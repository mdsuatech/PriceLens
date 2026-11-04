import { test, expect, type Page } from "@playwright/test";

async function mockRates(page: Page): Promise<void> {
  await page.route("https://open.er-api.com/**", (route) =>
    route.fulfill({
      json: {
        result: "success",
        base_code: "RON",
        rates: { RON: 1, EUR: 0.2, UAH: 10 },
        time_last_update_unix: Math.floor(Date.now() / 1000) - 3600,
        time_next_update_unix: Math.floor(Date.now() / 1000) + 86400,
      },
    }),
  );
}
async function saveManual(page: Page, amount: string): Promise<void> {
  await page
    .getByRole("button", { name: "Ввести вручную", exact: true })
    .click();
  await page.getByLabel("Цена RON", { exact: true }).fill(amount);
  await page.getByRole("button", { name: "Сохранить цену" }).click();
  await expect(page.getByRole("dialog")).toBeHidden();
}
test("Manual price, correction, preferences and history survive an offline reload", async ({
  page,
  context,
}) => {
  await mockRates(page);
  await page.goto("./");
  await page.screenshot({
    path: "../.dart_tool/pricelens-web-mobile.png",
    fullPage: true,
  });
  await expect(page.locator("#connection")).toContainText("Готово офлайн", {
    timeout: 30_000,
  });
  await expect(page.locator("#rate-summary")).toContainText("Курсы");
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.screenshot({
    path: "../.dart_tool/pricelens-web-desktop.png",
    fullPage: true,
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await saveManual(page, "24,99");
  await expect(page.locator("#result")).toContainText("5,00");
  await page.getByRole("button", { name: "Исправить цену" }).click();
  await page.getByLabel("Цена RON", { exact: true }).fill("25,99");
  await page.getByRole("button", { name: "Сохранить цену" }).click();
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await expect(page.locator(".history-card")).toContainText("25,99");
  await page.getByRole("link", { name: "Настройки", exact: true }).click();
  await page
    .getByRole("combobox", { name: "Основная валюта", exact: true })
    .selectOption("UAH");
  await page.getByRole("radio", { name: "Без дроби" }).check();
  await page.getByRole("switch", { name: "Показывать EUR" }).uncheck();
  await page.getByRole("switch", { name: "Показывать UAH" }).click();
  await expect(
    page.getByRole("switch", { name: "Показывать UAH" }),
  ).toBeChecked();
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole("radio", { name: "Без дроби" })).toBeChecked();
  await expect(
    page.getByRole("switch", { name: "Показывать EUR" }),
  ).not.toBeChecked();
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await expect(page.locator(".history-card")).toContainText("260");
  await page.locator(".history-card").click();
  await expect(page.locator("#entry-details")).toContainText("0.2 EUR");
  await page.getByRole("button", { name: "Закрыть" }).click();
  await page
    .getByRole("button", { name: "Очистить историю", exact: true })
    .click();
  await page.getByRole("button", { name: "Отмена", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await page
    .getByRole("button", { name: "Очистить историю", exact: true })
    .click();
  await page.getByRole("button", { name: "Удалить записи" }).click();
  await expect(
    page.getByRole("heading", { name: "Здесь будут ваши находки" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "Настройки", exact: true }).click();
  await expect(page.getByRole("radio", { name: "Без дроби" })).toBeChecked();
  await expect(page.locator("#rates-details")).toContainText("0.2 EUR");
});
test("Real OCR initializes and reads a generated price label entirely offline", async ({
  page,
  context,
}) => {
  const failures: string[] = [];
  page.on("pageerror", (error) => failures.push(error.message));
  await mockRates(page);
  await page.goto("./");
  await expect(page.locator("#connection")).toContainText("Готово офлайн", {
    timeout: 30_000,
  });
  await expect(page.locator("#rate-summary")).toContainText("Курсы");
  const encoded = await page.evaluate(() => {
    const canvas = document.createElement("canvas");
    canvas.width = 1000;
    canvas.height = 400;
    const context = canvas.getContext("2d")!;
    context.fillStyle = "#fff";
    context.fillRect(0, 0, 1000, 400);
    context.fillStyle = "#000";
    context.font = "bold 120px Arial";
    context.fillText("24,99 RON", 90, 245);
    return canvas.toDataURL("image/png").split(",")[1];
  });
  await context.setOffline(true);
  await page.reload();
  await page
    .locator("#photo-input")
    .setInputFiles({
      name: "generated-price.png",
      mimeType: "image/png",
      buffer: Buffer.from(encoded, "base64"),
    });
  await expect(page.locator("#result .source-price")).toContainText("24,99", {
    timeout: 40_000,
  });
  await expect(page.locator("#result-status")).toHaveText("Проверьте");
  await expect(page.locator("#result")).toContainText("5,00");
  await page.getByRole("button", { name: "Подтвердить цену" }).click();
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await expect(page.locator(".history-card")).toContainText("Фото");
  expect(failures).toEqual([]);
});
test("Camera tracks stop on navigation and a late OCR result cannot populate another screen", async ({
  page,
}) => {
  await mockRates(page);
  await page.goto("./");
  await page
    .getByRole("button", { name: "Включить камеру", exact: true })
    .click();
  await expect(page.locator("#camera-label")).toHaveText("Камера включена");
  await expect
    .poll(() =>
      page
        .locator("#video")
        .evaluate((video) => (video as HTMLVideoElement).videoWidth),
    )
    .toBeGreaterThan(0);
  const converted = await page
    .locator("#result .conversion")
    .last()
    .boundingBox();
  expect(converted!.y + converted!.height).toBeLessThan(770);
  await page.screenshot({
    path: "../.dart_tool/pricelens-web-camera.png",
    fullPage: true,
  });
  await page.getByRole("link", { name: "Настройки", exact: true }).click();
  await expect
    .poll(() =>
      page
        .locator("#video")
        .evaluate((video) => (video as HTMLVideoElement).srcObject),
    )
    .toBeNull();
  await page.getByRole("link", { name: "Сканер", exact: true }).click();
  await expect(page.locator("#result-status")).toHaveText("Ожидание");
  await expect(
    page.getByRole("button", { name: "Фиксировать цену", exact: true }),
  ).toBeDisabled();
});
test("History cap is transactional, current rates do not rewrite saved conversions, layout fits mobile", async ({
  page,
}) => {
  await mockRates(page);
  await page.goto("./");
  await expect(page.locator("#rate-summary")).toContainText("Курсы");
  await saveManual(page, "24,99");
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await page.evaluate(async () => {
    const name = "pricelens:/PriceLens/";
    const request = indexedDB.open(name, 1);
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("state", "readwrite");
      const get = tx.objectStore("state").get("rates");
      get.onsuccess = () =>
        tx.objectStore("state").put({ ...get.result, eurPerRon: "1" }, "rates");
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  });
  await page.reload();
  await expect(page.locator(".history-card")).toContainText("5,00");
  await page.locator(".history-card").click();
  await expect(page.locator("#entry-details")).toContainText("0.2 EUR");
  await page.getByRole("button", { name: "Закрыть" }).click();
  await page.getByRole("link", { name: "Настройки", exact: true }).click();
  await expect(page.locator("#rates-details")).toContainText("1 EUR");
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth > innerWidth,
  );
  expect(overflow).toBe(false);
  await page.evaluate(async () => {
    const request = indexedDB.open("pricelens:/PriceLens/", 1);
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction("history", "readwrite");
      const store = tx.objectStore("history");
      for (let i = 0; i < 100; i++)
        store.put({
          id: `older-${i}`,
          createdAt: Date.now() - 100000 + i,
          bani: 100,
          unit: "item",
          origin: "manual",
          corrected: false,
          assumed: false,
          rates: null,
          eur: null,
          uah: null,
        });
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    db.close();
  });
  await page.getByRole("link", { name: "Сканер", exact: true }).click();
  await saveManual(page, "49,99");
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(100);
  await expect(page.locator(".history-card").first()).toContainText("49,99");
  await expect(page.locator(".history-card").nth(1)).toContainText("24,99");
});

test("First launch without rates saves RON and never supplies invented conversions", async ({
  page,
}) => {
  await page.route("https://open.er-api.com/**", (route) => route.abort());
  await page.goto("./");
  await saveManual(page, "0,99");
  await expect(page.locator("#result")).toContainText(
    "Для пересчёта загрузите курсы",
  );
  await expect(page.locator("#result .converted-value")).toHaveText([
    "—€",
    "—₴",
  ]);
  await page.getByRole("link", { name: "История", exact: true }).click();
  await expect(page.locator(".history-card")).toHaveCount(1);
  await page.locator(".history-card").click();
  await expect(page.locator("#entry-details")).toContainText(
    "На момент сохранения курс отсутствовал",
  );
});
