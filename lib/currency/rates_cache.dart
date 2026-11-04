import 'package:sqflite/sqflite.dart';

import '../storage/database.dart';
import 'exchange_rates.dart';

typedef CachedRates = ({
  RateSnapshot? snapshot,
  DateTime? lastAutomaticAttempt
});

abstract interface class RatesCache {
  Future<CachedRates> load();
  Future<void> save(RateSnapshot snapshot);
  Future<void> recordAutomaticAttempt(DateTime at);
}

class SqliteRatesCache implements RatesCache {
  const SqliteRatesCache({this.path = priceLensDatabasePath});

  final String path;

  Future<Database> _open() => openPriceLensDatabase(path);

  @override
  Future<CachedRates> load() async {
    final db = await _open();
    final row = (await db.query('rate_state', where: 'id = 1')).single;
    final encoded = row['snapshot'] as String?;
    final attempt = row['last_automatic_attempt'] as int?;
    return (
      snapshot: encoded == null ? null : RateSnapshot.fromCache(encoded),
      lastAutomaticAttempt: attempt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(attempt, isUtc: true),
    );
  }

  @override
  Future<void> save(RateSnapshot snapshot) async {
    final db = await _open();
    // One SQLite statement commits both target rates and their timestamps.
    await db.update('rate_state', {'snapshot': snapshot.toCache()},
        where: 'id = 1');
  }

  @override
  Future<void> recordAutomaticAttempt(DateTime at) async {
    final db = await _open();
    await db.update(
        'rate_state', {'last_automatic_attempt': at.millisecondsSinceEpoch},
        where: 'id = 1');
  }
}
