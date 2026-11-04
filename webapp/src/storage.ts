import {
  defaultPreferences,
  type HistoryEntry,
  type Preferences,
  type Rates,
} from "./domain.ts";

const dbName = `pricelens:${new URL(import.meta.env.BASE_URL, location.href).pathname}`;
let connection: Promise<IDBDatabase> | undefined;
function database(): Promise<IDBDatabase> {
  connection ??= new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore("state");
      const history = request.result.createObjectStore("history", {
        keyPath: "id",
      });
      history.createIndex("createdAt", "createdAt");
    };
    request.onsuccess = () => {
      const db = request.result;
      db.onversionchange = () => {
        db.close();
        connection = undefined;
      };
      resolve(db);
    };
    request.onerror = () => {
      connection = undefined;
      reject(request.error);
    };
    request.onblocked = () => {
      connection = undefined;
      reject(new Error("Закройте другую вкладку PriceLens и повторите"));
    };
  });
  return connection;
}

async function readState<T>(key: string): Promise<T | undefined> {
  const db = await database();
  return new Promise((resolve, reject) => {
    const request = db.transaction("state").objectStore("state").get(key);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}
export async function writeState(key: string, value: unknown): Promise<void> {
  const db = await database();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("state", "readwrite");
    transaction.objectStore("state").put(value, key);
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error);
    transaction.onerror = () => reject(transaction.error);
  });
}
export const readRates = () => readState<Rates>("rates");
export const readAttempt = () => readState<number>("rateAttempt");
export async function readPreferences(): Promise<Preferences> {
  return (
    (await readState<Preferences>("preferences")) ??
    structuredClone(defaultPreferences)
  );
}
export async function listHistory(): Promise<HistoryEntry[]> {
  const db = await database();
  return new Promise((resolve, reject) => {
    const request = db
      .transaction("history")
      .objectStore("history")
      .index("createdAt")
      .getAll();
    request.onsuccess = () =>
      resolve((request.result as HistoryEntry[]).reverse());
    request.onerror = () => reject(request.error);
  });
}
export async function saveEntry(entry: HistoryEntry): Promise<void> {
  const db = await database();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("history", "readwrite");
    const store = transaction.objectStore("history");
    store.put(entry);
    let count = 0;
    const cursor = store.index("createdAt").openCursor(null, "prev");
    cursor.onsuccess = () => {
      const row = cursor.result;
      if (!row) return;
      if (++count > 100) row.delete();
      row.continue();
    };
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error);
    transaction.onerror = () => reject(transaction.error);
  });
}
export async function clearHistory(): Promise<void> {
  const db = await database();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("history", "readwrite");
    transaction.objectStore("history").clear();
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error);
    transaction.onerror = () => reject(transaction.error);
  });
}
