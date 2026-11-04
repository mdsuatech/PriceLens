import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/scanner/scanner_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_text_recognizer');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'Permission dialog preserves the initialization and does not request again on resume',
      () async {
    final scanner = ScannerController();
    var changes = 0;
    scanner.addListener(() => changes++);
    final initializing = scanner.resume();
    final inactive = scanner.handleLifecycle(AppLifecycleState.inactive);
    expect(scanner.isActive, isTrue);
    final resumed = scanner.handleLifecycle(AppLifecycleState.resumed);
    expect(changes, 1,
        reason: 'The same initialization must handle the permission result');
    await Future.wait([initializing, inactive, resumed]);
    scanner.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('Going to background still stops a pending initialization', () async {
    final scanner = ScannerController();
    final initializing = scanner.resume();
    final paused = scanner.handleLifecycle(AppLifecycleState.paused);
    expect(scanner.isActive, isFalse);
    await Future.wait([initializing, paused]);
    await scanner.handleLifecycle(AppLifecycleState.resumed);
    expect(scanner.isActive, isTrue);
    scanner.dispose();
    await Future<void>.delayed(Duration.zero);
  });
}
