import 'package:pricelens/currency/currency_preferences.dart';
import 'package:pricelens/history/scan_entry.dart';
import 'package:pricelens/storage/scan_store.dart';

class MemoryScanStore implements ScanStore {
  final entries = <int, ScanEntry>{};
  CurrencyPreferences preferences = const CurrencyPreferences();
  int _next = 0;

  @override
  Future<List<ScanEntry>> history() async =>
      entries.values.toList().reversed.toList();

  @override
  Future<int> insert(ScanEntry entry) async {
    final id = ++_next;
    entries[id] = ScanEntry.fromStorage(id, entry.toStorage());
    return id;
  }

  @override
  Future<void> update(int id, ScanEntry entry) async {
    if (entries.containsKey(id)) {
      entries[id] = ScanEntry.fromStorage(id, entry.toStorage());
    }
  }

  @override
  Future<void> clearHistory() async => entries.clear();

  @override
  Future<CurrencyPreferences> loadPreferences() async => preferences;

  @override
  Future<void> savePreferences(CurrencyPreferences value) async =>
      preferences = value;
}
