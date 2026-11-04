import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/scanner/price_parser.dart';

void main() {
  const parser = PriceParser();
  PriceAnalysis read(String text) => parser.analyze([
        OcrLine(text, const Rect.fromLTWH(10, 20, 200, 40)),
      ]);

  group('Price formats', () {
    for (final entry in {
      '24,99 RON': 2499,
      '24,99RON': 2499,
      '24.99 RON': 2499,
      '1.299,00 RON': 129900,
      '1 299,00 LEI': 129900,
      '1\u00a0299,00 lei': 129900,
      '15,99': 1599,
      '24 LEI': 2400,
      '24,9 RON': 2490,
      '0,99 RON': 99,
    }.entries) {
      test(entry.key, () {
        final result = read(entry.key);
        expect(result.selected?.amountBani, entry.value);
        expect(result.needsConfirmation, isFalse);
      });
    }

    for (final text in [
      '-20%',
      '500 g',
      '1 L',
      '03.11.2026',
      '5941234567890',
      '12,3456',
      '1.29,00',
      '1,299.00',
      'O,99 RON',
      '-24,99 RON',
    ]) {
      test('Does not invent a price from $text', () {
        expect(read(text).candidates, isEmpty);
      });
    }

    test('Foreign currency never uses the RON assumption', () {
      final result = read('24,99 EUR');
      expect(result.candidates, isEmpty);
      expect(result.foreignCurrency, isTrue);
      expect(read('24,99EUR').candidates, isEmpty);
    });

    test('A detached foreign currency must not turn into assumed RON', () {
      final result = parser.analyze(const [
        OcrLine('24,99', Rect.fromLTWH(0, 0, 100, 30)),
        OcrLine('EUR', Rect.fromLTWH(100, 0, 50, 30)),
      ]);
      expect(result.candidates, isEmpty);
      expect(result.foreignCurrency, isTrue);
    });

    test('RON assumption is explicit', () {
      expect(read('15,99').selected?.currencyAssumed, isTrue);
      expect(read('15,99 LEI').selected?.currencyAssumed, isFalse);
    });

    for (final text in ['1.299 RON', '1299', '0,00 RON']) {
      test('Requires confirmation: $text', () {
        expect(read(text).needsConfirmation, isTrue);
      });
    }
  });

  group('Price selection', () {
    PriceAnalysis lines(List<String> texts) => parser.analyze([
          for (var i = 0; i < texts.length; i++)
            OcrLine(texts[i], Rect.fromLTWH(10, i * 50, 200, 40)),
        ]);

    test('Does not choose the minimum of two ordinary prices', () {
      final result = lines(['29,99 LEI', '19,99 LEI']);
      expect(result.needsConfirmation, isTrue);
      expect(result.candidates, hasLength(2));
    });

    test('Excludes a labelled old price', () {
      final result = lines(['PRET VECHI 29,99 LEI', '19,99 LEI']);
      expect(result.selected?.amountBani, 1999);
      expect(result.needsConfirmation, isFalse);
    });

    test('Main price wins over price per kilogram', () {
      final result = lines(['9,99 LEI', '19,98 LEI/kg']);
      expect(result.selected?.amountBani, 999);
      expect(result.selected?.unit, PriceUnit.item);
      expect(result.needsConfirmation, isFalse);
    });

    test('A unit price keeps its meaning and requires confirmation', () {
      final result = read('19,98 LEI/kg');
      expect(result.selected?.unit, PriceUnit.kg);
      expect(result.needsConfirmation, isTrue);
    });

    test('Conditional discount does not replace ordinary price', () {
      final result = lines(['24,99 LEI', 'CU CARD 19,99 LEI']);
      expect(result.selected?.amountBani, 2499);
      expect(result.needsConfirmation, isFalse);
    });

    test('A detached promotion condition is not silently ignored', () {
      final result = lines(['CU CARD', '19,99 LEI']);
      expect(result.needsConfirmation, isTrue);
    });

    test('Separated integers are not silently joined', () {
      expect(read('24 99 LEI').needsConfirmation, isTrue);
    });

    test('Invalid long decimal cannot be accepted by matching a prefix', () {
      expect(read('12,3456 LEI').candidates, isEmpty);
    });
  });

  test('Manual input is stricter than OCR input', () {
    expect(parseManualPrice('24,99'), 2499);
    expect(parseManualPrice('24.9'), 2490);
    expect(parseManualPrice('24'), 2400);
    expect(parseManualPrice('0'), 0);
    for (final value in ['', '-1', '1.299', '1 299', '24,999', 'RON', 'NaN']) {
      expect(parseManualPrice(value), isNull, reason: value);
    }
  });
}
