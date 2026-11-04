import 'dart:convert';

import 'package:pricelens/currency/exchange_rates.dart';
import 'package:pricelens/currency/rates_cache.dart';

Map<String, Object?> ratePayload(
  DateTime dataAsOf, {
  Object? eur = 0.2,
  Object? uah = 10,
  DateTime? nextUpdateAt,
}) =>
    {
      'result': 'success',
      'base_code': 'RON',
      'time_last_update_unix': dataAsOf.millisecondsSinceEpoch ~/ 1000,
      if (nextUpdateAt != null)
        'time_next_update_unix': nextUpdateAt.millisecondsSinceEpoch ~/ 1000,
      'rates': {'RON': 1, 'EUR': eur, 'UAH': uah},
    };

RateSnapshot rateFixture(DateTime now,
        {DateTime? dataAsOf,
        num eur = 0.2,
        num uah = 10,
        DateTime? nextUpdateAt}) =>
    RateSnapshot.fromApi(
        jsonEncode(ratePayload(dataAsOf ?? now,
            eur: eur, uah: uah, nextUpdateAt: nextUpdateAt)),
        now);

class MemoryRatesCache implements RatesCache {
  RateSnapshot? saved;
  DateTime? lastAttempt;
  int writes = 0;

  @override
  Future<CachedRates> load() async =>
      (snapshot: saved, lastAutomaticAttempt: lastAttempt);

  @override
  Future<void> save(RateSnapshot snapshot) async {
    saved = snapshot;
    writes++;
  }

  @override
  Future<void> recordAutomaticAttempt(DateTime at) async => lastAttempt = at;
}
