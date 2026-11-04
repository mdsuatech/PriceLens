import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/currency/currency_preferences.dart';
import 'package:pricelens/history/scan_entry.dart';
import 'package:pricelens/scanner/scanner_screen.dart';

import 'support/memory_scan_store.dart';

void main() {
  testWidgets(
      'A manual correction updates its row and clearing requires confirmation',
      (tester) async {
    const channel = MethodChannel('google_mlkit_text_recognizer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final store = MemoryScanStore();
    await tester.pumpWidget(
        MaterialApp(home: ScannerScreen(demoRates: true, store: store)));
    await tester.pumpAndSettle();

    Future<void> tapText(String text) async {
      final target = find.text(text);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> enterPrice(String amount) async {
      await tester.enterText(find.byType(TextFormField), amount);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    await tapText('Ввести цену');
    await enterPrice('24,99');
    final savedId = store.entries.keys.single;
    final originalTime = store.entries.values.single.scannedAt;
    await tapText('Исправить');
    await enterPrice('19,99');
    expect(store.entries.keys.single, savedId);
    expect(store.entries.values.single.scannedAt, originalTime);
    expect(store.entries.values.single.origin, ScanOrigin.corrected);

    await tapText('Настройки');
    await tester.tap(find.byType(DropdownButton<TargetCurrency>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UAH').last);
    await tester.pumpAndSettle();
    expect(
        store.preferences.currencies, [TargetCurrency.uah, TargetCurrency.eur]);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0').last);
    await tester.pumpAndSettle();
    await tapText('Показывать EUR');
    expect(store.preferences.currencies, [TargetCurrency.uah]);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Показывать UAH'))
            .onChanged,
        isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText('История');
    expect(find.text('19,99 RON'), findsOneWidget);
    expect(find.textContaining('≈ 200 UAH'), findsOneWidget);
    expect(find.textContaining('≈ 4,00 EUR'), findsNothing);
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    await tapText('Отмена');
    expect(store.entries, hasLength(1));
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    await tapText('Очистить');
    expect(store.entries, isEmpty);
    expect(store.preferences.currencies, [TargetCurrency.uah]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
