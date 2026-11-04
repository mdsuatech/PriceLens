export type Currency = "EUR" | "UAH";
export type Unit = "item" | "kg" | "litre";
export interface Bounds {
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface OcrLine {
  text: string;
  bounds: Bounds;
}
export interface Candidate {
  bani: number;
  bounds: Bounds;
  unit: Unit;
  kind: "regular" | "old" | "conditional" | "unit";
  assumed: boolean;
  caution?: string;
}
export interface Analysis {
  candidates: Candidate[];
  selected?: Candidate;
  needsConfirmation: boolean;
  message?: string;
}
export interface Rates {
  eurPerRon: string;
  uahPerRon: string;
  dataAsOf: number;
  fetchedAt: number;
  nextUpdateAt: number;
}
export interface Preferences {
  currencies: Currency[];
  decimals: 0 | 2;
}
export const defaultPreferences: Preferences = {
  currencies: ["EUR", "UAH"],
  decimals: 2,
};
export interface HistoryEntry {
  id: string;
  createdAt: number;
  bani: number;
  unit: Unit;
  origin: "camera" | "photo" | "manual";
  corrected: boolean;
  assumed: boolean;
  caution?: string;
  rates: Rates | null;
  eur: string | null;
  uah: string | null;
}

const ron = /(?<![a-z])(?:ron|lei)(?![a-z])/i;
const foreign = /(?<![a-z])(?:eur|uah|usd|gbp|pln|huf|mdl)(?![a-z])|[€$₴£]/i;
const old = /\b(?:vechi|veche|old|was)\b|старая|стара/i;
const conditional =
  /\b(?:card|loialitate|fidelitate|cumperi|bucati|bucăți)\b|по карте|при покупке/i;

export function parseManualPrice(input: string): number | null {
  const value = input.trim();
  if (!/^\d+(?:[.,]\d{1,2})?$/.test(value)) return null;
  const [whole, fraction = ""] = value.split(/[.,]/);
  const bani = Number(whole + fraction.padEnd(2, "0"));
  return Number.isSafeInteger(bani) ? bani : null;
}

function parseOcrNumber(
  raw: string,
): { bani: number; ambiguous: boolean } | null {
  const value = raw.replace(/\u00a0/g, " ");
  if (/^\d{1,3}(?:[. ]\d{3})+,\d{1,2}$/.test(value)) {
    const bani = parseManualPrice(value.replace(/[. ]/g, ""));
    return bani === null ? null : { bani, ambiguous: false };
  }
  if (/^\d{1,3}(?:\.\d{3})+$/.test(value)) {
    const bani = parseManualPrice(value.replace(/\./g, ""));
    return bani === null ? null : { bani, ambiguous: true };
  }
  const bani = parseManualPrice(value);
  return bani === null ? null : { bani, ambiguous: false };
}

export function analyze(lines: OcrLine[]): Analysis {
  const candidates: Candidate[] = [];
  const hasForeign = lines.some((line) => foreign.test(line.text));
  let detachedCondition = false;
  for (const { text, bounds } of lines) {
    const hasRon = ron.test(text);
    if (foreign.test(text) || (hasForeign && !hasRon)) continue;
    const isOld = old.test(text);
    const isConditional = conditional.test(text);
    let count = 0;
    for (const match of text.matchAll(
      /(?<![\p{L}\d.,])\d+(?:[.,]\d+|[ \u00a0]\d{3})*(?![\d.,])/gu,
    )) {
      const before = text.slice(0, match.index).trimEnd();
      const after = text.slice(match.index + match[0].length);
      if (
        /[-−/]$/.test(before) ||
        /^\s*%/.test(after) ||
        /^\s*(?:kg|g|mg|l|ml|buc)\b/i.test(after)
      )
        continue;
      const parsed = parseOcrNumber(match[0]);
      if (!parsed || (!/[.,]/.test(match[0]) && !hasRon && match[0].length > 6))
        continue;
      const unitMatch = /^\s*(?:(?:ron|lei)\s*)?\/\s*(kg|l)\b/i.exec(after);
      const unit: Unit = unitMatch
        ? unitMatch[1].toLowerCase() === "kg"
          ? "kg"
          : "litre"
        : "item";
      let caution = parsed.ambiguous
        ? "Проверьте разделитель в цене"
        : undefined;
      if (parsed.bani === 0) caution = "Подтвердите нулевую цену";
      if (!hasRon && !/[.,]/.test(match[0]))
        caution = "Подтвердите, что это цена в RON";
      if (isConditional) caution = "У этой цены есть условия акции";
      if (unit !== "item") caution = "Это цена за единицу измерения";
      candidates.push({
        bani: parsed.bani,
        bounds,
        unit,
        kind: isOld
          ? "old"
          : isConditional
            ? "conditional"
            : unit !== "item"
              ? "unit"
              : "regular",
        assumed: !hasRon,
        caution,
      });
      count++;
    }
    if ((isOld || isConditional) && !count) detachedCondition = true;
  }
  const usable = candidates.filter((candidate) => candidate.kind !== "old");
  const ordinary = usable.filter((candidate) => candidate.kind === "regular");
  const selected = ordinary[0] ?? usable[0];
  const multiple =
    ordinary.length > 1 || (!ordinary.length && usable.length > 1);
  return {
    candidates: usable,
    selected,
    needsConfirmation: multiple || detachedCondition || !!selected?.caution,
    message: multiple
      ? "Несколько цен — выберите нужную"
      : detachedCondition
        ? "Проверьте условия и основную цену"
        : (selected?.caution ??
          (hasForeign ? "Нужен ценник в RON или LEI" : undefined)),
  };
}

function formatMinor(value: bigint, decimals: number): string {
  if (decimals === 0) return value.toString();
  const digits = value.toString().padStart(decimals + 1, "0");
  return `${digits.slice(0, -decimals)},${digits.slice(-decimals)}`;
}
export function formatBani(bani: number): string {
  return formatMinor(BigInt(bani), 2);
}
export function exactConversion(bani: number, rate: string): string {
  if (!Number.isSafeInteger(bani) || bani < 0 || !/^\d+(?:\.\d+)?$/.test(rate))
    throw new Error("Некорректная сумма или курс");
  const [whole, fraction = ""] = rate.split(".");
  const numerator = BigInt(whole + fraction);
  if (numerator <= 0n) throw new Error("Курс должен быть положительным");
  return formatMinor(BigInt(bani) * numerator, fraction.length + 2).replace(
    ",",
    ".",
  );
}
export function formatExact(amount: string, decimals: 0 | 2): string {
  const [whole, fraction = ""] = amount.split(".");
  const divisor = 10n ** BigInt(fraction.length);
  const product = BigInt(whole + fraction) * 10n ** BigInt(decimals);
  return formatMinor((product * 2n + divisor) / (divisor * 2n), decimals);
}
export function makeEntry(
  id: string,
  price: Candidate,
  rates: Rates | null,
  origin: HistoryEntry["origin"],
  corrected = false,
  createdAt = Date.now(),
): HistoryEntry {
  return {
    id,
    createdAt,
    bani: price.bani,
    unit: price.unit,
    origin,
    corrected,
    assumed: price.assumed,
    caution: price.caution,
    rates: rates ? { ...rates } : null,
    eur: rates ? exactConversion(price.bani, rates.eurPerRon) : null,
    uah: rates ? exactConversion(price.bani, rates.uahPerRon) : null,
  };
}
export function unitSuffix(unit: Unit): string {
  return unit === "kg" ? " / кг" : unit === "litre" ? " / л" : "";
}

export function samePrice(a: Candidate, b: Candidate): boolean {
  const x = Math.max(a.bounds.x, b.bounds.x);
  const y = Math.max(a.bounds.y, b.bounds.y);
  const width = Math.max(
    0,
    Math.min(a.bounds.x + a.bounds.width, b.bounds.x + b.bounds.width) - x,
  );
  const height = Math.max(
    0,
    Math.min(a.bounds.y + a.bounds.height, b.bounds.y + b.bounds.height) - y,
  );
  const area = width * height;
  const union =
    a.bounds.width * a.bounds.height + b.bounds.width * b.bounds.height - area;
  return (
    a.bani === b.bani &&
    a.unit === b.unit &&
    a.kind === b.kind &&
    union > 0 &&
    area / union >= 0.5
  );
}

export class PriceTracker {
  status: "searching" | "checking" | "stable" | "confirmation" | "fixed" =
    "searching";
  candidate?: Candidate;
  analysis: Analysis = { candidates: [], needsConfirmation: false };
  eventId?: number;
  private nextId = 0;
  private consecutive = 0;
  private lastSeen = 0;
  private scene?: { price: Candidate; id: number; seen: number };

