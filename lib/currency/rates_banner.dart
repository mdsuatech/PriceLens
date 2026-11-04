import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'exchange_rates.dart';
import 'rates_controller.dart';

class RatesBanner extends StatelessWidget {
  const RatesBanner({super.key, required this.controller});

  // The debug fixture has no network or storage controller.
  final RatesController? controller;

  @override
  Widget build(BuildContext context) {
    final rates = controller;
    final snapshot = rates?.snapshot;
    final stale = rates?.isStale ?? false;
    final String label;
    if (rates == null) {
      label = 'ТЕСТОВЫЕ КУРСЫ · не для покупок';
    } else if (snapshot == null) {
      label = rates.isRefreshing ? 'Загружаем курс…' : 'Курс не загружен';
    } else {
      final prefix = rates.usingCache ? 'Сохранённый курс' : 'Курс';
      label =
          '$prefix от ${formatRateDate(snapshot.dataAsOf)}${stale ? ' · устарел' : ''}';
    }

    return Material(
      color: rates == null || stale
          ? const Color(0xFF3A3020)
          : const Color(0xFF20272B),
      borderRadius: BorderRadius.circular(12),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openDetails(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: 16,
                  color: rates == null || stale
                      ? const Color(0xFFFFCF83)
                      : Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 12))),
              const Icon(Icons.chevron_right, size: 16),
            ]),
          ),
        ),
        if (snapshot != null) const RatesSourceLink(),
      ]),
    );
  }

  void _openDetails(BuildContext context) {
    final rates = controller;
    showDialog<void>(
        context: context,
        builder: (context) {
          if (rates == null) {
            return AlertDialog(
              title: const Text('Тестовые курсы'),
              content: const Text(
                  'Условные значения для проверки сканера\n\n1 RON = 0,20 EUR\n1 RON = 10,00 UAH'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть'))
              ],
            );
          }
          return AnimatedBuilder(
              animation: rates,
              builder: (context, _) {
                final snapshot = rates.snapshot;
                return AlertDialog(
                  title: const Text('Курсы валют'),
                  scrollable: true,
                  content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snapshot != null) ...[
                          Text(
                              '1 RON = ${snapshot.quote.eurPerRon.replaceAll('.', ',')} EUR'),
                          Text(
                              '1 RON = ${snapshot.quote.uahPerRon.replaceAll('.', ',')} UAH'),
                          const SizedBox(height: 12),
                          Text(
                              'Курс от ${formatRateDate(snapshot.dataAsOf, withTime: true)}'),
                          Text(
                              'Получен ${formatRateDate(snapshot.fetchedAt, withTime: true)}'),
                          if (rates.usingCache)
                            const Text('Используется сохранённый курс'),
                          if (rates.isStale) const Text('Курс устарел'),
                          const SizedBox(height: 12),
                          const Text(
                              'Справочный пересчёт. Сумма списания зависит от банка.'),
                        ] else
                          const Text(
                              'Курс пока недоступен. Можно распознать или ввести цену в RON.'),
                        if (rates.error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(error)
                        ],
                        if (rates.storageWarning case final warning?) ...[
                          const SizedBox(height: 12),
                          Text(warning)
                        ],
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Закрыть')),
                    FilledButton(
                      onPressed: rates.isRefreshing
                          ? null
                          : () => rates.refresh(manual: true),
                      child:
                          Text(rates.isRefreshing ? 'Обновляем…' : 'Обновить'),
                    ),
                  ],
                );
              });
        });
  }
}

class RatesSourceLink extends StatelessWidget {
  const RatesSourceLink({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => _openSource(context),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.open_in_new, size: 13),
        label: const Text('Rates By Exchange Rate API',
            style: TextStyle(fontSize: 11)),
      );

  Future<void> _openSource(BuildContext context) async {
    try {
      if (await launchUrl(ExchangeRateApi.sourceUrl,
          mode: LaunchMode.externalApplication)) return;
    } on PlatformException {
      // The device may not have an app that can open the source link.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть сайт источника')));
    }
  }
}

String formatRateDate(DateTime time, {bool withTime = false}) {
  final local = time.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  final date = '${pad(local.day)}.${pad(local.month)}.${local.year}';
  return withTime ? '$date ${pad(local.hour)}:${pad(local.minute)}' : date;
}
