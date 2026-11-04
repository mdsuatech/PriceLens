import 'package:flutter/material.dart';

import '../currency/currency_preferences.dart';
import '../currency/exchange_rates.dart';
import '../currency/money.dart';
import 'price_parser.dart';
import 'price_tracker.dart';

class PriceResultCard extends StatelessWidget {
  const PriceResultCard({
    super.key,
    required this.candidate,
    required this.status,
    required this.rates,
    this.preferences = const CurrencyPreferences(),
    this.rateNote,
    this.isLost = false,
    this.message,
    required this.onEdit,
  });

  final PriceCandidate? candidate;
  final ScanStatus status;
  final RateQuote? rates;
  final CurrencyPreferences preferences;
  final String? rateNote;
  final bool isLost;
  final String? message;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final price = candidate;
    final quote = rates;
    final accepted =
        !isLost && (status == ScanStatus.stable || status == ScanStatus.fixed);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF20272B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: price == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message ?? 'Наведите камеру на цену',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                    'Один ценник в кадре. Пересчёт появится автоматически.',
                    style: TextStyle(color: Colors.white60)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLost
                      ? 'ИЩЕМ ЦЕНУ…'
                      : switch (status) {
                          ScanStatus.stable => 'СТАБИЛЬНО',
                          ScanStatus.fixed => 'ПОДТВЕРЖДЕНО ВАМИ',
                          ScanStatus.needsConfirmation => 'НУЖНА ПРОВЕРКА',
                          _ => 'ПРОВЕРЯЕМ ЦЕНУ',
                        },
                  style: TextStyle(
                      color: accepted ? accent : const Color(0xFFFFCF83),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 4),
                Text('${formatBani(price.amountBani)} RON${price.unit.suffix}',
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1)),
                if (price.currencyAssumed)
                  const Text('RON по умолчанию',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                if (accepted && quote != null) ...[
                  Row(children: [
                    for (final currency in preferences.currencies) ...[
                      if (currency != preferences.primary)
                        const SizedBox(width: 12),
                      Expanded(
                          child: _CurrencyValue(
                        currency: currency.name.toUpperCase(),
                        value: convertBani(
                            price.amountBani,
                            currency == TargetCurrency.eur
                                ? quote.eurPerRon
                                : quote.uahPerRon,
                            decimals: preferences.decimals),
                        suffix: price.unit.suffix,
                        primary: currency == preferences.primary,
                      )),
                    ],
                  ]),
                  if (rateNote case final note?) ...[
                    const SizedBox(height: 6),
                    Text(note,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                  ],
                ] else
                  Text(
                    !accepted
                        ? (isLost
                            ? 'Проверяем, осталась ли цена в кадре'
                            : message ??
                                'Дождитесь проверки или подтвердите цену')
                        : '${preferences.currencies.map((currency) => '${currency.name.toUpperCase()} —').join(' · ')}\nДля пересчёта нужен загруженный курс',
                    style: const TextStyle(color: Colors.white60),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(status == ScanStatus.needsConfirmation
                        ? 'Проверить цену'
                        : 'Исправить'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CurrencyValue extends StatelessWidget {
  const _CurrencyValue(
      {required this.currency,
      required this.value,
      required this.suffix,
      required this.primary});
  final String currency;
  final String value;
  final String suffix;
  final bool primary;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(currency,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text('≈ $value$suffix',
              style: TextStyle(
                  fontSize: primary ? 25 : 22, fontWeight: FontWeight.w500)),
        ],
      );
}
