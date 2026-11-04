import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef RateQuote = ({String eurPerRon, String uahPerRon});

const demoQuote = (eurPerRon: '0.2', uahPerRon: '10');

class RateSnapshot {
  const RateSnapshot._(
      this.quote, this.dataAsOf, this.fetchedAt, this.nextUpdateAt);

  final RateQuote quote;
  final DateTime dataAsOf;
  final DateTime fetchedAt;
  final DateTime? nextUpdateAt;

  factory RateSnapshot.fromApi(String body, DateTime fetchedAt) {
    final json = jsonDecode(body);
    if (json is! Map ||
        json['result'] != 'success' ||
        json['base_code'] != 'RON') {
      throw const FormatException('Expected a successful RON response');
    }
    final rates = json['rates'];
    if (rates is! Map || rates['RON'] != 1) {
      throw const FormatException('Invalid RON base rate');
    }
    final eur = rates['EUR'];
    final uah = rates['UAH'];
    if (eur is! num || uah is! num) {
      throw const FormatException('Both numeric target rates are required');
    }
    return RateSnapshot._validated(
      eur.toString(),
      uah.toString(),
      _utcSeconds(json['time_last_update_unix']),
      fetchedAt.toUtc(),
      json['time_next_update_unix'] == null
          ? null
          : _utcSeconds(json['time_next_update_unix']),
    );
  }

  factory RateSnapshot.fromCache(String body) {
    final json = jsonDecode(body);
    if (json is! Map || json['source'] != ExchangeRateApi.source) {
      throw const FormatException('Unknown cached rate source');
    }
    final next = json['nextUpdateAt'];
    return RateSnapshot._validated(
      json['eurPerRon'],
      json['uahPerRon'],
      _utcSeconds(json['dataAsOf']),
      _utcSeconds(json['fetchedAt']),
      next == null ? null : _utcSeconds(next),
    );
  }

  factory RateSnapshot._validated(Object? eur, Object? uah, DateTime dataAsOf,
      DateTime fetchedAt, DateTime? next) {
    if (dataAsOf.isAfter(fetchedAt.add(const Duration(minutes: 5)))) {
      throw const FormatException('Rate data is dated in the future');
    }
    // A bad schedule must not prevent future automatic updates.
    if (next != null &&
        (!next.isAfter(dataAsOf) ||
            next.isAfter(dataAsOf.add(const Duration(days: 2))))) {
      next = null;
    }
    return RateSnapshot._(
      (eurPerRon: _positiveDecimal(eur), uahPerRon: _positiveDecimal(uah)),
      dataAsOf,
      fetchedAt,
      next,
    );
  }

  String toCache() => jsonEncode({
        'source': ExchangeRateApi.source,
        'eurPerRon': quote.eurPerRon,
        'uahPerRon': quote.uahPerRon,
        'dataAsOf': dataAsOf.millisecondsSinceEpoch ~/ 1000,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch ~/ 1000,
        if (nextUpdateAt case final next?)
          'nextUpdateAt': next.millisecondsSinceEpoch ~/ 1000,
      });

  bool isStaleAt(DateTime now) =>
      now.difference(dataAsOf) > const Duration(hours: 24);
}

class RatesRequestException implements Exception {
  const RatesRequestException(this.message);
  final String message;
}

class ExchangeRateApi {
  static const source = 'ExchangeRate-API';
  static final sourceUrl = Uri.https('www.exchangerate-api.com');
  static final _endpoint = Uri.https('open.er-api.com', '/v6/latest/RON');

  static Future<RateSnapshot> fetch() async {
    final client = HttpClient();
    try {
      return await _fetch(client).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const RatesRequestException('Источник курса не ответил вовремя');
    } on SocketException {
      throw const RatesRequestException(
          'Не удалось подключиться к источнику курса');
    } on IOException {
      throw const RatesRequestException('Не удалось получить курс');
    } on FormatException {
      throw const RatesRequestException('Источник вернул некорректный курс');
    } finally {
      client.close(force: true);
    }
  }

  static Future<RateSnapshot> _fetch(HttpClient client) async {
    final request = await client.getUrl(_endpoint);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode == HttpStatus.tooManyRequests) {
      throw const RatesRequestException(
          'Слишком много запросов. Попробуйте позже');
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const RatesRequestException('Источник курса временно недоступен');
    }
    final body = await utf8.decoder.bind(response).join();
    return RateSnapshot.fromApi(body, DateTime.now());
  }
}

DateTime _utcSeconds(Object? value) {
  if (value is! int || value <= 0 || value > 8640000000000) {
    throw const FormatException('Invalid rate timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

String _positiveDecimal(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value) ||
      !value.contains(RegExp(r'[1-9]'))) {
    throw const FormatException('Invalid target rate');
  }
  return value;
}
