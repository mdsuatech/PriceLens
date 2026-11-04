import { createWorker, OEM, PSM, type Worker } from "tesseract.js";
import type { Bounds, OcrLine } from "./domain.ts";

export class LocalOcr {
  private worker?: Promise<Worker>;
  constructor(private progress: (message: string) => void) {}
  private async load(): Promise<Worker> {
    const base = new URL(
      "ocr/",
      new URL(import.meta.env.BASE_URL, location.href),
    ).href;
    this.progress("Подготавливаем распознавание…");
    let worker: Worker | undefined;
    try {
      worker = await createWorker("eng", OEM.LSTM_ONLY, {
        workerPath: base + "worker.min.js",
        corePath: base,
        langPath: base,
        workerBlobURL: false,
        cacheMethod: "none",
      });
      await worker.setParameters({
        tessedit_pageseg_mode: PSM.SPARSE_TEXT,
        preserve_interword_spaces: "1",
      });
      return worker;
    } catch (error) {
      if (worker) await worker.terminate();
      throw error;
    }
  }
  async recognize(image: HTMLCanvasElement): Promise<OcrLine[]> {
    this.worker ??= this.load();
    try {
      const worker = await this.worker;
      this.progress("Считываем ценник…");
      const { data } = await worker.recognize(
        image,
        {},
        { text: true, blocks: true },
      );
      return (data.blocks ?? []).flatMap((block) =>
        block.paragraphs.flatMap((paragraph) =>
          paragraph.lines.map((line) => ({
            text: line.text,
            bounds: {
              x: line.bbox.x0 / image.width,
              y: line.bbox.y0 / image.height,
              width: (line.bbox.x1 - line.bbox.x0) / image.width,
              height: (line.bbox.y1 - line.bbox.y0) / image.height,
            },
          })),
        ),
      );
    } catch (error) {
      await this.terminate();
      throw error;
    }
  }
  async terminate(): Promise<void> {
    const pending = this.worker;
    this.worker = undefined;
    if (pending) {
      try {
        await (await pending).terminate();
      } catch {
        /* Initialization may already have failed. */
      }
    }
  }
}

type TorchCapabilities = MediaTrackCapabilities & { torch?: boolean };
export class Camera {
  private stream?: MediaStream;
  private generation = 0;
  facing: "environment" | "user" = "environment";
  torch = false;
  constructor(
    readonly video: HTMLVideoElement,
    readonly viewport: HTMLElement,
  ) {}
  get active(): boolean {
    return !!this.stream;
  }
  get supportsTorch(): boolean {
    return !!(
      this.stream?.getVideoTracks()[0]?.getCapabilities?.() as
        | TorchCapabilities
        | undefined
    )?.torch;
  }
  async start(): Promise<boolean> {
    this.stop();
    const generation = this.generation;
    if (!navigator.mediaDevices?.getUserMedia)
      throw new Error(
        "Камера доступна по HTTPS или на localhost. Можно загрузить фото или ввести цену",
      );
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        facingMode: { ideal: this.facing },
        width: { ideal: 1920 },
        height: { ideal: 1080 },
      },
    });
    if (generation !== this.generation) {
      stream.getTracks().forEach((track) => track.stop());
      return false;
    }
    this.stream = stream;
    this.video.srcObject = stream;
    try {
      await this.video.play();
    } catch (error) {
      this.stop();
      throw error;
    }
    return generation === this.generation;
  }
  stop(): void {
    this.generation++;
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = undefined;
    this.video.srcObject = null;
    this.torch = false;
  }
  async toggleTorch(): Promise<void> {
    const track = this.stream?.getVideoTracks()[0];
    if (!track || !this.supportsTorch) return;
    await track.applyConstraints({
      advanced: [{ torch: !this.torch } as MediaTrackConstraintSet],
    });
    this.torch = !this.torch;
  }
  capture(): HTMLCanvasElement {
    const canvas = document.createElement("canvas");
    const sourceWidth = this.video.videoWidth;
    const sourceHeight = this.video.videoHeight;
    if (!sourceWidth || !sourceHeight)
      throw new Error("Камера ещё не передала изображение");
    const aspect = this.viewport.clientWidth / this.viewport.clientHeight;
    const width = Math.min(sourceWidth, sourceHeight * aspect);
    const height = width / aspect;
    canvas.width = Math.min(1400, Math.round(width * 0.82));
    canvas.height = Math.max(
      1,
      Math.round(canvas.width / ((aspect * 0.82) / 0.5)),
    );
    // Match object-fit: cover, then crop the visible guide (82% × 50%).
    const x = (sourceWidth - width) / 2 + width * 0.09;
    const y = (sourceHeight - height) / 2 + height * 0.22;
    canvas
      .getContext("2d")!
      .drawImage(
        this.video,
        x,
        y,
        width * 0.82,
        height * 0.5,
        0,
        0,
        canvas.width,
        canvas.height,
      );
    return canvas;
  }
}

export async function photoCanvas(file: File): Promise<HTMLCanvasElement> {
  if (!file.type.startsWith("image/"))
    throw new Error("Выберите изображение ценника");
  const image = new Image();
  const url = URL.createObjectURL(file);
  try {
    image.src = url;
    await image.decode();
    const scale = Math.min(
      1,
      1800 / Math.max(image.naturalWidth, image.naturalHeight),
    );
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    canvas
      .getContext("2d")!
      .drawImage(image, 0, 0, canvas.width, canvas.height);
    return canvas;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function drawBounds(element: HTMLElement, bounds?: Bounds): void {
  element.hidden = !bounds;
  if (!bounds) return;
  element.style.left = `${bounds.x * 100}%`;
  element.style.top = `${bounds.y * 100}%`;
  element.style.width = `${bounds.width * 100}%`;
  element.style.height = `${bounds.height * 100}%`;
}
