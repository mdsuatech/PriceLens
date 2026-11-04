import 'package:flutter/material.dart';

import '../currency/money.dart';
import 'price_parser.dart';

class PriceEntrySheet extends StatefulWidget {
  const PriceEntrySheet({super.key, this.initial, this.candidates = const []});
  final PriceCandidate? initial;
  final List<PriceCandidate> candidates;

  @override
  State<PriceEntrySheet> createState() => _PriceEntrySheetState();
}

class _PriceEntrySheetState extends State<PriceEntrySheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _text;
  late PriceUnit _unit;
  PriceCandidate? _chosen;
  bool _confirmZero = false;

  @override
  void initState() {
    super.initState();
    _chosen = widget.initial;
    _unit = widget.initial?.unit ?? PriceUnit.item;
    _text = TextEditingController(
        text: widget.initial == null
            ? ''
            : formatBani(widget.initial!.amountBani));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final bani = parseManualPrice(_text.text)!;
    if (bani == 0 && !_confirmZero) return;
    Navigator.pop(
        context,
        PriceCandidate(
          amountBani: bani,
          bounds: _chosen?.bounds ?? Rect.zero,
          unit: _unit,
          kind: _chosen?.kind ?? PriceKind.regular,
          currencyAssumed: false,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final zero = parseManualPrice(_text.text) == 0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Expanded(
                  child: Text('Проверьте цену',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w600))),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Отменить',
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            const Text('Укажите текущую цену товара в румынских леях.',
                style: TextStyle(color: Colors.white60)),
            if (widget.candidates.length > 1) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final candidate in widget.candidates)
                    ChoiceChip(
                      selected: identical(candidate, _chosen),
                      label: Text(
                          '${formatBani(candidate.amountBani)} RON${candidate.unit.suffix}${candidate.kind == PriceKind.conditional ? ' · по акции' : ''}'),
                      onSelected: (_) => setState(() {
                        _chosen = candidate;
                        _unit = candidate.unit;
                        _text.text = formatBani(candidate.amountBani);
                        _confirmZero = false;
                      }),
                    ),
                ],
              ),
            ],
            if (_chosen?.caution != null) ...[
              const SizedBox(height: 12),
              Text(_chosen!.caution!,
                  style: const TextStyle(color: Color(0xFFFFCF83))),
            ],
            const SizedBox(height: 20),
            TextFormField(
              controller: _text,
              autofocus: widget.initial == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Цена', suffixText: 'RON', hintText: '24,99'),
              onChanged: (_) => setState(() => _confirmZero = false),
              validator: (value) => parseManualPrice(value ?? '') == null
                  ? 'Введите число с 0–2 знаками после запятой'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PriceUnit>(
              value: _unit,
              decoration:
                  const InputDecoration(labelText: 'За что указана цена'),
              items: const [
                DropdownMenuItem(
                    value: PriceUnit.item, child: Text('За товар')),
                DropdownMenuItem(
                    value: PriceUnit.kg, child: Text('За килограмм')),
                DropdownMenuItem(
                    value: PriceUnit.litre, child: Text('За литр')),
              ],
              onChanged: (value) => setState(() => _unit = value!),
            ),
            if (zero)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmZero,
                onChanged: (value) => setState(() => _confirmZero = value!),
                title: const Text('Подтверждаю, что цена равна нулю'),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: zero && !_confirmZero ? null : _submit,
                child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Подтвердить цену')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
