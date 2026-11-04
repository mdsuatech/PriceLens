String formatBani(int amountBani) => _formatMinor(BigInt.from(amountBani), 2);

/// The rate is target-currency units per one RON. Round once, half-up.
String convertBani(int amountBani, String perRon, {int decimals = 2}) {
  return formatExactAmount(exactConversion(amountBani, perRon), decimals);
}

String exactConversion(int amountBani, String perRon) {
  if (amountBani < 0) throw ArgumentError.value(amountBani, 'amountBani');
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(perRon)) {
    throw ArgumentError.value(perRon, 'perRon');
  }
  final parts = perRon.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final numerator = BigInt.parse('${parts[0]}$fraction');
  if (numerator <= BigInt.zero) {
    throw ArgumentError.value(perRon, 'perRon');
  }
  final product = BigInt.from(amountBani) * numerator;
  return _formatMinor(product, fraction.length + 2).replaceFirst(',', '.');
}

String formatExactAmount(String amount, int decimals) {
  if (decimals != 0 && decimals != 2) {
    throw ArgumentError.value(decimals, 'decimals');
  }
  final parts = amount.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  final divisor = BigInt.from(10).pow(fraction.length);
  final product =
      BigInt.parse('${parts[0]}$fraction') * BigInt.from(10).pow(decimals);
  final rounded = (product * BigInt.two + divisor) ~/ (divisor * BigInt.two);
  return _formatMinor(rounded, decimals);
}

String _formatMinor(BigInt value, int decimals) {
  if (decimals == 0) return value.toString();
  final digits = value.toString().padLeft(decimals + 1, '0');
  return '${digits.substring(0, digits.length - decimals)},${digits.substring(digits.length - decimals)}';
}
