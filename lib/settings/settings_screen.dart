import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../currency/currency_preferences.dart';
import '../currency/rates_banner.dart';
import '../currency/rates_controller.dart';
import '../history/history_screen.dart';
import '../storage/scan_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
      {super.key,
      required this.store,
      required this.initial,
      required this.onChanged,
      required this.rates});

  final ScanStore store;
  final CurrencyPreferences initial;
  final ValueChanged<CurrencyPreferences> onChanged;
  final RatesController? rates;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late CurrencyPreferences _preferences = widget.initial;
  bool _busy = false;

  Future<void> _save(CurrencyPreferences next) async {
    setState(() => _busy = true);
    try {
      await widget.store.savePreferences(next);
      widget.onChanged(next);
      _preferences = next;
    } on DatabaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось сохранить настройки')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    final cleared = await confirmClearHistory(context, widget.store);
    if (!mounted) return;
    setState(() => _busy = false);
    if (cleared) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('История очищена')));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Настройки')),
          body: SafeArea(
              child: ListView(children: [
            const ListTile(
                title: Text('Исходная валюта · RON'),
                subtitle: Text('Цена без обозначения считается ценой в RON')),
            for (final currency in TargetCurrency.values)
              SwitchListTile(
                title: Text('Показывать ${currency.name.toUpperCase()}'),
                value: _preferences.shows(currency),
                onChanged: _busy ||
                        (_preferences.shows(currency) &&
                            _preferences.currencies.length == 1)
                    ? null
                    : (visible) =>
                        _save(_preferences.withVisibility(currency, visible)),
              ),
            ListTile(
                title: const Text('Показывать первой'),
                trailing: DropdownButton<TargetCurrency>(
                  value: _preferences.primary,
                  items: [
                    for (final currency in _preferences.currencies)
                      DropdownMenuItem(
                          value: currency,
                          child: Text(currency.name.toUpperCase()))
                  ],
                  onChanged: _busy || _preferences.currencies.length == 1
                      ? null
                      : (currency) {
                          if (currency != null) {
                            _save(_preferences.withPrimary(currency));
                          }
                        },
                )),
            ListTile(
                title: const Text('Знаков после запятой'),
                trailing: DropdownButton<int>(
                  value: _preferences.decimals,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0')),
                    DropdownMenuItem(value: 2, child: Text('2'))
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            _save(_preferences.withDecimals(value));
                          }
                        },
                )),
            const Divider(),
            Padding(
                padding: const EdgeInsets.all(16),
                child: widget.rates == null
                    ? const RatesBanner(controller: null)
                    : AnimatedBuilder(
                        animation: widget.rates!,
                        builder: (context, _) =>
                            RatesBanner(controller: widget.rates))),
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Очистить историю'),
                onTap: _busy ? null : _clear),
          ])),
        ),
      );
}
