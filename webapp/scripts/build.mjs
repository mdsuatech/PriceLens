import "./prepare.mjs";
import { build } from "vite";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import path from "node:path";

await build();
const dist = fileURLToPath(new URL("../dist/", import.meta.url));
async function walk(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const name = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(name)));
    else files.push(name);
  }
  return files;
}
const files = (await walk(dist)).sort();
const digest = createHash("sha256");
for (const file of files)
  digest.update(path.relative(dist, file)).update(await readFile(file));
const assets = files.map(
  (file) => "./" + path.relative(dist, file).replaceAll("\\", "/"),
);
const version = digest.digest("hex").slice(0, 16);
const worker = `
const PREFIX = 'pricelens:' + self.registration.scope + ':';
const CACHE = PREFIX + '${version}';
const ASSETS = ${JSON.stringify(assets)};
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)));
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(PREFIX) && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || !url.href.startsWith(self.registration.scope)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (event.request.mode === 'navigate') {
      return await cache.match(new URL('./index.html', self.registration.scope)) || fetch(event.request);
    }
    return await cache.match(event.request, { ignoreSearch: true, ignoreVary: true }) || fetch(event.request);
  })());
});
`;
await writeFile(path.join(dist, "sw.js"), worker.trim());
await writeFile(path.join(dist, ".nojekyll"), "");
console.log(
  `Offline bundle ${version}, ${assets.length} files. OCR assets are hosted with the application.`,
);
