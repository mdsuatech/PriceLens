import { test } from "node:test";
import assert from "node:assert/strict";
import {
  analyze,
  exactConversion,
  formatExact,
  makeEntry,
  parseManualPrice,
  PriceTracker,
  type OcrLine,
} from "../src/domain.ts";
import { parseRates, shouldRefresh } from "../src/rates.ts";

function lines(...texts: string[]): OcrLine[] {
  return texts.map((text, index) => ({
    text,
    bounds: { x: 0.1, y: 0.1 + index * 0.2, width: 0.5, height: 0.15 },
  }));
}
for (const [text, bani] of Object.entries({
  "24,99 RON": 2499,
  "24,99RON": 2499,
  "24.99 LEI": 2499,
  "1.299,00 RON": 129900,
  "1 299,00 LEI": 129900,
  "1\u00a0299,00 lei": 129900,
  "15,99": 1599,
  "24 LEI": 2400,
  "24,9 RON": 2490,
  "0,99 RON": 99,
})) {
  test(`Recognizes ${text}`, () => {
    const result = analyze(lines(text));
    assert.equal(result.selected?.bani, bani);
    assert.equal(result.needsConfirmation, false);
  });
}
for (const text of [
  "-20%",
  "500 g",
  "1 L",
  "03.11.2026",
  "5941234567890",
  "12,3456",
  "1.29,00",
  "1,299.00",
  "O,99 RON",
  "-24,99 RON",
  "24,99EUR",
]) {
  test(`Rejects ${text}`, () =>
    assert.equal(analyze(lines(text)).candidates.length, 0));
}
test("Detached foreign marker blocks the RON assumption", () =>
  assert.equal(analyze(lines("24,99", "EUR")).candidates.length, 0));
test("Assumed RON remains explicit", () =>
  assert.equal(analyze(lines("15,99")).selected?.assumed, true));
for (const text of ["1.299 RON", "1299", "0,00 RON", "24 99 LEI"]) {
  test(`Asks to confirm ${text}`, () =>
    assert.equal(analyze(lines(text)).needsConfirmation, true));
}
test("Ordinary price takes priority over labelled old, card and unit prices", () => {
  const result = analyze(
    lines(
      "PRET VECHI 29,99 LEI",
      "24,99 LEI",
      "CU CARD 19,99 LEI",
      "49,98 LEI/kg",
    ),
  );
  assert.equal(result.selected?.bani, 2499);
  assert.equal(result.needsConfirmation, false);
});
test("Multiple ordinary prices and detached conditions require confirmation", () => {
  assert.equal(
    analyze(lines("29,99 LEI", "19,99 LEI")).needsConfirmation,
    true,
  );
  assert.equal(analyze(lines("CU CARD", "19,99 LEI")).needsConfirmation, true);
});
test("Unit price preserves its meaning", () => {
  const result = analyze(lines("19,98 LEI/kg"));
  assert.equal(result.selected?.unit, "kg");
  assert.equal(result.needsConfirmation, true);
});
test("Manual input rejects ambiguous, malformed and unsafe numbers", () => {
  assert.equal(parseManualPrice("24.9"), 2490);
  assert.equal(parseManualPrice("0"), 0);
  for (const value of [
    "",
    "-1",
    "1.299",
    "1 299",
    "24,999",
    "RON",
    "NaN",
    "999999999999999999",
  ])
    assert.equal(parseManualPrice(value), null);
});
test("Exact conversion rounds only once, half-up at either display precision", () => {
  assert.equal(exactConversion(2499, "0.2"), "4.998");
  assert.equal(formatExact(exactConversion(2499, "0.2"), 2), "5,00");
  assert.equal(formatExact(exactConversion(5, "0.1"), 2), "0,01");
  assert.equal(formatExact(exactConversion(5, "10"), 0), "1");
  assert.throws(() => exactConversion(2499, "NaN"));
  assert.throws(() => exactConversion(2499, "0"));
});
const now = Date.UTC(2026, 10, 4);
const response = {
  result: "success",
  base_code: "RON",
  rates: { RON: 1, EUR: 0.2, UAH: 10 },
  time_last_update_unix: now / 1000,
  time_next_update_unix: now / 1000 + 86400,
};
test("Rate adapter validates direction and the entire snapshot", () => {
  assert.equal(parseRates(response, now).eurPerRon, "0.2");
  for (const invalid of [
    { ...response, base_code: "EUR" },
    { ...response, rates: { ...response.rates, UAH: 0 } },
    { ...response, time_last_update_unix: now / 1000 + 86400 },
    { ...response, time_next_update_unix: 0 },
  ]) {
    assert.throws(() => parseRates(invalid, now));
  }
});
test("Rate refresh respects publication schedule and persists failed-attempt cooldown", () => {
  const rates = parseRates(response, now);
  assert.equal(shouldRefresh(rates, now, now + 3_600_000), false);
  assert.equal(shouldRefresh(rates, now, now + 86_400_000), true);
  assert.equal(shouldRefresh(null, now, now + 1000), false);
});
test("Historical conversion keeps the original snapshot and absent rates stay absent", () => {
  const price = analyze(lines("24,99 RON")).selected!;
  const rates = parseRates(response, now);
  const entry = makeEntry("one", price, rates, "camera");
  rates.eurPerRon = "1";
  assert.equal(entry.eur, "4.998");
  assert.equal(entry.rates?.eurPerRon, "0.2");
  assert.equal(makeEntry("two", price, null, "manual").eur, null);
});
test("Stable event survives a missed frame and changes after a sustained absence", () => {
  const tracker = new PriceTracker();
  const result = analyze(lines("24,99 RON"));
  tracker.observe(result, now);
  tracker.observe(result, now + 500);
  assert.equal(tracker.status, "stable");
  const event = tracker.eventId;
  tracker.observe(analyze([]), now + 700);
  tracker.observe(result, now + 1000);
  tracker.observe(result, now + 1500);
  assert.equal(tracker.eventId, event);
  tracker.expire(now + 5000);
  tracker.observe(result, now + 5100);
  tracker.observe(result, now + 5600);
  assert.notEqual(tracker.eventId, event);
});
test("Fix, correct and resume preserve the original event identity", () => {
  const tracker = new PriceTracker();
  const result = analyze(lines("24,99 RON"));
  tracker.observe(result, now);
  tracker.observe(result, now + 500);
  const event = tracker.eventId;
  tracker.fix({ ...tracker.candidate!, bani: 2599 }, now + 600);
  assert.equal(tracker.eventId, event);
  assert.equal(tracker.expire(now + 20_000), false);
  tracker.reset(true, now + 20_000);
  tracker.observe(result, now + 20_100);
  tracker.observe(result, now + 20_600);
  assert.equal(tracker.eventId, event);
});
test("Moving to a new label with the same amount creates an event", () => {
  const tracker = new PriceTracker();
  const result = analyze(lines("24,99 RON"));
  tracker.observe(result, now);
  tracker.observe(result, now + 500);
  const event = tracker.eventId;
  const moved = analyze([
    { text: "24,99 RON", bounds: { x: 0.7, y: 0.7, width: 0.2, height: 0.1 } },
  ]);
  tracker.observe(moved, now + 1000);
  tracker.observe(moved, now + 1500);
  assert.notEqual(tracker.eventId, event);
});
