import "./style.css";
import {
  analyze,
  defaultPreferences,
  exactConversion,
  formatBani,
  formatExact,
  makeEntry,
  parseManualPrice,
  PriceTracker,
  unitSuffix,
  type Candidate,
  type Currency,
  type HistoryEntry,
  type Preferences,
  type Rates,
} from "./domain.ts";
import {
  clearHistory,
  listHistory,
  readAttempt,
  readPreferences,
  readRates,
  saveEntry,
  writeState,
} from "./storage.ts";
import { fetchRates, ratesSource, shouldRefresh } from "./rates.ts";
import { Camera, drawBounds, LocalOcr, photoCanvas } from "./scanner.ts";

const icons = {
  scan: '<path d="M8 3H5a2 2 0 0 0-2 2v3m13-5h3a2 2 0 0 1 2 2v3M3 16v3a2 2 0 0 0 2 2h3m8 0h3a2 2 0 0 0 2-2v-3M7 12h10"/>',
  history: '<path d="M3 11a9 9 0 1 1 2.7 7M3 4v7h7m2-5v6l4 2"/>',
  settings:
    '<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3"/><circle cx="15" cy="17" r="3"/>',
  camera:
    '<path d="M14 4h-4L8 7H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-4z"/><circle cx="12" cy="13" r="4"/>',
  flash: '<path d="m13 2-9 12h7l-1 8 10-13h-7z"/>',
  flip: '<path d="M4 8a8 8 0 0 1 14-3l3 3m0-6v6h-6M20 16a8 8 0 0 1-14 3l-3-3m0 6v-6h6"/>',
  arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
  edit: '<path d="m16 3 5 5-12 12-6 1 1-6zM13 6l5 5"/>',
  photo:
    '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1"/><path d="m3 17 6-6 5 5 3-3 4 4"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
};
const icon = (name: keyof typeof icons) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
function element<T extends HTMLElement = HTMLElement>(id: string): T {
  return document.getElementById(id) as T;
}
function escape(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        character
      ]!,
  );
}
const date = (time: number) =>
  new Intl.DateTimeFormat("ru", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(time);

element("app").innerHTML = `
  <header class="topbar">
    <a class="brand" href="#scan" aria-label="PriceLens — сканер">${icon("scan")}<span>Price<span class="brand-light">Lens</span>
    </span>
    </a>
    <nav aria-label="Разделы приложения">
      <a href="#scan" data-view="scan">${icon("scan")}<span>Сканер</span>
    </a>
      <a href="#history" data-view="history">${icon("history")}<span>История</span>
    </a>
      <a href="#settings" data-view="settings">${icon("settings")}<span>Настройки</span>
    </a>
    </nav>
    <span class="connection" id="connection">
    <i>
    </i>
    <span>Проверяем кэш</span>
    </span>
  </header>
  <main>
    <section id="scan-view">
      <div class="page-heading">
    <div>
    <p class="eyebrow">ПОКУПКИ В РУМЫНИИ</p>
    <h1>Цены в привычной<br class="mobile-break"> валюте.</h1>
    <p class="intro">Наведите камеру на ценник в леях — увидите сумму в евро и гривнах.</p>
    </div>
    <span class="local-badge">${icon("check")}Распознавание на устройстве</span>
    </div>
      <div class="scan-layout">
        <section class="camera-panel" aria-label="Камера сканера">
          <div class="camera-top">
    <span class="camera-label">
    <i id="camera-dot">
    </i> <span id="camera-label">Камера выключена</span>
    </span>
    <span class="currency-tag">RON / LEI</span>
    </div>
          <div class="viewport" id="viewport">
            <video id="video" autoplay muted playsinline aria-label="Изображение с камеры">
    </video>
            <img id="photo-preview" alt="Выбранный ценник" hidden />
            <div class="guide" id="guide">
    <span class="corner tl">
    </span>
    <span class="corner tr">
    </span>
    <span class="corner bl">
    </span>
    <span class="corner br">
    </span>
    <div id="detected-bounds" class="detected-bounds" hidden>
    </div>
    </div>
            <div class="camera-idle" id="camera-idle">
    <div class="lens-symbol">${icon("scan")}</div>
    <h2>Ценник — в рамку</h2>
    <p>Разрешите доступ к камере.<br>Распознавание начнётся автоматически.</p>
    <button class="button lime" id="start-camera">${icon("camera")}Включить камеру</button>
    </div>
            <p class="scan-hint" id="scan-hint" role="status">Подойдите ближе, чтобы цифры были чёткими</p>
          </div>
          <div class="camera-bottom">
    <span>Кадры остаются на вашем устройстве</span>
    <div class="camera-tools">
    <button id="torch" class="icon-button" aria-label="Включить фонарик" disabled>${icon("flash")}</button>
    <button id="flip" class="icon-button" aria-label="Сменить камеру" disabled>${icon("flip")}</button>
    <button id="pause" class="small-button" disabled>Пауза</button>
    </div>
    </div>
        </section>
        <aside class="result-panel" aria-label="Результат сканирования">
    <div class="result-top">
    <span class="eyebrow">ВАШ ЦЕННИК</span>
    <span id="result-status" class="status-chip">Ожидание</span>
    </div>
    <div id="result" aria-live="polite">
    </div>
    <div class="result-actions">
    <button id="fix" class="button primary" disabled>${icon("check")}Фиксировать цену</button>
    <button id="manual" class="button secondary">${icon("edit")}Ввести вручную</button>
    </div>
    <p class="result-footnote">Справочный пересчёт.<br>Сумма списания банка может отличаться.</p>
    </aside>
      </div>
      <div class="scan-under">
    <div>
    <span class="step-number">01</span>
    <span>Наведите камеру</span>
    <span class="step-line">
    </span>
    <span class="step-number">02</span>
    <span>Дождитесь цены</span>
    <span class="step-line">
    </span>
    <span class="step-number">03</span>
    <span>Сравните</span>
    </div>
    <button id="upload" class="text-button">${icon("photo")}Открыть фото ценника</button>
    <input id="photo-input" type="file" accept="image/*" hidden />
    </div>
    </section>
    <section id="history-view" hidden>
    <div class="page-heading">
    <div>
    <p class="eyebrow">ВАШИ НАХОДКИ</p>
    <h1>История цен</h1>
    <p class="intro">Последние 100 событий с курсом на момент сканирования.</p>
    </div>
    <button class="button secondary" id="clear-history">Очистить историю</button>
    </div>
    <div id="history-list">
    </div>
    </section>
    <section id="settings-view" hidden>
    <div class="page-heading">
    <div>
    <p class="eyebrow">ПОД ВАШИ ПОКУПКИ</p>
    <h1>Настройки</h1>
    <p class="intro">Выберите, как показывать пересчитанные цены.</p>
    </div>
    </div>
    <div class="settings-grid">
    <section class="settings-card">
    <h2>Валюты и отображение</h2>
    <p>RON всегда остаётся исходной валютой.</p>
    <label class="setting-row">
    <span>Евро <small>EUR</small>
    </span>
    <input type="checkbox" id="show-eur" role="switch" aria-label="Показывать EUR" />
    </label>
    <label class="setting-row">
    <span>Гривна <small>UAH</small>
    </span>
    <input type="checkbox" id="show-uah" role="switch" aria-label="Показывать UAH" />
    </label>
    <label class="setting-row" for="primary-currency">
    <span>Основная валюта</span>
    <select id="primary-currency">
    <option value="EUR">EUR — евро</option>
    <option value="UAH">UAH — гривна</option>
    </select>
    </label>
    <fieldset>
    <legend>Знаков после запятой</legend>
    <div class="segmented">
    <label>
    <input type="radio" name="decimals" value="2" />Два · 5,00</label>
    <label>
    <input type="radio" name="decimals" value="0" />Без дроби · 5</label>
    </div>
    </fieldset>
    <p class="muted">Настройки меняют отображение. История сохраняет исходные суммы и курсы.</p>
    </section>
    <div>
    <section class="settings-card">
    <h2>Курсы валют</h2>
    <div id="rates-details">
    </div>
    <button class="button secondary" id="refresh-rates">Обновить курсы</button>
    <p class="muted">Котировки обновляются у источника раз в день. <a href="${ratesSource}" target="_blank" rel="noopener noreferrer">Источник ExchangeRate-API</a>
    </p>
    </section>
    <section class="settings-card offline-card">
    <h2>Приложение под рукой</h2>
    <p id="offline-details">Готовим приложение и распознавание для работы без сети…</p>
    <button id="install" class="button secondary" hidden>Установить приложение</button>
    <p class="muted">На iPhone откройте меню «Поделиться» в Safari и выберите «На экран “Домой”». История хранится в этом браузере.</p>
    </section>
    </div>
    </div>
    </section>
    <div class="rates-strip">
    <div>
    <span class="rates-dot">
    </span>
    <span id="rate-summary">Загружаем курсы…</span>
    </div>
    <span class="rates-links">
    <a href="${ratesSource}" target="_blank" rel="noopener noreferrer">ExchangeRate-API</a>
    <a href="#settings">Подробнее ${icon("arrow")}</a>
    </span>
    </div>
    <div class="notice" id="notice" role="status" hidden>
    </div>
    <div class="update-bar" id="update-bar" hidden>
    <span>Доступна новая версия PriceLens</span>
    <button id="update" class="text-button">Обновить</button>
    </div>
  </main>
  <footer>
    <span>PriceLens <span class="version">WEB 0.4.0</span>
    </span>
    <span>Сканируйте здесь. Покупайте где угодно.</span>
    </footer>
  <dialog id="manual-dialog">
    <form id="manual-form" novalidate>
    <div class="dialog-heading">
    <h2 id="manual-title">Цена вручную</h2>
    <button type="button" class="close-button" data-close="manual-dialog" aria-label="Закрыть">×</button>
    </div>
    <p>Укажите цену в румынских леях.</p>
    <label for="manual-price">Цена RON</label>
    <input id="manual-price" class="price-input" type="text" inputmode="decimal" placeholder="24,99" autocomplete="off" required />
    <label for="manual-unit">За что указана цена</label>
    <select id="manual-unit">
    <option value="item">За товар</option>
    <option value="kg">За килограмм</option>
    <option value="litre">За литр</option>
    </select>
    <p id="manual-error" class="error" role="alert">
    </p>
    <div class="dialog-actions">
    <button type="button" class="button secondary" data-close="manual-dialog">Отмена</button>
    <button class="button primary" type="submit">Сохранить цену</button>
    </div>
    </form>
    </dialog>
  <dialog id="details-dialog">
    <div class="dialog-heading">
    <h2>Сохранённая цена</h2>
    <button class="close-button" data-close="details-dialog" aria-label="Закрыть">×</button>
    </div>
    <div id="entry-details">
    </div>
    </dialog>
  <dialog id="clear-dialog">
    <h2>Очистить историю?</h2>
    <p>Все сохранённые цены будут удалены из этого браузера.</p>
    <div class="dialog-actions">
    <button class="button secondary" data-close="clear-dialog">Отмена</button>
    <button id="confirm-clear" class="button danger">Удалить записи</button>
    </div>
    </dialog>
`;

let preferences: Preferences = structuredClone(defaultPreferences);
let rates: Rates | null = null;
let lastAttempt = 0;
let refreshing = false;
let view = "scan";
let running = false;
let starting = false;
let generation = 0;
let frameTimer = 0;
let recognition: Promise<unknown> | undefined;
let origin: HistoryEntry["origin"] = "camera";
let activeEntry: HistoryEntry | undefined;
let writeQueue = Promise.resolve();
let history: HistoryEntry[] = [];
let resumeAfterDialog = false;
let offlineReady = false;
let offlineError = false;
let registration: ServiceWorkerRegistration | undefined;
let noticeTimer = 0;
const entries = new Map<number, HistoryEntry>();
const tracker = new PriceTracker();
const camera = new Camera(
  element<HTMLVideoElement>("video"),
  element("viewport"),
);
const ocr = new LocalOcr((message) => {
  element("scan-hint").textContent = message;
});

function notify(message: string): void {
  clearTimeout(noticeTimer);
  element("notice").textContent = message;
  element("notice").hidden = false;
  noticeTimer = window.setTimeout(() => {
    element("notice").hidden = true;
  }, 8000);
}
function errorMessage(error: unknown): string {
  if (error instanceof DOMException && error.name === "NotAllowedError")
    return "Доступ к камере закрыт. Разрешите его в настройках сайта или откройте фото ценника";
  if (error instanceof DOMException && error.name === "NotFoundError")
    return "Камера не найдена. Можно открыть фото или ввести цену";
  return error instanceof Error
    ? error.message
    : "Не удалось выполнить действие. Повторите";
}
function conversions(
  price: Candidate,
  snapshot: Rates | null,
  saved?: HistoryEntry,
): string {
  return preferences.currencies
    .map((currency, index) => {
      const exact = saved
        ? currency === "EUR"
          ? saved.eur
          : saved.uah
        : snapshot
          ? exactConversion(
              price.bani,
              currency === "EUR" ? snapshot.eurPerRon : snapshot.uahPerRon,
            )
          : null;
      return `<div class="conversion ${index === 0 ? "conversion-primary" : ""}"><span class="currency-name">${currency === "EUR" ? "Евро" : "Гривна"}<small>${currency}</small></span><span class="converted-value">${exact === null ? "—" : formatExact(exact, preferences.decimals)}<small>${currency === "EUR" ? "€" : "₴"}${unitSuffix(price.unit)}</small></span></div>`;
    })
    .join("");
}
function renderResult(): void {
  const price = tracker.candidate;
  const labels = {
    searching: "Ожидание",
    checking: "Проверяем",
    stable: "Цена найдена",
    confirmation: "Проверьте",
    fixed: "Зафиксировано",
  };
  element("result-status").textContent = labels[tracker.status];
  element("result-status").className = `status-chip ${tracker.status}`;
  const snapshot =
    tracker.status === "fixed" && activeEntry ? activeEntry.rates : rates;
  element("result").innerHTML =
    `<div class="source-price"><span>Цена в Румынии</span><div>${price ? formatBani(price.bani) : '<span class="placeholder-value">—</span>'}<small>RON${price ? unitSuffix(price.unit) : ""}</small></div></div><div class="conversion-divider"><span>В ВАШЕЙ ВАЛЮТЕ</span>${icon("arrow")}</div>${price ? conversions(price, snapshot, tracker.status === "fixed" ? activeEntry : undefined) : preferences.currencies.map((currency, i) => `<div class="conversion ${i === 0 ? "conversion-primary" : ""}"><span class="currency-name">${currency === "EUR" ? "Евро" : "Гривна"}<small>${currency}</small></span><span class="converted-value placeholder-value">—<small>${currency === "EUR" ? "€" : "₴"}</small></span></div>`).join("")}<p class="price-context">${price ? escape(tracker.analysis.message ?? (price.assumed ? "Валюта принята за RON" : tracker.status === "fixed" ? "Цена сохранена в истории" : "Цена распознана на устройстве")) : "Здесь появится распознанная цена"}</p>${tracker.status === "confirmation" && tracker.analysis.candidates.length > 1 ? `<div class="candidate-list">${tracker.analysis.candidates.map((candidate, i) => `<button class="candidate" data-candidate="${i}">${formatBani(candidate.bani)} RON${unitSuffix(candidate.unit)}</button>`).join("")}</div>` : ""}${price && !snapshot ? '<p class="warning">Для пересчёта загрузите курсы в настройках</p>' : ""}`;
  const fix = element<HTMLButtonElement>("fix");
  fix.disabled = !price;
  fix.innerHTML =
    tracker.status === "fixed"
      ? `${icon("scan")}Сканировать дальше`
      : `${icon("check")}${tracker.status === "confirmation" ? "Подтвердить цену" : "Фиксировать цену"}`;
  element("manual").innerHTML =
    `${icon("edit")}${price ? "Исправить цену" : "Ввести вручную"}`;
  drawBounds(
    element("detected-bounds"),
    origin === "camera" && running ? price?.bounds : undefined,
  );
}
function persist(price: Candidate, corrected = false): void {
  const eventId = tracker.eventId;
  if (!eventId) return;
  const previous = entries.get(eventId);
  const entry = makeEntry(
    previous?.id ?? crypto.randomUUID(),
    price,
    previous ? previous.rates : rates,
    origin,
    corrected || !!previous?.corrected,
    previous?.createdAt,
  );
  entries.set(eventId, entry);
  activeEntry = entry;
  writeQueue = writeQueue
    .then(() => saveEntry(entry))
    .catch(() =>
      notify(
        "Не удалось сохранить цену. Проверьте доступ к хранилищу браузера",
      ),
    );
}
function updateCameraControls(): void {
  element<HTMLButtonElement>("start-camera").disabled = starting;
  element("start-camera").innerHTML =
    `${icon("camera")}${starting ? "Открываем камеру…" : "Включить камеру"}`;
  element<HTMLButtonElement>("flip").disabled = !running || starting;
  const photoVisible = !element("photo-preview").hidden;
  document.body.classList.toggle(
    "scanner-active",
    running || tracker.status === "fixed" || photoVisible,
  );
  element<HTMLButtonElement>("pause").disabled = !running && !photoVisible;
  element("pause").textContent = !running && photoVisible ? "Камера" : "Пауза";
  element<HTMLButtonElement>("torch").disabled =
    !running || !camera.supportsTorch;
  element("torch").setAttribute("aria-pressed", String(camera.torch));
  element("torch").setAttribute(
    "aria-label",
    camera.torch ? "Выключить фонарик" : "Включить фонарик",
  );
  element("camera-dot").classList.toggle("live", running);
  element("camera-label").textContent = running
    ? "Камера включена"
    : tracker.status === "fixed"
      ? "Цена зафиксирована"
      : "Камера выключена";
  element("camera-idle").hidden =
    running || tracker.status === "fixed" || !element("photo-preview").hidden;
}
function stopCamera(reset = true): void {
  running = false;
  generation++;
  clearTimeout(frameTimer);
  camera.stop();
  if (reset) {
    tracker.reset();
    activeEntry = undefined;
  }
  drawBounds(element("detected-bounds"));
  updateCameraControls();
  renderResult();
}
async function startCamera(preserveScene = false): Promise<void> {
  if (starting) return;
  starting = true;
  stopCamera(false);
  tracker.reset(preserveScene);
  activeEntry = undefined;
  origin = "camera";
  element("photo-preview").hidden = true;
  element("guide").hidden = false;
  const token = generation;
  updateCameraControls();
  try {
    const opened = await camera.start();
    if (!opened || token !== generation || view !== "scan" || document.hidden)
      return;
    running = true;
    void scanFrame(token);
  } catch (error) {
    notify(errorMessage(error));
  } finally {
    starting = false;
    updateCameraControls();
    renderResult();
  }
}
async function scanFrame(token: number): Promise<void> {
  if (!running || generation !== token) return;
  if (recognition) {
    frameTimer = window.setTimeout(() => void scanFrame(token), 400);
    return;
  }
  try {
    if (!recognition) {
      recognition = ocr.recognize(camera.capture());
      const lines = (await recognition) as Awaited<
        ReturnType<LocalOcr["recognize"]>
      >;
      if (token !== generation || !running) return;
      const result = analyze(lines);
      tracker.observe(result);
      if (
        tracker.status === "stable" &&
        tracker.eventId &&
        !entries.has(tracker.eventId)
      )
        persist(tracker.candidate!);
      element("scan-hint").textContent =
        result.message ??
        (tracker.candidate
          ? "Держите камеру на ценнике"
          : "Ищем цену в рамке…");
      renderResult();
    }
  } catch (error) {
    if (generation === token) {
      stopCamera();
      notify(
        "Не удалось распознать ценник. Попробуйте ещё раз или введите цену",
      );
    }
  } finally {
    recognition = undefined;
    if (running && token === generation)
      frameTimer = window.setTimeout(() => void scanFrame(token), 400);
  }
}

function renderRates(): void {
  const stale = rates && Date.now() - rates.dataAsOf > 86_400_000;
  element("rate-summary").textContent = rates
    ? `${stale ? "Курс устарел" : "Курсы"} · ${date(rates.dataAsOf)}${!navigator.onLine ? " · сохранённые данные" : ""}`
    : "Курс ещё не загружен · доступна цена в RON";
  element("rates-details").innerHTML = rates
    ? `<p class="rates-date">Данные от ${date(rates.dataAsOf)}${stale ? " · курс устарел" : ""}</p><div class="rate-pair"><span>1 RON</span><strong>${escape(rates.eurPerRon)} EUR</strong></div><div class="rate-pair"><span>1 RON</span><strong>${escape(rates.uahPerRon)} UAH</strong></div><p class="muted">Сохранено ${date(rates.fetchedAt)}</p>`
    : "<p>Загрузите курсы, чтобы увидеть цену в EUR и UAH. Затем пересчёт будет доступен без сети.</p>";
  element<HTMLButtonElement>("refresh-rates").disabled = refreshing;
  element("refresh-rates").textContent = refreshing
    ? "Загружаем…"
    : "Обновить курсы";
}
async function refreshRates(manual = false): Promise<void> {
  if (
    refreshing ||
    (!manual && (!navigator.onLine || !shouldRefresh(rates, lastAttempt)))
  )
    return;
  refreshing = true;
  lastAttempt = Date.now();
  renderRates();
  try {
    await writeState("rateAttempt", lastAttempt);
    const next = await fetchRates();
    await writeState("rates", next);
    rates = next;
    if (manual) notify("Курсы обновлены");
  } catch {
    notify(
      rates
        ? "Не удалось обновить курсы. Используем сохранённый курс"
        : "Не удалось загрузить курсы. Цена в RON доступна, обновление можно повторить в настройках",
    );
  } finally {
    refreshing = false;
    renderRates();
    renderResult();
  }
}
function priceForEntry(entry: HistoryEntry): Candidate {
  return {
    bani: entry.bani,
    unit: entry.unit,
    assumed: entry.assumed,
    kind: "regular",
    bounds: { x: 0, y: 0, width: 1, height: 1 },
  };
}
async function renderHistory(): Promise<void> {
  element("history-list").innerHTML =
    '<div class="empty-state">Загружаем историю…</div>';
  try {
    await writeQueue;
    history = await listHistory();
    element<HTMLButtonElement>("clear-history").disabled = !history.length;
    element("history-list").innerHTML = history.length
      ? `<div class="history-grid">${history.map((entry) => `<button class="history-card" data-entry="${escape(entry.id)}"><span class="history-meta">${date(entry.createdAt)}<span>${entry.origin === "manual" ? "Вручную" : entry.origin === "photo" ? "Фото" : "Камера"}${entry.corrected ? " · исправлено" : ""}</span></span><strong>${formatBani(entry.bani)}<small>RON${unitSuffix(entry.unit)}</small></strong><div class="history-conversions">${conversions(priceForEntry(entry), entry.rates, entry)}</div><span class="history-link">Открыть детали ${icon("arrow")}</span></button>`).join("")}</div>`
      : `<div class="empty-state"><div class="empty-icon">${icon("history")}</div><h2>Здесь будут ваши находки</h2><p>Распознанные и введённые цены сохраняются автоматически.</p><a href="#scan" class="button primary">Открыть сканер ${icon("arrow")}</a></div>`;
  } catch {
    element("history-list").innerHTML =
      '<div class="empty-state"><p>Не удалось открыть историю</p><button class="button secondary" id="retry-history">Повторить</button></div>';
  }
}
function renderPreferences(): void {
  element<HTMLInputElement>("show-eur").checked =
    preferences.currencies.includes("EUR");
  element<HTMLInputElement>("show-uah").checked =
    preferences.currencies.includes("UAH");
  const primary = element<HTMLSelectElement>("primary-currency");
  for (const option of primary.options)
    option.disabled = !preferences.currencies.includes(
      option.value as Currency,
    );
  primary.value = preferences.currencies[0];
  document
    .querySelectorAll<HTMLInputElement>('input[name="decimals"]')
    .forEach((input) => {
      input.checked = Number(input.value) === preferences.decimals;
    });
}
let preferenceQueue = Promise.resolve();
function changePreferences(next: Preferences): void {
  preferences = next;
  renderPreferences();
  renderResult();
  preferenceQueue = preferenceQueue
    .then(() => writeState("preferences", next))
    .catch(() =>
      notify(
        "Не удалось сохранить настройки. Проверьте доступ к хранилищу браузера",
      ),
    );
}
function navigate(): void {
  const requested = location.hash.slice(1);
  const next = ["scan", "history", "settings"].includes(requested)
    ? requested
    : "scan";
  if (next !== view) {
    stopCamera();
    element("photo-preview").hidden = true;
  }
  view = next;
  for (const name of ["scan", "history", "settings"])
    element(`${name}-view`).hidden = name !== view;
  document
    .querySelectorAll<HTMLAnchorElement>("[data-view]")
    .forEach((link) => {
      if (link.dataset.view === view) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
  if (view === "history") void renderHistory();
  renderPreferences();
  renderRates();
}
function openManual(): void {
  resumeAfterDialog = running;
  stopCamera(false);
  element("manual-title").textContent = tracker.candidate
    ? "Исправить цену"
    : "Цена вручную";
  element<HTMLInputElement>("manual-price").value = tracker.candidate
    ? formatBani(tracker.candidate.bani)
    : "";
  element<HTMLSelectElement>("manual-unit").value =
    tracker.candidate?.unit ?? "item";
  element("manual-error").textContent = "";
  element<HTMLDialogElement>("manual-dialog").showModal();
  element("manual-price").focus();
}
element("manual-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const bani = parseManualPrice(
    element<HTMLInputElement>("manual-price").value,
  );
  if (bani === null) {
    element("manual-error").textContent =
      "Введите положительную сумму, например 24,99";
    return;
  }
  const corrected = !!tracker.candidate;
  if (!corrected) origin = "manual";
  const price: Candidate = {
    bani,
    unit: element<HTMLSelectElement>("manual-unit").value as Candidate["unit"],
    bounds: tracker.candidate?.bounds ?? { x: 0, y: 0, width: 1, height: 1 },
    kind: "regular",
    assumed: false,
  };
  tracker.fix(price);
  tracker.analysis = {
    candidates: [price],
    selected: price,
    needsConfirmation: false,
  };
  persist(price, corrected);
  resumeAfterDialog = false;
  element<HTMLDialogElement>("manual-dialog").close();
  updateCameraControls();
  renderResult();
});
element("manual-dialog").addEventListener("close", () => {
  if (resumeAfterDialog && view === "scan" && !document.hidden)
    void startCamera(true);
  resumeAfterDialog = false;
});
element("start-camera").addEventListener("click", () => void startCamera());
element("manual").addEventListener("click", openManual);
element("pause").addEventListener("click", () => {
  if (running) stopCamera();
  else void startCamera();
});
element("flip").addEventListener("click", () => {
  camera.facing = camera.facing === "environment" ? "user" : "environment";
  void startCamera();
});
element("torch").addEventListener(
  "click",
  () =>
    void camera
      .toggleTorch()
      .then(updateCameraControls)
      .catch(() => notify("Фонарик недоступен для этой камеры")),
);
element("fix").addEventListener("click", () => {
  if (tracker.status === "fixed") {
    void startCamera(true);
    return;
  }
  if (!tracker.candidate) return;
  tracker.fix(tracker.candidate);
  persist(tracker.candidate);
  stopCamera(false);
});
element("result").addEventListener("click", (event) => {
  const button = (event.target as HTMLElement).closest<HTMLElement>(
    "[data-candidate]",
  );
  if (!button) return;
  const candidate =
    tracker.analysis.candidates[Number(button.dataset.candidate)];
  if (!candidate) return;
  tracker.fix(candidate);
  persist(candidate);
  stopCamera(false);
});
element("upload").addEventListener("click", () =>
  element<HTMLInputElement>("photo-input").click(),
);
element("photo-input").addEventListener("change", async () => {
  const input = element<HTMLInputElement>("photo-input");
  const file = input.files?.[0];
  if (!file) return;
  input.value = "";
  stopCamera();
  const token = generation;
  origin = "photo";
  element<HTMLButtonElement>("upload").disabled = true;
  try {
    if (recognition) await recognition.catch(() => undefined);
    if (token !== generation || view !== "scan") return;
    const canvas = await photoCanvas(file);
    if (token !== generation) return;
    element<HTMLImageElement>("photo-preview").src = canvas.toDataURL(
      "image/jpeg",
      0.85,
    );
    element("photo-preview").hidden = false;
    element("guide").hidden = true;
    updateCameraControls();
    recognition = ocr.recognize(canvas);
    const lines = (await recognition) as Awaited<
      ReturnType<LocalOcr["recognize"]>
    >;
    if (token !== generation || view !== "scan") return;
    const result = analyze(lines);
    tracker.observe(result);
    if (result.selected) {
      tracker.status = "confirmation";
      element("scan-hint").textContent = "Проверьте цену с фотографии";
    } else
      element("scan-hint").textContent =
        result.message ??
        "Цена не найдена. Попробуйте другое фото или ручной ввод";
    renderResult();
  } catch {
    if (token === generation)
      notify(
        "Не удалось прочитать фото. Выберите другое изображение или введите цену",
      );
  } finally {
    recognition = undefined;
    element<HTMLButtonElement>("upload").disabled = false;
  }
});
element("refresh-rates").addEventListener(
  "click",
  () => void refreshRates(true),
);
for (const currency of ["EUR", "UAH"] as const)
  element(`show-${currency.toLowerCase()}`).addEventListener(
    "change",
    (event) => {
      const checked = (event.target as HTMLInputElement).checked;
      const currencies = checked
        ? [...preferences.currencies, currency]
        : preferences.currencies.filter((value) => value !== currency);
      if (!currencies.length) {
        notify("Оставьте хотя бы одну валюту пересчёта");
        renderPreferences();
        return;
      }
      changePreferences({ ...preferences, currencies });
    },
  );
element("primary-currency").addEventListener("change", (event) => {
  const first = (event.target as HTMLSelectElement).value as Currency;
  changePreferences({
    ...preferences,
    currencies: [
      first,
      ...preferences.currencies.filter((currency) => currency !== first),
    ],
  });
});
document
  .querySelectorAll<HTMLInputElement>('input[name="decimals"]')
  .forEach((input) =>
    input.addEventListener("change", () =>
      changePreferences({
        ...preferences,
        decimals: Number(input.value) as 0 | 2,
      }),
    ),
  );
element("history-list").addEventListener("click", (event) => {
  const button = (event.target as HTMLElement).closest<HTMLElement>(
    "[data-entry], #retry-history",
  );
  if (button?.id === "retry-history") {
    void renderHistory();
    return;
  }
  const entry = history.find((item) => item.id === button?.dataset.entry);
  if (!entry) return;
  element("entry-details").innerHTML =
    `<p class="muted">${date(entry.createdAt)} · ${entry.origin === "manual" ? "Введено вручную" : entry.origin === "photo" ? "С фотографии" : "С камеры"}${entry.corrected ? " · исправлено" : ""}</p><div class="detail-price">${formatBani(entry.bani)}<small>RON${unitSuffix(entry.unit)}</small></div>${conversions(priceForEntry(entry), entry.rates, entry)}${entry.assumed ? '<p class="muted">Валюта принята за RON</p>' : ""}${entry.caution ? `<p class="warning">${escape(entry.caution)}</p>` : ""}<p class="muted">${entry.rates ? `Сохранённый курс от ${date(entry.rates.dataAsOf)}<br>1 RON = ${escape(entry.rates.eurPerRon)} EUR · ${escape(entry.rates.uahPerRon)} UAH` : "На момент сохранения курс отсутствовал"}</p><a href="${ratesSource}" target="_blank" rel="noopener noreferrer">Источник ExchangeRate-API</a>`;
  element<HTMLDialogElement>("details-dialog").showModal();
});
document
  .querySelectorAll<HTMLElement>("[data-close]")
  .forEach((button) =>
    button.addEventListener("click", () =>
      element<HTMLDialogElement>(button.dataset.close!).close(),
    ),
  );
element("clear-history").addEventListener("click", () =>
  element<HTMLDialogElement>("clear-dialog").showModal(),
);
element("confirm-clear").addEventListener("click", async () => {
  const button = element<HTMLButtonElement>("confirm-clear");
  button.disabled = true;
  try {
    await writeQueue;
    await clearHistory();
    entries.clear();
    element<HTMLDialogElement>("clear-dialog").close();
    await renderHistory();
  } catch {
    notify("Не удалось очистить историю. Повторите");
  } finally {
    button.disabled = false;
  }
});

function renderConnection(): void {
  const offline = !navigator.onLine;
  element("connection").classList.toggle("offline", offline);
  element("connection").querySelector("span")!.textContent = offline
    ? "Без сети"
    : offlineReady
      ? "Готово офлайн"
      : offlineError
        ? "Офлайн-кэш недоступен"
        : "Готовим офлайн";
  element("offline-details").textContent = offlineReady
    ? "Приложение и OCR сохранены. Сканер работает без сети, пересчёт использует загруженные курсы."
    : offlineError
      ? "Не удалось подготовить офлайн-кэш. Освободите место и перезагрузите страницу с интернетом."
      : "Готовим приложение и распознавание для работы без сети. Оставьте страницу открытой до завершения.";
}
async function registerOffline(): Promise<void> {
  if (!("serviceWorker" in navigator) || import.meta.env.DEV) {
    offlineError = true;
    renderConnection();
    return;
  }
  try {
    registration = await navigator.serviceWorker.register(
      new URL("sw.js", new URL(import.meta.env.BASE_URL, location.href)),
      { scope: import.meta.env.BASE_URL },
    );
    const observe = (worker: ServiceWorker) =>
      worker.addEventListener("statechange", () => {
        if (worker.state === "redundant") {
          offlineError = true;
          renderConnection();
        }
        if (worker.state === "installed" && navigator.serviceWorker.controller)
          element("update-bar").hidden = false;
      });
    if (registration.installing) observe(registration.installing);
    registration.addEventListener("updatefound", () => {
      if (registration?.installing) observe(registration.installing);
    });
    if (registration.waiting) element("update-bar").hidden = false;
    await navigator.serviceWorker.ready;
    offlineReady = true;
    renderConnection();
  } catch {
    offlineError = true;
    renderConnection();
  }
}
element("update").addEventListener("click", () => {
  stopCamera();
  void Promise.all([writeQueue, preferenceQueue]).then(() =>
    registration?.waiting?.postMessage("SKIP_WAITING"),
  );
});
let hadController = !!navigator.serviceWorker?.controller;
navigator.serviceWorker?.addEventListener("controllerchange", () => {
  if (hadController) location.reload();
  hadController = true;
});
interface InstallPrompt extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: string }>;
}
let installPrompt: InstallPrompt | undefined;
window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  installPrompt = event as InstallPrompt;
  element("install").hidden = false;
});
element("install").addEventListener("click", async () => {
  if (!installPrompt) return;
  await installPrompt.prompt();
  await installPrompt.userChoice;
  installPrompt = undefined;
  element("install").hidden = true;
});
window.addEventListener("hashchange", navigate);
window.addEventListener("online", () => {
  renderConnection();
  renderRates();
  void refreshRates();
});
window.addEventListener("offline", () => {
  renderConnection();
  renderRates();
});
document.addEventListener("visibilitychange", () => {
  if (document.hidden) {
    resumeAfterDialog = false;
    stopCamera();
  } else {
    renderRates();
    void refreshRates();
  }
});
window.addEventListener("pagehide", () => {
  stopCamera();
  void ocr.terminate();
});
window.setInterval(() => {
  if (running && tracker.expire()) renderResult();
}, 300);

renderResult();
renderPreferences();
renderConnection();
navigate();
void registerOffline();
void (async () => {
  try {
    const saved = await Promise.all([
      readPreferences(),
      readRates(),
      readAttempt(),
    ]);
    preferences = saved[0];
    rates = saved[1] ?? null;
    lastAttempt = saved[2] ?? 0;
    renderPreferences();
    renderRates();
    renderResult();
  } catch {
    notify(
      "Хранилище браузера недоступно. История и настройки могут не сохраниться",
    );
  }
  void refreshRates();
})();
