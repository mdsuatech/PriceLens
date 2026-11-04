import 'package:sqflite/sqflite.dart';

import '../currency/currency_preferences.dart';
import '../history/scan_entry.dart';
import 'database.dart';

abstract interface class ScanStore {
  Future<List<ScanEntry>> history();
  Future<int> insert(ScanEntry entry);
  Future<void> update(int id, ScanEntry entry);
  Future<void> clearHistory();
  Future<CurrencyPreferences> loadPreferences();
  Future<void> savePreferences(CurrencyPreferences preferences);
}

class SqliteScanStore implements ScanStore {
  const SqliteScanStore({this.path = priceLensDatabasePath});
  final String path;

  @override
  Future<List<ScanEntry>> history() async {
    final db = await openPriceLensDatabase(path);
    final rows = await db.query('scan_history', orderBy: 'id DESC');
    return [
      for (final row in rows)
        ScanEntry.fromStorage(row['id'] as int, row['entry'] as String)
    ];
  }

  @override
  Future<int> insert(ScanEntry entry) async {
    final db = await openPriceLensDatabase(path);
    return db.transaction((transaction) async {
      final id = await transaction
          .insert('scan_history', {'entry': entry.toStorage()});
      await transaction.rawDelete('''
        DELETE FROM scan_history WHERE id IN (
          SELECT id FROM scan_history ORDER BY id DESC LIMIT -1 OFFSET 100
        )
      ''');
      return id;
    });
  }

  @override
  Future<void> update(int id, ScanEntry entry) async {
    final db = await openPriceLensDatabase(path);
    await db.update('scan_history', {'entry': entry.toStorage()},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearHistory() async {
    final db = await openPriceLensDatabase(path);
    await db.delete('scan_history');
  }

  @override
  Future<CurrencyPreferences> loadPreferences() async {
    final db = await openPriceLensDatabase(path);
    final rows = await db.query('currency_preferences', where: 'id = 1');
    if (rows.isEmpty) return const CurrencyPreferences();
    final row = rows.single;
    return CurrencyPreferences(
        showEur: row['show_eur'] == 1,
        showUah: row['show_uah'] == 1,
        primary:
            TargetCurrency.values.byName(row['primary_currency'] as String),
        decimals: row['decimals'] as int);
  }

  @override
  Future<void> savePreferences(CurrencyPreferences preferences) async {
    final db = await openPriceLensDatabase(path);
    await db.insert(
        'currency_preferences',
        {
          'id': 1,
          'show_eur': preferences.showEur ? 1 : 0,
          'show_uah': preferences.showUah ? 1 : 0,
          'primary_currency': preferences.primary.name,
          'decimals': preferences.decimals,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
