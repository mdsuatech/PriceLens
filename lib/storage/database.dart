import 'package:sqflite/sqflite.dart';

const priceLensDatabasePath = 'pricelens.db';

Future<Database> openPriceLensDatabase(String path) => openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
      CREATE TABLE rate_state (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        snapshot TEXT,
        last_automatic_attempt INTEGER
      )
    ''');
        await db.insert('rate_state', {'id': 1});
        await _createLocalTables(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createLocalTables(db);
      },
    );

Future<void> _createLocalTables(Database db) async {
  await db.execute('''
    CREATE TABLE scan_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE currency_preferences (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      show_eur INTEGER NOT NULL CHECK(show_eur IN (0, 1)),
      show_uah INTEGER NOT NULL CHECK(show_uah IN (0, 1)),
      primary_currency TEXT NOT NULL,
      decimals INTEGER NOT NULL CHECK(decimals IN (0, 2)),
      CHECK((primary_currency = 'eur' AND show_eur = 1) OR
            (primary_currency = 'uah' AND show_uah = 1))
    )
  ''');
}