  observe(result: Analysis, now = Date.now()): void {
    if (this.status === "fixed") return;
    this.expire(now);
    this.analysis = result;
    const selected = result.selected;
    if (!selected) {
      this.consecutive = 0;
      return;
    }
    this.consecutive =
      this.candidate && samePrice(this.candidate, selected)
        ? this.consecutive + 1
        : 1;
    this.candidate = selected;
    this.lastSeen = now;
    this.status = result.needsConfirmation
      ? "confirmation"
      : this.consecutive >= 2
        ? "stable"
        : "checking";
    this.eventId =
      this.scene && samePrice(this.scene.price, selected)
        ? this.scene.id
        : undefined;
    if (this.status === "stable") this.remember(selected, now);
    else if (this.scene && this.eventId) this.scene.seen = now;
  }
  private remember(price: Candidate, now: number): void {
    const id =
      this.scene && samePrice(this.scene.price, price)
        ? this.scene.id
        : ++this.nextId;
    this.scene = { price, id, seen: now };
    this.eventId = id;
  }
  fix(price: Candidate, now = Date.now()): void {
    if (!this.eventId) this.remember(this.candidate ?? price, now);
    this.candidate = price;
    this.status = "fixed";
  }
  expire(now = Date.now()): boolean {
    if (this.status === "fixed") return false;
    if (this.scene && now - this.scene.seen >= 3000) this.scene = undefined;
    if (!this.candidate || now - this.lastSeen < 3000) return false;
    this.reset();
    return true;
  }
  reset(preserveScene = false, now = Date.now()): void {
    this.status = "searching";
    this.candidate = undefined;
    this.consecutive = 0;
    this.eventId = undefined;
    this.analysis = { candidates: [], needsConfirmation: false };
    if (preserveScene && this.scene) this.scene.seen = now;
    else this.scene = undefined;
  }
}
