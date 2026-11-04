import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/currency/money.dart';

void main() {
  test('Converts without binary floating point errors', () {
    expect(convertBani(2499, '0.2'), '5,00');
    expect(convertBani(2499, '10'), '249,90');
    expect(convertBani(129900, '0.2'), '259,80');
    expect(convertBani(10, '0.2'), '0,02');
  });

  test('Half-up rounding at the exact half', () {
    expect(convertBani(5, '0.1'), '0,01');
    expect(convertBani(5, '10', decimals: 0), '1');
    expect(convertBani(100, '0.004999999999'), '0,00');
    expect(convertBani(100, '0.005000000001'), '0,01');
  });

  test('Zero and large values retain precision', () {
    expect(convertBani(0, '10'), '0,00');
    expect(convertBani(99999999, '10'), '9999999,90');
    expect(formatBani(99), '0,99');
    expect(formatBani(129900), '1299,00');
  });

  test('Rejects invalid rates instead of displaying a fabricated result', () {
    for (final rate in ['0', '-1', 'NaN', 'Infinity', '', '1,2']) {
      expect(() => convertBani(100, rate), throwsArgumentError);
    }
  });
}
