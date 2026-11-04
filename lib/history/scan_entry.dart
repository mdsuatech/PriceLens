import 'dart:convert';

import '../currency/currency_preferences.dart';
import '../currency/exchange_rates.dart';
import '../currency/money.dart';
import '../scanner/price_parser.dart';

enum ScanOrigin {
  automatic('Автоматически'),
  confirmed('Подтверждено'),
  corrected('Исправлено'),
  manual('Введено вручную');

  const ScanOrigin(this.label);
  final String label;
}

typedef UsedRates = ({RateSnapshot? snapshot, bool cached, bool demo});

class ScanEntry {
  ScanEntry.capture(PriceCandidate price, this.origin, this.scannedAt,
      this.updatedAt, this.rates)
      : id = null,
        amountBani = price.amountBani,
        unit = price.unit,
        kind = price.kind,
        currencyAssumed = price.currencyAssumed,
        eurAmount = _convert(price.amountBani, rates, TargetCurrency.eur),
        uahAmount = _convert(price.amountBani, rates, TargetCurrency.uah);

  ScanEntry.fromStorage(int id, String encoded)
      : this._decode(id, jsonDecode(encoded));

  ScanEntry._decode(this.id, Map<String, dynamic> json)
      : amountBani = json['bani'] as int,
        unit = PriceUnit.values.byName(json['unit'] as String),
        kind = PriceKind.values.byName(json['kind'] as String),
        currencyAssumed = json['currencyAssumed'] as bool,
        origin = ScanOrigin.values.byName(json['origin'] as String),
        scannedAt = DateTime.parse(json['scannedAt'] as String),
        updatedAt = DateTime.parse(json['updatedAt'] as String),
        eurAmount = json['eur'] as String?,
        uahAmount = json['uah'] as String?,
        rates = (
          snapshot: json['snapshot'] == null
              ? null
              : RateSnapshot.fromCache(json['snapshot'] as String),
          cached: json['cached'] as bool,
          demo: json['demo'] as bool,
        );

  final int? id;
  final int amountBani;
  final PriceUnit unit;
  final PriceKind kind;
  final bool currencyAssumed;
  final ScanOrigin origin;
  final DateTime scannedAt;
  final DateTime updatedAt;
  final UsedRates rates;
  final String? eurAmount;
  final String? uahAmount;

  String? amount(TargetCurrency currency) =>
      currency == TargetCurrency.eur ? eurAmount : uahAmount;

  String toStorage() => jsonEncode({
        'bani': amountBani,
        'unit': unit.name,
        'kind': kind.name,
        'currencyAssumed': currencyAssumed,
        'origin': origin.name,
        'scannedAt': scannedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'eur': eurAmount,
        'uah': uahAmount,
        'snapshot': rates.snapshot?.toCache(),
        'cached': rates.cached,
        'demo': rates.demo,
      });
}

String? _convert(int bani, UsedRates rates, TargetCurrency currency) {
  final quote = rates.demo ? demoQuote : rates.snapshot?.quote;
  if (quote == null) return null;
  return exactConversion(
      bani, currency == TargetCurrency.eur ? quote.eurPerRon : quote.uahPerRon);
}
