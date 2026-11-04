import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/currency/exchange_rates.dart';
import 'package:pricelens/currency/rates_controller.dart';
import 'package:pricelens/scanner/price_entry_sheet.dart';
import 'package:pricelens/scanner/price_parser.dart';
import 'package:pricelens/scanner/price_result_card.dart';
import 'package:pricelens/scanner/price_tracker.dart';
import 'package:pricelens/scanner/scanner_screen.dart';

import 'support/rates_fixture.dart';
import 'support/memory_scan_store.dart';

void main() {
  const price = PriceCandidate(amountBani: 2499, bounds: Rect.zero);

  testWidgets(
      'Refreshing rates leaves a confirmed price tied to its previous quote',
      (tester) async {
    const channel = MethodChannel('google_mlkit_text_recognizer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final now = DateTime.utc(2026, 11, 3);
    final store = MemoryRatesCache()..saved = rateFixture(now);
    final controller = RatesController(
        cache: store,
        clock: () => now,
        fetch: () async => rateFixture(now, eur: 0.4, uah: 8));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ScannerScreen(
            demoRates: false,
            ratesController: controller,
            store: MemoryScanStore())));
    await tester.pumpAndSettle();
    expect(find.text('Rates By Exchange Rate API'), findsOneWidget);

    Future<void> enterPrice() async {
      await tester.ensureVisible(find.text('Ввести цену'));
      await tester.tap(find.text('Ввести цену'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '24,99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    await enterPrice();
    expect(find.text('≈ 5,00'), findsOneWidget);
    final banner = find.textContaining('Сохранённый курс от');
    await tester.ensureVisible(banner);
    await tester.tap(banner);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.pumpAndSettle();
    expect(find.text('1 RON = 0,4 EUR'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('≈ 5,00'), findsOneWidget);
    expect(find.text('≈ 249,90'), findsOneWidget);
    await enterPrice();
    expect(find.text('≈ 10,00'), findsOneWidget);
    expect(find.text('≈ 199,92'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'Full scanner keeps retry and manual conversion usable without a camera',
      (tester) async {
    const channel = MethodChannel('google_mlkit_text_recognizer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: ScannerScreen(demoRates: true, store: MemoryScanStore())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Повторить'));
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ввести цену'));
    await tester.tap(find.text('Ввести цену'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '24,99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('≈ 5,00'), findsOneWidget);
    expect(find.text('≈ 249,90'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Explains unsupported currency without inventing a price',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PriceResultCard(
      candidate: null,
      status: ScanStatus.searching,
      rates: demoQuote,
      message: 'Поддерживается цена в RON',
      onEdit: () {},
    ))));
    expect(find.text('Поддерживается цена в RON'), findsOneWidget);
    expect(find.text('≈ 5,00'), findsNothing);
  });

  Widget card({bool demo = true, ScanStatus status = ScanStatus.stable}) =>
      MaterialApp(
          home: Scaffold(
              body: PriceResultCard(
        candidate: price,
        status: status,
        rates: demo ? demoQuote : null,
        onEdit: () {},
      )));

  testWidgets('Shows both correctly rounded conversions after stabilization',
      (tester) async {
    await tester.pumpWidget(card());
    expect(find.text('24,99 RON'), findsOneWidget);
    expect(find.text('≈ 5,00'), findsOneWidget);
    expect(find.text('≈ 249,90'), findsOneWidget);
    expect(find.text('СТАБИЛЬНО'), findsOneWidget);
  });

  testWidgets('Unconfirmed price is not presented as a trusted conversion',
      (tester) async {
    await tester.pumpWidget(card(status: ScanStatus.needsConfirmation));
    expect(find.text('НУЖНА ПРОВЕРКА'), findsOneWidget);
    expect(find.text('≈ 5,00'), findsNothing);
    expect(find.text('Проверить цену'), findsOneWidget);
  });

  testWidgets('No rates means no invented conversions', (tester) async {
    await tester.pumpWidget(card(demo: false));
    expect(find.textContaining('Для пересчёта нужен загруженный курс'),
        findsOneWidget);
    expect(find.text('≈ 5,00'), findsNothing);
  });

  testWidgets('Unit remains attached to every displayed amount',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PriceResultCard(
      candidate: const PriceCandidate(
          amountBani: 2499, bounds: Rect.zero, unit: PriceUnit.kg),
      status: ScanStatus.fixed,
      rates: demoQuote,
      onEdit: () {},
    ))));
    expect(find.text('24,99 RON / кг'), findsOneWidget);
    expect(find.text('≈ 5,00 / кг'), findsOneWidget);
    expect(find.text('≈ 249,90 / кг'), findsOneWidget);
  });

  Future<void> openEntry(
      WidgetTester tester, void Function(PriceCandidate?) onResult) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () async =>
            onResult(await showModalBottomSheet<PriceCandidate>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const PriceEntrySheet(),
        )),
        child: const Text('Ввести'),
      ),
    ))));
    await tester.tap(find.text('Ввести'));
    await tester.pumpAndSettle();
  }

  testWidgets('Manual entry validates before returning a price',
      (tester) async {
    PriceCandidate? submitted;
    await openEntry(tester, (value) => submitted = value);
    await tester.enterText(find.byType(TextFormField), '24,999');
    await tester.tap(find.text('Подтвердить цену'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(
        find.text('Введите число с 0–2 знаками после запятой'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '24,99');
    await tester.tap(find.text('Подтвердить цену'));
    await tester.pumpAndSettle();
    expect(submitted?.amountBani, 2499);
  });

  testWidgets('A zero price requires an explicit acknowledgement',
      (tester) async {
    PriceCandidate? submitted;
    await openEntry(tester, (value) => submitted = value);
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Подтвердить цену'));
    await tester.tap(find.text('Подтвердить цену'));
    await tester.pumpAndSettle();
    expect(submitted?.amountBani, 0);
  });

  testWidgets('Card remains readable on a narrow screen with larger text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Scaffold(
          body: SingleChildScrollView(
              child: PriceResultCard(
        candidate: price,
        status: ScanStatus.stable,
        rates: demoQuote,
        onEdit: () {},
      ))),
    )));
    expect(tester.takeException(), isNull);
  });
}
