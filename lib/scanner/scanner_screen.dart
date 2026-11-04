import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../currency/currency_preferences.dart';
import '../currency/exchange_rates.dart';
import '../currency/rates_banner.dart';
import '../currency/rates_controller.dart';
import '../history/history_screen.dart';
import '../history/scan_entry.dart';
import '../settings/settings_screen.dart';
import '../storage/scan_store.dart';
import 'price_entry_sheet.dart';
import 'price_parser.dart';
import 'price_result_card.dart';
import 'price_tracker.dart';
import 'scanner_controller.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen(
      {super.key,
      required this.demoRates,
      this.ratesController,
      this.store = const SqliteScanStore()});
  final bool demoRates;
  final RatesController? ratesController;
  final ScanStore store;

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

typedef _StoredScan = ({
  int? sceneId,
  DateTime scannedAt,
  ScanOrigin origin,
  Future<int?> id
});

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final _scanner = ScannerController();
  late final _rates =
      widget.demoRates ? null : widget.ratesController ?? RatesController();
  late final _changes = Listenable.merge([_scanner, _rates]);
  UsedRates? _fixedRates;
  _StoredScan? _automaticEntry;
  _StoredScan? _fixedEntry;
  Future<void> _historyWrites = Future.value();
  CurrencyPreferences _preferences = const CurrencyPreferences();
  late final Future<void> _preferencesLoaded;
  bool _localPageOpen = false;

  UsedRates get _currentRates => (
        snapshot: _rates?.snapshot,
        cached: _rates?.usingCache ?? false,
        demo: widget.demoRates,
      );

  UsedRates get _shownRates => _scanner.isFixed ? _fixedRates! : _currentRates;

  _StoredScan? get _currentEntry {
    if (_scanner.isFixed) return _fixedEntry;
    final eventId = _scanner.tracker.eventId;
    return eventId != null && _automaticEntry?.sceneId == eventId
        ? _automaticEntry
        : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner.addListener(_recordStable);
    _preferencesLoaded = _loadPreferences();
    unawaited(_scanner.resume());
    unawaited(_rates?.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_localPageOpen) unawaited(_scanner.handleLifecycle(state));
    if (state == AppLifecycleState.resumed) unawaited(_rates?.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.removeListener(_recordStable);
    _scanner.dispose();
    if (widget.ratesController == null) _rates?.dispose();
    super.dispose();
  }

  Future<void> _edit({bool blank = false}) async {
    if (_localPageOpen) return;
    final ratesAtEntry = blank ? _currentRates : _shownRates;
    final original = blank ? null : _scanner.tracker.candidate;
    final existing = blank ? null : _currentEntry;
    final scenePrice =
        _scanner.isFixed || _scanner.tracker.isLost ? null : original;
    _scanner.beginEditing();
    final candidate = await showModalBottomSheet<PriceCandidate>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PriceEntrySheet(
        initial: original,
        candidates: blank ? const [] : _scanner.tracker.analysis.candidates,
      ),
    );
    if (!mounted) return;
    if (candidate == null) {
      _scanner.cancelEditing();
    } else {
      final changed = original != null &&
          (original.amountBani != candidate.amountBani ||
              original.unit != candidate.unit ||
              original.kind != candidate.kind);
      final origin = original == null
          ? ScanOrigin.manual
          : changed
              ? ScanOrigin.corrected
              : existing?.origin == ScanOrigin.manual ||
                      existing?.origin == ScanOrigin.corrected
                  ? existing!.origin
                  : ScanOrigin.confirmed;
      _confirm(candidate, ratesAtEntry, origin,
          existing: existing, scenePrice: scenePrice);
    }
  }

  Future<void> _toggleTorch() async {
    if (!await _scanner.toggleTorch() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фонарик недоступен на этой камере')));
    }
  }

  Future<void> _openSettings() async {
    try {
      await AppSettings.openAppSettings();
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Откройте настройки доступа к камере вручную')));
      }
    }
  }

  void _fix() {
    if (_localPageOpen) return;
    final candidate = _scanner.tracker.candidate;
    if (_scanner.isFixed) {
      _scanner.continueScanning();
    } else if (candidate == null ||
        _scanner.tracker.status == ScanStatus.needsConfirmation ||
        _scanner.tracker.isLost) {
      unawaited(_edit());
    } else {
      _confirm(candidate, _currentRates, ScanOrigin.confirmed,
          existing: _currentEntry, scenePrice: candidate);
    }
  }

  void _recordStable() {
    final tracker = _scanner.tracker;
    final eventId = tracker.eventId;
    if (tracker.status != ScanStatus.stable ||
        tracker.isLost ||
        eventId == null ||
        _automaticEntry?.sceneId == eventId) return;
    final now = DateTime.now();
    final entry = ScanEntry.capture(
        tracker.candidate!, ScanOrigin.automatic, now, now, _currentRates);
    _automaticEntry = (
      sceneId: eventId,
      scannedAt: now,
      origin: entry.origin,
      id: _saveEntry(entry)
    );
  }

  void _confirm(PriceCandidate candidate, UsedRates rates, ScanOrigin origin,
      {_StoredScan? existing, PriceCandidate? scenePrice}) {
    final now = DateTime.now();
    var sceneId = existing?.sceneId;
    if (sceneId == null && scenePrice != null && !scenePrice.bounds.isEmpty) {
      sceneId = _scanner.tracker.rememberScene(scenePrice, now);
    }
    if (sceneId == null) _scanner.tracker.forgetScene();
    final entry = ScanEntry.capture(
        candidate, origin, existing?.scannedAt ?? now, now, rates);
    final saved = (
      sceneId: sceneId,
      scannedAt: entry.scannedAt,
      origin: origin,
      id: _saveEntry(entry, previous: existing?.id)
    );
    if (sceneId != null) _automaticEntry = saved;
    _fixedEntry = saved;
    _fixedRates = rates;
    _scanner.fix(candidate);
  }

  Future<int?> _saveEntry(ScanEntry entry, {Future<int?>? previous}) {
    final saved = _historyWrites.then((_) async {
      final id = await previous;
      try {
        if (id == null) return await widget.store.insert(entry);
        await widget.store.update(id, entry);
        return id;
      } on DatabaseException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Не удалось сохранить цену в истории')));
        }
        return id;
      }
    });
    _historyWrites = saved.then((_) {});
    return saved;
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await widget.store.loadPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } on DatabaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось загрузить настройки валют')));
      }
    }
  }

  Future<void> _openLocalPage({required bool settings}) async {
    if (_localPageOpen) return;
    _localPageOpen = true;
    try {
      await _scanner.pause();
      await Future.wait([_historyWrites, _preferencesLoaded]);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => settings
              ? SettingsScreen(
                  store: widget.store,
                  initial: _preferences,
                  rates: _rates,
                  onChanged: (preferences) {
                    if (mounted) setState(() => _preferences = preferences);
                  })
              : HistoryScreen(store: widget.store, preferences: _preferences)));
    } finally {
      _localPageOpen = false;
      final state = WidgetsBinding.instance.lifecycleState;
      if (mounted && (state == null || state == AppLifecycleState.resumed)) {
        unawaited(_scanner.resume());
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        resizeToAvoidBottomInset: false,
        body: AnimatedBuilder(
          animation: _changes,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              if (_scanner.cameraStatus == CameraStatus.ready)
                _cameraPreview()
              else
                const ColoredBox(color: Color(0xFF1B2125)),
              const IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xD9101518),
                    Color(0x00101518),
                    Color(0xE6101518)
                  ],
                  stops: [0, 0.4, 1],
                ),
              ))),
              SafeArea(
                  child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
                          child: Row(children: [
                            const Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('PriceLens',
                                      style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.8)),
                                  Text('Цены в привычной валюте',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white54)),
                                ])),
                            IconButton(
                              onPressed:
                                  _scanner.cameraStatus == CameraStatus.ready &&
                                          _scanner.torchAvailable
                                      ? _toggleTorch
                                      : null,
                              tooltip: _scanner.torchOn
                                  ? 'Выключить фонарик'
                                  : 'Включить фонарик',
                              isSelected: _scanner.torchOn,
                              icon: const Icon(Icons.flashlight_off_outlined),
                              selectedIcon: const Icon(Icons.flashlight_on),
                            ),
                            IconButton(
                              onPressed: _scanner.canSwitchCamera &&
                                      _scanner.cameraStatus ==
                                          CameraStatus.ready
                                  ? _scanner.switchCamera
                                  : null,
                              tooltip: 'Переключить камеру',
                              icon: const Icon(Icons.cameraswitch_outlined),
                            ),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RatesBanner(controller: _rates),
                        ),
                        SizedBox(
                          height: _scanner.cameraStatus == CameraStatus.ready
                              ? 112
                              : 200,
                          child: _scanner.cameraStatus == CameraStatus.ready
                              ? null
                              : _cameraPreview(),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: PriceResultCard(
                            candidate: _scanner.tracker.candidate,
                            status: _scanner.tracker.status,
                            rates: widget.demoRates
                                ? demoQuote
                                : _shownRates.snapshot?.quote,
                            preferences: _preferences,
                            rateNote: _scanner.isFixed &&
                                    _fixedRates?.snapshot != null
                                ? 'Курс от ${formatRateDate(_fixedRates!.snapshot!.dataAsOf)}'
                                : null,
                            isLost: _scanner.tracker.isLost,
                            message: _scanner.tracker.analysis.message,
                            onEdit: _edit,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Row(children: [
                            Expanded(
                                child: OutlinedButton.icon(
                              onPressed: () => _edit(blank: true),
                              icon:
                                  const Icon(Icons.keyboard_outlined, size: 20),
                              label: const Text('Ввести цену',
                                  textAlign: TextAlign.center),
                            )),
                            const SizedBox(width: 12),
                            Expanded(
                                child: FilledButton.icon(
                              onPressed: _fix,
                              icon: Icon(
                                  _scanner.isFixed
                                      ? Icons.play_arrow_rounded
                                      : Icons.center_focus_strong,
                                  size: 20),
                              label: Text(
                                  _scanner.isFixed
                                      ? 'Продолжить'
                                      : 'Фиксировать',
                                  textAlign: TextAlign.center),
                            )),
                          ]),
                        ),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                  onPressed: () =>
                                      _openLocalPage(settings: false),
                                  icon: const Icon(Icons.history),
                                  label: const Text('История')),
                              TextButton.icon(
                                  onPressed: () =>
                                      _openLocalPage(settings: true),
                                  icon: const Icon(Icons.settings_outlined),
                                  label: const Text('Настройки')),
                            ]),
                      ],
                    ),
                  ),
                ),
              )),
            ],
          ),
        ),
      );

  Widget _cameraPreview() {
    final camera = _scanner.camera;
    if (_scanner.cameraStatus == CameraStatus.ready && camera != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / camera.value.aspectRatio,
              child: Stack(fit: StackFit.expand, children: [
                CameraPreview(camera),
                IgnorePointer(
                    child: CustomPaint(
                        painter: _PriceOutline(
                  _scanner.tracker.candidate?.bounds,
                  _scanner.tracker.status == ScanStatus.stable ||
                      _scanner.isFixed,
                ))),
              ]),
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: const Color(0xFF1B2125),
          borderRadius: BorderRadius.circular(24)),
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_scanner.cameraStatus == CameraStatus.loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Открываем камеру…'),
            ] else ...[
              const Icon(Icons.no_photography_outlined,
                  size: 40, color: Colors.white38),
              const SizedBox(height: 12),
              Text(_scanner.errorMessage ?? 'Камера недоступна',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              if (_scanner.cameraStatus == CameraStatus.denied)
                TextButton(
                    onPressed: _openSettings,
                    child: const Text('Открыть настройки')),
              if (_scanner.cameraStatus != CameraStatus.restricted)
                TextButton(
                    onPressed: _scanner.resume, child: const Text('Повторить')),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PriceOutline extends CustomPainter {
  const _PriceOutline(this.bounds, this.stable);
  final Rect? bounds;
  final bool stable;

  @override
  void paint(Canvas canvas, Size size) {
    final box = bounds;
    final rect = box == null || box.isEmpty
        ? Rect.fromLTWH(size.width * 0.12, size.height * 0.35,
            size.width * 0.76, size.height * 0.2)
        : Rect.fromLTRB(box.left * size.width, box.top * size.height,
                box.right * size.width, box.bottom * size.height)
            .inflate(5);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = stable ? const Color(0xFFCBF88B) : Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PriceOutline oldDelegate) =>
      bounds != oldDelegate.bounds || stable != oldDelegate.stable;
}
