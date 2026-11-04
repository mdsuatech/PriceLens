import { mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = fileURLToPath(new URL("../", import.meta.url));
const target = path.join(root, "public/ocr");
await mkdir(target, { recursive: true });
const assets = [
  ["tesseract.js/dist/worker.min.js", "worker.min.js"],
  [
    "@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz",
    "eng.traineddata.gz",
  ],
  ["tesseract.js/LICENSE.md", "LICENSE.tesseract.txt"],
  ["tesseract.js-core/LICENSE", "LICENSE.core.txt"],
  ...["lstm", "simd-lstm", "relaxedsimd-lstm"].map((variant) => [
    `tesseract.js-core/tesseract-core-${variant}.wasm.js`,
    `tesseract-core-${variant}.wasm.js`,
  ]),
];
for (const [source, name] of assets)
  await copyFile(
    path.join(root, "node_modules", source),
    path.join(target, name),
  );
