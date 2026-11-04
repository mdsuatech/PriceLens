import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pricelens/currency/exchange_rates.dart';
import 'package:pricelens/currency/money.dart';
import 'package:pricelens/currency/rates_controller.dart';

import 'support/rates_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 11, 3, 12);

  test(
      'RON quotes are used in the supplied direction without rounding the rate',
      () {
    final snapshot = rateFixture(now, eur: 0.187654, uah: 9.432156);
    expect(snapshot.quote.eurPerRon, '0.187654');
    expect(convertBani(2499, snapshot.quote.eurPerRon), '4,69');
    expect(convertBani(2499, snapshot.quote.uahPerRon), '235,71');
  });

  test(
      'Cache round-trip preserves both quotes and publication time separately from fetch time',
      () {
    final dataAt = now.subtract(const Duration(hours: 3));
    final next = now.add(const Duration(hours: 21));
    final restored = RateSnapshot.fromCache(
        rateFixture(now, dataAsOf: dataAt, nextUpdateAt: next).toCache());
    expect(restored.quote, demoQuote);
    expect(restored.dataAsOf, dataAt);
    expect(restored.fetchedAt, now);
    expect(restored.nextUpdateAt, next);
  });

  test(
      'Rejects incomplete, invalid and future quotes before they can replace the cache',
      () {
    for (final payload in [
      ratePayload(now, uah: null),
      ratePayload(now, eur: '0.2'),
      ratePayload(now, eur: 0),
      ratePayload(now, eur: -1),
      ratePayload(now)..['base_code'] = 'EUR',
      ratePayload(now)..['result'] = 'error',
      ratePayload(now)..remove('time_last_update_unix'),
      ratePayload(now.add(const Duration(hours: 1))),
    ]) {
      expect(() => RateSnapshot.fromApi(jsonEncode(payload), now),
          throwsFormatException);
    }
  });

  test('Staleness follows publication time even immediately after a fetch', () {
    final snapshot =
        rateFixture(now, dataAsOf: now.subtract(const Duration(days: 2)));
    expect(snapshot.isStaleAt(now), isTrue);
    expect(snapshot.fetchedAt, now);
  });

  test('An implausible next publication does not block automatic updates', () {
    expect(
        rateFixture(now, nextUpdateAt: now.add(const Duration(days: 7)))
            .nextUpdateAt,
        isNull);
  });

  test(
      'Shows persisted rates while a request is pending and keeps them when it fails',
      () async {
    final cached = rateFixture(now.subtract(const Duration(days: 2)));
    final store = MemoryRatesCache()..saved = cached;
    final request = Completer<RateSnapshot>();
    final started = Completer<void>();
    final controller = RatesController(
        cache: store,
        clock: () => now,
        fetch: () {
          started.complete();
          return request.future;
        });
    addTearDown(controller.dispose);
    final refresh = controller.refresh();
    await started.future;
    expect(controller.snapshot, same(cached));
    expect(controller.usingCache, isTrue);
    expect(controller.isStale, isTrue);
    request.completeError(const RatesRequestException('Нет соединения'));
    await refresh;
    expect(controller.snapshot, same(cached));
    expect(controller.error, 'Нет соединения');
    expect(store.writes, 0);
  });

  test(
      'An empty offline start remains empty and throttles automatic retry across restart',
      () async {
    final store = MemoryRatesCache();
    var currentTime = now;
    var requests = 0;
    RatesController makeController() => RatesController(
        cache: store,
        clock: () => currentTime,
        fetch: () async {
          requests++;
          throw const RatesRequestException('Нет соединения');
        });
    final first = makeController();
    await first.refresh();
    expect(first.snapshot, isNull);
    expect(first.error, isNotNull);
    first.dispose();
    final restarted = makeController();
    addTearDown(restarted.dispose);
    currentTime = now.add(const Duration(minutes: 59));
    await restarted.refresh();
    expect(requests, 1);
    currentTime = now.add(const Duration(hours: 1));
    await restarted.refresh();
    expect(requests, 2);
    expect(restarted.snapshot, isNull);
  });

  test(
      'Automatic refresh waits for publication and manual refresh joins an in-flight request',
      () async {
    final previous = rateFixture(now.subtract(const Duration(hours: 2)),
        nextUpdateAt: now.add(const Duration(hours: 1)));
    final store = MemoryRatesCache()..saved = previous;
    final request = Completer<RateSnapshot>();
    final started = Completer<void>();
    var requests = 0;
    final controller = RatesController(
        cache: store,
        clock: () => now,
        fetch: () {
          requests++;
          started.complete();
          return request.future;
        });
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(requests, 0);
    final manual = controller.refresh(manual: true);
    await started.future;
    final second = controller.refresh(manual: true);
    expect(controller.isRefreshing, isTrue);
    final next = rateFixture(now, eur: 0.19, uah: 9);
    request.complete(next);
    await Future.wait([manual, second]);
    expect(requests, 1);
    expect(store.writes, 1);
    expect(controller.snapshot, same(next));
    expect(controller.usingCache, isFalse);
  });

  test('A response with an older publication cannot roll back a valid snapshot',
      () async {
    final cached = rateFixture(now);
    final store = MemoryRatesCache()..saved = cached;
    final controller = RatesController(
        cache: store,
        clock: () => now,
        fetch: () async =>
            rateFixture(now, dataAsOf: now.subtract(const Duration(days: 1))));
    addTearDown(controller.dispose);
    await controller.refresh(manual: true);
    expect(controller.snapshot, same(cached));
    expect(store.writes, 0);
    expect(controller.error, isNotNull);
  });
}
