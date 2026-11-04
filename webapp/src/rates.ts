import type { Rates } from "./domain.ts";

export const ratesSource = "https://www.exchangerate-api.com";
export function parseRates(value: unknown, now = Date.now()): Rates {
  const data = value as Record<string, unknown> | null;
  const values = data?.rates as Record<string, unknown> | undefined;
  const seconds = data?.time_last_update_unix;
  const next = data?.time_next_update_unix;
  if (
    data?.result !== "success" ||
    data.base_code !== "RON" ||
    !values ||
    values.RON !== 1 ||
    typeof seconds !== "number" ||
    !Number.isSafeInteger(seconds) ||
    seconds <= 0 ||
    seconds * 1000 > now + 300_000 ||
    typeof next !== "number" ||
    !Number.isSafeInteger(next) ||
    next <= seconds
  )
    throw new Error("Не удалось проверить дату и базу курса");
  for (const currency of ["EUR", "UAH"]) {
    const rate = values[currency];
    if (
      typeof rate !== "number" ||
      !Number.isFinite(rate) ||
      rate <= 0 ||
      !/^\d+(?:\.\d+)?$/.test(String(rate))
    ) {
      throw new Error("Источник вернул некорректный курс");
    }
  }
  return {
    eurPerRon: String(values.EUR),
    uahPerRon: String(values.UAH),
    dataAsOf: seconds * 1000,
    fetchedAt: now,
    nextUpdateAt: next * 1000,
  };
}
export async function fetchRates(): Promise<Rates> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch("https://open.er-api.com/v6/latest/RON", {
      signal: controller.signal,
      cache: "no-store",
      credentials: "omit",
    });
    if (!response.ok)
      throw new Error(
        response.status === 429
          ? "Слишком частые запросы. Попробуйте позже"
          : "Источник курсов временно недоступен",
      );
    return parseRates(await response.json());
  } finally {
    clearTimeout(timeout);
  }
}
export function shouldRefresh(
  rates: Rates | null,
  lastAttempt: number,
  now = Date.now(),
): boolean {
  return (
    now - lastAttempt >= 3_600_000 &&
    (!rates ||
      (now >= rates.nextUpdateAt && now - rates.fetchedAt >= 3_600_000))
  );
}
