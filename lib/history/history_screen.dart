import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../currency/currency_preferences.dart';
import '../currency/exchange_rates.dart';
import '../currency/money.dart';
import '../currency/rates_banner.dart';
import '../scanner/price_parser.dart';
import '../storage/scan_store.dart';
import 'scan_entry.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen(
      {super.key, required this.store, required this.preferences});
  final ScanStore store;
  final CurrencyPreferences preferences;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<ScanEntry>> _entries = widget.store.history();
  bool _clearing = false;

  Future<void> _clear() async {
    setState(() => _clearing = true);
    final cleared = await confirmClearHistory(context, widget.store);
    if (!mounted) return;
    setState(() {
      _clearing = false;
      if (cleared) _entries = widget.store.history();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ScanEntry>>(
        future: _entries,
        builder: (context, result) {
          final entries = result.data;
          return Scaffold(
            appBar: AppBar(title: const Text('История'), actions: [
              IconButton(
                  tooltip: 'Очистить историю',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _clearing || entries == null || entries.isEmpty
                      ? null
                      : _clear),
            ]),
            body: SafeArea(child: _body(result)),
          );
        },
      );

  Widget _body(AsyncSnapshot<List<ScanEntry>> result) {
    if (result.hasError) {
      return Center(
          child: TextButton(
              onPressed: () =>
                  setState(() => _entries = widget.store.history()),
              child: const Text('Не удалось загрузить историю. Повторить')));
    }
    final entries = result.data;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Здесь появятся распознанные и введённые цены',
                  textAlign: TextAlign.center)));
    }
    return Column(children: [
      if (entries.any((entry) => entry.rates.snapshot != null))
        const RatesSourceLink(),
      Expanded(
          child: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ListTile(
            title:
                Text('${formatBani(entry.amountBani)} RON${entry.unit.suffix}'),
            subtitle: Text(
                '${_converted(entry)}${entry.rates.demo ? ' · Тестовый курс' : ''}\n${formatRateDate(entry.scannedAt, withTime: true)} · ${entry.origin.label}'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showEntry(entry),
          );
        },
      )),
    ]);
  }

  String _converted(ScanEntry entry) {
    if (entry.eurAmount == null) return 'Без курса';
    return widget.preferences.currencies
        .map((currency) =>
            '≈ ${formatExactAmount(entry.amount(currency)!, widget.preferences.decimals)} ${currency.name.toUpperCase()}${entry.unit.suffix}')
        .join(' · ');
  }

  void _showEntry(ScanEntry entry) {
    final snapshot = entry.rates.snapshot;
    final quote = entry.rates.demo ? demoQuote : snapshot?.quote;
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(
                  '${formatBani(entry.amountBani)} RON${entry.unit.suffix}'),
              content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_converted(entry)),
                    const SizedBox(height: 12),
                    Text(
                        '${formatRateDate(entry.scannedAt, withTime: true)} · ${entry.origin.label}'),
                    if (entry.updatedAt != entry.scannedAt)
                      Text(
                          'Изменено ${formatRateDate(entry.updatedAt, withTime: true)}'),
                    if (entry.currencyAssumed) const Text('RON по умолчанию'),
                    if (entry.kind == PriceKind.conditional)
                      const Text('Цена с условиями акции'),
                    if (quote != null) ...[
                      const SizedBox(height: 12),
                      Text(
                          '1 RON = ${quote.eurPerRon.replaceAll('.', ',')} EUR'),
                      Text(
                          '1 RON = ${quote.uahPerRon.replaceAll('.', ',')} UAH'),
                    ],
                    if (entry.rates.demo) const Text('Тестовые курсы'),
                    if (snapshot != null) ...[
                      Text(
                          'Курс от ${formatRateDate(snapshot.dataAsOf, withTime: true)}'),
                      Text(
                          'Получен ${formatRateDate(snapshot.fetchedAt, withTime: true)}'),
                      if (entry.rates.cached)
                        const Text('Использован сохранённый курс'),
                      if (snapshot.isStaleAt(entry.updatedAt))
                        const Text('Курс был устаревшим'),
                      const RatesSourceLink(),
                    ],
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть'))
              ],
            ));
  }
}

Future<bool> confirmClearHistory(BuildContext context, ScanStore store) async {
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
            title: const Text('Очистить историю?'),
            content:
                const Text('Все сохранённые цены будут удалены с устройства.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Очистить')),
            ],
          ));
  if (confirmed != true) return false;
  try {
    await store.clearHistory();
    return true;
  } on DatabaseException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось очистить историю')));
    }
    return false;
  }
}
