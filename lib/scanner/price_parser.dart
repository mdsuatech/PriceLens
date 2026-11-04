import 'dart:ui';

enum PriceUnit {
  item(''),
  kg(' / кг'),
  litre(' / л');

  const PriceUnit(this.suffix);
  final String suffix;
}

enum PriceKind { regular, old, conditional, unit }

class OcrLine {
  const OcrLine(this.text, this.bounds);
  final String text;
  final Rect bounds;
}

class PriceCandidate {
  const PriceCandidate({
    required this.amountBani,
    required this.bounds,
    this.unit = PriceUnit.item,
    this.kind = PriceKind.regular,
    this.currencyAssumed = false,
    this.caution,
  });

  final int amountBani;
  final Rect bounds;
  final PriceUnit unit;
  final PriceKind kind;
  final bool currencyAssumed;
  final String? caution;
}

class PriceAnalysis {
  const PriceAnalysis({
    this.candidates = const [],
    this.selected,
    this.needsConfirmation = false,
    this.foreignCurrency = false,
    this.message,
  });

  final List<PriceCandidate> candidates;
  final PriceCandidate? selected;
  final bool needsConfirmation;
  final bool foreignCurrency;
  final String? message;
}

class PriceParser {
  const PriceParser();

  static final _numbers =
      RegExp(r'(?<![\w.,])\d+(?:[.,]\d+|[ \u00a0]\d{3})*(?![\d.,])');
  static final _ron =
      RegExp(r'(?<![A-Za-z])(?:ron|lei)(?![A-Za-z])', caseSensitive: false);
  static final _foreign = RegExp(
      r'(?<![A-Za-z])(?:eur|uah|usd|gbp|pln|huf|mdl)(?![A-Za-z])|[€\$₴£]',
      caseSensitive: false);
  static final _old =
      RegExp(r'\b(?:vechi|veche|old|was)\b|старая|стара', caseSensitive: false);
  static final _conditional = RegExp(
      r'\b(?:card|loialitate|fidelitate|cumperi|bucati|bucăți)\b|по карте|при покупке',
      caseSensitive: false);

  PriceAnalysis analyze(List<OcrLine> lines) {
    final candidates = <PriceCandidate>[];
    final foreignCurrency = lines.any((line) => _foreign.hasMatch(line.text));
    var detachedCondition = false;
    for (final line in lines) {
      final text = line.text;
      if (_foreign.hasMatch(text)) {
        continue;
      }
      final hasRon = _ron.hasMatch(text);
      // A currency marker may be returned as a separate OCR line/block.
      if (foreignCurrency && !hasRon) continue;
      final isOld = _old.hasMatch(text);
      final isConditional = _conditional.hasMatch(text);
      var parsedOnLine = 0;
      for (final match in _numbers.allMatches(text)) {
        final before = text.substring(0, match.start).trimRight();
        final after = text.substring(match.end);
        if (before.endsWith('-') ||
            before.endsWith('−') ||
            RegExp(r'^\s*%').hasMatch(after) ||
            RegExp(r'^\s*(?:kg|g|mg|l|ml|buc)\b', caseSensitive: false)
                .hasMatch(after) ||
            RegExp(r'/\s*$').hasMatch(before)) {
          continue;
        }
        final raw = match.group(0)!;
        final parsed = _parseOcrNumber(raw);
        if (parsed == null) continue;
        // Bare long integers are often barcodes, dates or product IDs.
        if (!raw.contains(RegExp(r'[.,]')) && !hasRon && raw.length > 6) {
          continue;
        }

        var unit = PriceUnit.item;
        final unitMatch =
            RegExp(r'^\s*(?:(?:ron|lei)\s*)?/\s*(kg|l)\b', caseSensitive: false)
                .firstMatch(after);
        if (unitMatch != null) {
          unit = unitMatch.group(1)!.toLowerCase() == 'kg'
              ? PriceUnit.kg
              : PriceUnit.litre;
        }
        var caution = parsed.ambiguous ? 'Проверьте разделитель в цене' : null;
        if (parsed.bani == 0) caution = 'Подтвердите нулевую цену';
        if (!hasRon && !raw.contains(RegExp(r'[.,]'))) {
          caution = 'Подтвердите, что это цена в RON';
        }
        if (isConditional) caution = 'У этой цены есть условия акции';
        if (unit != PriceUnit.item) caution = 'Это цена за единицу измерения';
        candidates.add(PriceCandidate(
          amountBani: parsed.bani,
          bounds: line.bounds,
          unit: unit,
          kind: isOld
              ? PriceKind.old
              : isConditional
                  ? PriceKind.conditional
                  : unit != PriceUnit.item
                      ? PriceKind.unit
                      : PriceKind.regular,
          currencyAssumed: !hasRon,
          caution: caution,
        ));
        parsedOnLine++;
      }
      if ((isOld || isConditional) && parsedOnLine == 0) {
        detachedCondition = true;
      }
    }

    final usable = candidates
        .where((candidate) => candidate.kind != PriceKind.old)
        .toList();
    if (usable.isEmpty) {
      return PriceAnalysis(
        foreignCurrency: foreignCurrency,
        message: foreignCurrency ? 'Поддерживается цена в RON' : null,
      );
    }
    final ordinary = usable
        .where((candidate) => candidate.kind == PriceKind.regular)
        .toList();
    final selected = ordinary.isNotEmpty ? ordinary.first : usable.first;
    final multiple =
        ordinary.length > 1 || (ordinary.isEmpty && usable.length > 1);
    final needsConfirmation =
        multiple || detachedCondition || selected.caution != null;
    return PriceAnalysis(
      candidates: List.unmodifiable(usable),
      selected: selected,
      needsConfirmation: needsConfirmation,
      foreignCurrency: foreignCurrency,
      message: multiple
          ? 'В кадре несколько цен — выберите нужную'
          : detachedCondition
              ? 'Проверьте условия и основную цену'
              : selected.caution,
    );
  }
}

({int bani, bool ambiguous})? _parseOcrNumber(String raw) {
  final value = raw.replaceAll('\u00a0', ' ');
  // Romanian thousands grouping, with an explicit decimal comma.
  if (RegExp(r'^\d{1,3}(?:[. ]\d{3})+,\d{1,2}$').hasMatch(value)) {
    final parts = value.split(',');
    final bani = int.tryParse(
        '${parts[0].replaceAll(RegExp(r'[. ]'), '')}${parts[1].padRight(2, '0')}');
    return bani == null ? null : (bani: bani, ambiguous: false);
  }
  if (RegExp(r'^\d+[.,]\d{1,2}$').hasMatch(value)) {
    final parts = value.split(RegExp(r'[.,]'));
    final bani = int.tryParse('${parts[0]}${parts[1].padRight(2, '0')}');
    return bani == null ? null : (bani: bani, ambiguous: false);
  }
  if (RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(value)) {
    final bani = int.tryParse('${value.replaceAll('.', '')}00');
    return bani == null ? null : (bani: bani, ambiguous: true);
  }
  if (RegExp(r'^\d+$').hasMatch(value)) {
    final bani = int.tryParse('${value}00');
    return bani == null ? null : (bani: bani, ambiguous: false);
  }
  return null;
}

int? parseManualPrice(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split(RegExp(r'[.,]'));
  return int.tryParse(
      '${parts[0]}${parts.length == 1 ? '00' : parts[1].padRight(2, '0')}');
}
