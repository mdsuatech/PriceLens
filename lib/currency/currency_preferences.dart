enum TargetCurrency { eur, uah }

class CurrencyPreferences {
  const CurrencyPreferences({
    this.showEur = true,
    this.showUah = true,
    this.primary = TargetCurrency.eur,
    this.decimals = 2,
  });

  final bool showEur;
  final bool showUah;
  final TargetCurrency primary;
  final int decimals;

  bool shows(TargetCurrency currency) =>
      currency == TargetCurrency.eur ? showEur : showUah;

  List<TargetCurrency> get currencies => [
        primary,
        for (final currency in TargetCurrency.values)
          if (currency != primary && shows(currency)) currency,
      ];

  CurrencyPreferences withVisibility(TargetCurrency currency, bool visible) {
    final eur = currency == TargetCurrency.eur ? visible : showEur;
    final uah = currency == TargetCurrency.uah ? visible : showUah;
    if (!eur && !uah) return this;
    final nextPrimary = !visible && currency == primary
        ? (eur ? TargetCurrency.eur : TargetCurrency.uah)
        : primary;
    return CurrencyPreferences(
        showEur: eur, showUah: uah, primary: nextPrimary, decimals: decimals);
  }

  CurrencyPreferences withPrimary(TargetCurrency currency) => shows(currency)
      ? CurrencyPreferences(
          showEur: showEur,
          showUah: showUah,
          primary: currency,
          decimals: decimals)
      : this;

  CurrencyPreferences withDecimals(int value) => CurrencyPreferences(
      showEur: showEur, showUah: showUah, primary: primary, decimals: value);
}
