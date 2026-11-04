import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'exchange_rates.dart';
import 'rates_cache.dart';

class RatesController extends ChangeNotifier {
  RatesController({
    RatesCache cache = const SqliteRatesCache(),
    Future<RateSnapshot> Function() fetch = ExchangeRateApi.fetch,
    DateTime Function() clock = DateTime.now,
  })  : _cache = cache,
        _fetch = fetch,
        _clock = clock;

  final RatesCache _cache;
  final Future<RateSnapshot> Function() _fetch;
  final DateTime Function() _clock;
  Future<void>? _initialization;
  Future<void>? _pending;
  DateTime? _lastAutomaticAttempt;
  bool _disposed = false;
  bool _snapshotSaved = false;

  RateSnapshot? snapshot;
  bool usingCache = false;
  String? error;
  String? storageWarning;

  bool get isRefreshing => _pending != null;
  bool get isStale => snapshot?.isStaleAt(_clock()) ?? false;

  Future<void> refresh({bool manual = false}) async {
    if (_disposed) return;
    await (_initialization ??= _load());
    if (_disposed) return;
    if (_pending case final active?) return active;
    final now = _clock();
    if (!manual && !_shouldRefresh(now)) {
      _emit();
      return;
    }

    error = null;
    final pending = _fetchAndSave(now, manual);
    _pending = pending;
    _emit();
    try {
      await pending;
    } finally {
      _pending = null;
      _emit();
    }
  }

  bool _shouldRefresh(DateTime now) {
    if (_withinHour(_lastAutomaticAttempt, now)) return false;
    final current = snapshot;
    if (current == null) return true;
    if (_withinHour(current.fetchedAt, now)) return false;
    final next = current.nextUpdateAt;
    return next == null ||
        now.isBefore(current.fetchedAt) ||
        !now.isBefore(next);
  }

  Future<void> _load() async {
    try {
      final cached = await _cache.load();
      snapshot = cached.snapshot;
      _snapshotSaved = snapshot != null;
      usingCache = _snapshotSaved;
      _lastAutomaticAttempt = cached.lastAutomaticAttempt;
    } on DatabaseException {
      storageWarning = 'Не удалось прочитать сохранённый курс';
    } on FormatException {
      storageWarning = 'Сохранённый курс повреждён';
    }
    _emit();
  }

  Future<void> _fetchAndSave(DateTime now, bool manual) async {
    if (!manual) {
      _lastAutomaticAttempt = now;
      try {
        await _cache.recordAutomaticAttempt(now);
      } on DatabaseException {
        storageWarning = 'Не удалось записать время проверки курса';
      }
    }
    if (_disposed) return;
    try {
      final next = await _fetch();
      if (_disposed) return;
      final previous = snapshot;
      if (previous != null && next.dataAsOf.isBefore(previous.dataAsOf)) {
        throw const RatesRequestException('Источник вернул более ранний курс');
      }
      try {
        await _cache.save(next);
        _snapshotSaved = true;
        storageWarning = null;
      } on DatabaseException {
        _snapshotSaved = false;
        storageWarning =
            'Курс получен, но его не удалось сохранить для работы без интернета';
      }
      snapshot = next;
      usingCache = false;
    } on RatesRequestException catch (failure) {
      error = failure.message;
      usingCache = _snapshotSaved;
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

bool _withinHour(DateTime? time, DateTime now) =>
    time != null &&
    !now.isBefore(time) &&
    now.difference(time) < const Duration(hours: 1);
