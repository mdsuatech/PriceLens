import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'frame_gate.dart';
import 'price_parser.dart';
import 'price_tracker.dart';

enum CameraStatus { loading, ready, denied, restricted, unavailable, error }

class ScannerController extends ChangeNotifier {
  final tracker = PriceTracker();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _gate = FrameGate();
  CameraController? camera;
  CameraStatus cameraStatus = CameraStatus.loading;
  String? errorMessage;
  bool torchOn = false;
  bool torchAvailable = true;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  int _session = 0;
  bool _active = false;
  bool _editing = false;
  bool _disposed = false;
  Future<void> _cameraQueue = Future.value();
  Future<void>? _inFlight;
  Timer? _expiry;

  bool get canSwitchCamera => _cameras.length > 1;
  bool get isFixed => tracker.status == ScanStatus.fixed;
  bool get isActive => _active;

  Future<void> handleLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return _active ? Future.value() : resume();
    }
    // The system permission dialog temporarily removes focus during initialize.
    // Preserve that request so denial is shown once, rather than requesting again.
    if (state == AppLifecycleState.inactive &&
        cameraStatus == CameraStatus.loading) {
      return Future.value();
    }
    return pause();
  }

  Future<void> resume() {
    _active = true;
    _expiry ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_editing && tracker.expire(DateTime.now())) _emit();
    });
    return _reconfigure();
  }

  Future<void> pause() {
    _active = false;
    _expiry?.cancel();
    _expiry = null;
    return _reconfigure();
  }

  Future<void> switchCamera() {
    if (!canSwitchCamera) return Future.value();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    return _reconfigure();
  }

  Future<void> _reconfigure() {
    final session = ++_session;
    _gate.invalidate();
    tracker.reset();
    errorMessage = null;
    cameraStatus = CameraStatus.loading;
    torchOn = false;
    _emit();
    // Camera initialization/disposal must not overlap with lifecycle changes.
    _cameraQueue = _cameraQueue.then((_) async {
      await _disposeCamera();
      if (!_isCurrent(session)) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        cameraStatus = CameraStatus.unavailable;
        errorMessage = 'Сканирование камерой доступно на Android и iPhone';
        _emit();
        return;
      }
      try {
        if (_cameras.isEmpty) {
          _cameras = await availableCameras();
          final back = _cameras.indexWhere(
              (value) => value.lensDirection == CameraLensDirection.back);
          if (back >= 0) _cameraIndex = back;
        }
        if (!_isCurrent(session)) return;
        if (_cameras.isEmpty) {
          cameraStatus = CameraStatus.unavailable;
          errorMessage = 'Камера не найдена. Можно ввести цену вручную';
          _emit();
          return;
        }
        final description = _cameras[_cameraIndex];
        final current = CameraController(
          description,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
        );
        camera = current;
        await current.initialize();
        if (!_isCurrent(session)) return;
        await current.lockCaptureOrientation(DeviceOrientation.portraitUp);
        if (!_isCurrent(session)) return;
        torchAvailable = description.lensDirection == CameraLensDirection.back;
        await current.startImageStream((image) => _onFrame(image, session));
        if (!_isCurrent(session)) return;
        cameraStatus = CameraStatus.ready;
        _emit();
      } on CameraException catch (error) {
        if (!_isCurrent(session)) return;
        cameraStatus = switch (error.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' =>
            CameraStatus.denied,
          'CameraAccessRestricted' => CameraStatus.restricted,
          _ => CameraStatus.error,
        };
        errorMessage = switch (cameraStatus) {
          CameraStatus.denied =>
            'Разрешите доступ к камере в настройках телефона',
          CameraStatus.restricted =>
            'Доступ к камере ограничен настройками устройства',
          _ => 'Не удалось запустить камеру. Попробуйте ещё раз',
        };
        await _disposeCamera();
        _emit();
      } on PlatformException {
        if (!_isCurrent(session)) return;
        cameraStatus = CameraStatus.error;
        errorMessage = 'Не удалось подключить камеру. Попробуйте ещё раз';
        await _disposeCamera();
        _emit();
      }
    });
    return _cameraQueue;
  }

  bool _isCurrent(int session) => !_disposed && _active && session == _session;

  Future<void> _disposeCamera() async {
    final previous = camera;
    camera = null;
    if (previous != null) {
      try {
        if (previous.value.isStreamingImages) await previous.stopImageStream();
      } finally {
        await previous.dispose();
      }
    }
  }

  void _onFrame(CameraImage image, int session) {
    if (!_isCurrent(session) ||
        _editing ||
        isFixed ||
        cameraStatus != CameraStatus.ready) return;
    final ticket = _gate.tryBegin(DateTime.now());
    if (ticket == null) return;
    _inFlight = _process(image, session, ticket);
  }

  Future<void> _process(CameraImage image, int session, int ticket) async {
    PriceAnalysis? analysis;
    String? failure;
    try {
      final description = camera!.description;
      final rotation = _rotation(description, camera!.value.deviceOrientation);
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (image.planes.length != 1 ||
          rotation == null ||
          (Platform.isAndroid && format != InputImageFormat.nv21) ||
          (Platform.isIOS && format != InputImageFormat.bgra8888)) {
        throw const FormatException('Unsupported camera frame');
      }
      final plane = image.planes.first;
      final input = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final text = await _recognizer.processImage(input);
      final sideways = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final size = Platform.isAndroid && sideways
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());
      final lines = [
        for (final block in text.blocks)
          for (final line in block.lines)
            OcrLine(
                line.text,
                _normalizedBounds(
                    line.boundingBox, size, description.lensDirection)),
      ];
      analysis = const PriceParser().analyze(lines);
    } on FormatException {
      failure =
          'Эта камера передаёт неподдерживаемый формат. Попробуйте другую камеру';
    } on PlatformException {
      failure =
          'Не удалось распознать изображение. Попробуйте запустить камеру снова';
    } finally {
      final current = _gate.finish(ticket);
      if (current && _isCurrent(session) && !_editing && !isFixed) {
        if (failure != null) {
          cameraStatus = CameraStatus.error;
          errorMessage = failure;
        } else if (analysis != null) {
          tracker.observe(analysis, DateTime.now());
        }
        _emit();
      }
    }
  }

  void beginEditing() {
    _editing = true;
    _gate.invalidate();
  }

  void fix(PriceCandidate candidate) {
    _gate.invalidate();
    _editing = false;
    tracker.fix(candidate);
    _emit();
  }

  void continueScanning() {
    _gate.invalidate();
    _editing = false;
    tracker.resumeAfterFix(DateTime.now());
    _emit();
  }

  void cancelEditing() {
    _gate.invalidate();
    _editing = false;
    tracker.cancelEditing(DateTime.now());
    _emit();
  }

  Future<bool> toggleTorch() async {
    final current = camera;
    if (current == null || cameraStatus != CameraStatus.ready) return false;
    try {
      final enabled = !torchOn;
      await current.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
      if (current != camera || _disposed) return false;
      torchOn = enabled;
      _emit();
      return true;
    } on CameraException {
      torchAvailable = false;
      torchOn = false;
      _emit();
      return false;
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _session++;
    _gate.invalidate();
    _expiry?.cancel();
    _cameraQueue = _cameraQueue.then((_) async {
      await _disposeCamera();
      await _inFlight;
      await _recognizer.close();
    });
    super.dispose();
  }
}

InputImageRotation? _rotation(
    CameraDescription camera, DeviceOrientation orientation) {
  if (Platform.isIOS) {
    return InputImageRotationValue.fromRawValue(camera.sensorOrientation);
  }
  final compensation = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final degrees = camera.lensDirection == CameraLensDirection.front
      ? (camera.sensorOrientation + compensation) % 360
      : (camera.sensorOrientation - compensation + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees);
}

Rect _normalizedBounds(Rect bounds, Size image, CameraLensDirection lens) {
  final left = bounds.left / image.width;
  final right = bounds.right / image.width;
  return Rect.fromLTRB(
    (lens == CameraLensDirection.front ? 1 - right : left).clamp(0, 1),
    (bounds.top / image.height).clamp(0, 1),
    (lens == CameraLensDirection.front ? 1 - left : right).clamp(0, 1),
    (bounds.bottom / image.height).clamp(0, 1),
  );
}
