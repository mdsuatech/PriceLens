import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pricelens/currency/currency_preferences.dart';
import 'package:pricelens/currency/exchange_rates.dart';
import 'package:pricelens/currency/money.dart';
import 'package:pricelens/currency/rates_cache.dart';
import 'package:pricelens/currency/rates_controller.dart';
import 'package:pricelens/history/scan_entry.dart';
import 'package:pricelens/main.dart' as app;
import 'package:pricelens/scanner/price_parser.dart';
import 'package:pricelens/storage/scan_store.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/rates_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SQLite upgrades v1 in place and keeps the latest 100 events',
      (tester) async {
    final path =
        'pricelens_history_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final now = DateTime.utc(2026, 11, 3);
    final oldQuote = rateFixture(now);
    final old = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE rate_state (id INTEGER PRIMARY KEY CHECK(id = 1), snapshot TEXT, last_automatic_attempt INTEGER)');
      await db.insert('rate_state', {
        'id': 1,
        'snapshot': oldQuote.toCache(),
        'last_automatic_attempt': now.millisecondsSinceEpoch
      });
    });
    await old.close();

    final store = SqliteScanStore(path: path);
    final cache = SqliteRatesCache(path: path);
    try {
      expect(await store.history(), isEmpty);
      expect((await store.loadPreferences()).currencies,
          [TargetCurrency.eur, TargetCurrency.uah]);
      expect((await cache.load()).snapshot?.quote, oldQuote.quote);
      expect((await cache.load()).lastAutomaticAttempt, now);
      const savedPreferences = CurrencyPreferences(
          showEur: false, primary: TargetCurrency.uah, decimals: 0);
      await store.savePreferences(savedPreferences);

      ScanEntry entry(int bani, ScanOrigin origin) => ScanEntry.capture(
          PriceCandidate(amountBani: bani, bounds: Rect.zero),
          origin,
          now,
          now,
          (snapshot: oldQuote, cached: true, demo: false));
      for (var bani = 1; bani <= 101; bani++) {
        await store.insert(entry(bani, ScanOrigin.automatic));
      }
      final entries = await store.history();
      expect(entries, hasLength(100));
      expect(entries.last.amountBani, 2);
      final correctedId = entries.first.id!;
      await store.update(correctedId, entry(2499, ScanOrigin.corrected));
      final newQuote =
          rateFixture(now.add(const Duration(days: 1)), eur: 0.4, uah: 8);
      await cache.save(newQuote);

      await (await openDatabase(path)).close();
      final reopened = SqliteScanStore(path: path);
      final restored = await reopened.history();
      expect(restored, hasLength(100));
      expect(restored.first.id, correctedId);
      expect(restored.first.origin, ScanOrigin.corrected);
      expect(formatExactAmount(restored.first.eurAmount!, 2), '5,00');
      expect(formatExactAmount(restored.first.uahAmount!, 2), '249,90');
      expect(restored.first.rates.snapshot?.quote, oldQuote.quote);
      expect(
          (await reopened.loadPreferences()).currencies, [TargetCurrency.uah]);
      expect((await reopened.loadPreferences()).decimals, 0);
      await reopened.clearHistory();
      expect(await reopened.history(), isEmpty);
      expect(
          (await reopened.loadPreferences()).currencies, [TargetCurrency.uah]);
      expect((await cache.load()).snapshot?.quote, newQuote.quote);
    } finally {
      await (await openDatabase(path)).close();
      await deleteDatabase(path);
    }
  });

  testWidgets(
      'SQLite keeps both quotes after closing the database and losing the network',
      (tester) async {
    final path =
        'pricelens_rates_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final now = DateTime.utc(2026, 11, 3);
    final initial = RatesController(
        cache: SqliteRatesCache(path: path),
        clock: () => now,
        fetch: () async => rateFixture(now));
    RatesController? restarted;
    try {
      await initial.refresh();
      expect(initial.storageWarning, isNull);
      await (await openDatabase(path)).close();
      restarted = RatesController(
          cache: SqliteRatesCache(path: path),
          clock: () => now.add(const Duration(days: 2)),
          fetch: () async =>
              throw const RatesRequestException('Test network unavailable'));
      await restarted.refresh();
      expect(restarted.usingCache, isTrue);
      expect(restarted.isStale, isTrue);
      expect(restarted.snapshot?.dataAsOf, now);
      expect(convertBani(2499, restarted.snapshot!.quote.eurPerRon), '5,00');
      expect(convertBani(2499, restarted.snapshot!.quote.uahPerRon), '249,90');
    } finally {
      initial.dispose();
      restarted?.dispose();
      await (await openDatabase(path)).close();
      await deleteDatabase(path);
    }
  });

  testWidgets('Bundled OCR reads a generated label on the device',
      (tester) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 900, 400), Paint()..color = Colors.white);
    final label = TextPainter(
      text: const TextSpan(
          text: '24,99 LEI',
          style: TextStyle(
              color: Colors.black, fontSize: 100, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(60, 120));
    final picture = recorder.endRecording();
    final image = await picture.toImage(900, 400);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final input = InputImage.fromBitmap(
        bitmap: bytes.buffer.asUint8List(), width: 900, height: 400);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(input);
      final result = const PriceParser().analyze([
        for (final block in text.blocks)
          for (final line in block.lines) OcrLine(line.text, line.boundingBox),
      ]);
      expect(result.selected?.amountBani, 2499);
      expect(result.needsConfirmation, isFalse);
    } finally {
      await recognizer.close();
      image.dispose();
      picture.dispose();
      label.dispose();
    }
  });

  testWidgets(
      'Camera preview, manual correction and two currencies work together',
      (tester) async {
    await app.main();
    // A cold software-rendered emulator can take much longer to open Camera2.
    // This is an initialization timeout, not the product's OCR latency target.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (find.byType(CameraPreview).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(CameraPreview), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '));
    // Let live frames reach native OCR; a format error must not hide the preview.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(find.textContaining('ТЕСТОВЫЕ КУРСЫ'), findsOneWidget);

    await tester.ensureVisible(find.text('Ввести цену'));
    await tester.tap(find.text('Ввести цену'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '24,99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('24,99 RON'), findsOneWidget);
    expect(find.text('≈ 5,00'), findsOneWidget);
    expect(find.text('≈ 249,90'), findsOneWidget);
    expect(find.text('ПОДТВЕРЖДЕНО ВАМИ'), findsOneWidget);

    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('android-prototype-conversion');

    await tester.ensureVisible(find.text('Продолжить'));
    await tester.tap(find.text('Продолжить'));
    await tester.pump();
    expect(find.text('ПОДТВЕРЖДЕНО ВАМИ'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
