// Air drawing: MediaPipe HandLandmarker tracks the index fingertip (landmark 8) on the displayed frame.
// The WASM runtime and model are bundled under public/mediapipe, so nothing loads from a third-party CDN.
// Detection runs on the already mirrored, cover-cropped frame, so landmark coordinates (0..1) map
// straight onto the viewport with no extra flip.
import type { HandLandmarker as HandLandmarkerType } from '@mediapipe/tasks-vision';
import type { Point, Viewport } from './geometry';

export type HandSample = { kind: 'point'; x: number; y: number } | { kind: 'lost' } | { kind: 'none' };

const INDEX_TIP = 8;
/** How long the fingertip may vanish before an in-progress stroke is cleared. */
const LOST_AFTER_MS = 500;
/** Detection input width; smaller is faster and plenty for one fingertip. */
const DETECT_WIDTH = 480;
/** Exponential smoothing of the fingertip (0 = frozen, 1 = raw). */
const SMOOTHING = 0.5;

export class HandDrawing {
  private landmarker: HandLandmarkerType | null = null;
  private loading: Promise<boolean> | null = null;
  private readonly input = document.createElement('canvas');
  private readonly inputCtx = this.input.getContext('2d')!;
  private tip: Point | null = null; // normalized 0..1
  private lastSeen = 0;
  private lastTs = 0;
  private inferenceMs = 0;

  load(): Promise<boolean> {
    if (this.landmarker) return Promise.resolve(true);
    this.loading ??= this.create().catch((err) => { console.error('Hand tracker failed', err); this.loading = null; return false; });
    return this.loading;
  }

  private async create(): Promise<boolean> {
    const { FilesetResolver, HandLandmarker } = await import('@mediapipe/tasks-vision');
    const base = `${import.meta.env.BASE_URL}mediapipe`;
    const fileset = await FilesetResolver.forVisionTasks(base);
    const options = (delegate: 'GPU' | 'CPU') => ({
      baseOptions: { modelAssetPath: `${base}/hand_landmarker.task`, delegate },
      runningMode: 'VIDEO' as const,
      numHands: 1,
      minHandDetectionConfidence: 0.5,
      minHandPresenceConfidence: 0.5,
      minTrackingConfidence: 0.5,
    });
    try {
      this.landmarker = await HandLandmarker.createFromOptions(fileset, options('GPU'));
    } catch {
      // Some browsers (older iOS Safari) lack the WebGL features the GPU delegate needs.
      this.landmarker = await HandLandmarker.createFromOptions(fileset, options('CPU'));
    }
    // Warm-up: the first inference compiles shaders and can take seconds; do it while "Loading…" shows,
    // not on the first live frame.
    const warm = document.createElement('canvas');
    warm.width = DETECT_WIDTH; warm.height = 270;
    warm.getContext('2d')!.fillRect(0, 0, warm.width, warm.height);
    this.lastTs = performance.now();
    this.landmarker.detectForVideo(warm, this.lastTs);
    return true;
  }

  reset(): void { this.tip = null; this.lastSeen = 0; }

  /** Runs one detection on the displayed frame. Call once per new camera frame. */
  detect(frame: HTMLCanvasElement, now: number): HandSample {
    if (!this.landmarker || !frame.width || !frame.height) return { kind: 'none' };
    const h = Math.max(1, Math.round(DETECT_WIDTH * frame.height / frame.width));
    if (this.input.width !== DETECT_WIDTH || this.input.height !== h) { this.input.width = DETECT_WIDTH; this.input.height = h; }
    this.inputCtx.drawImage(frame, 0, 0, DETECT_WIDTH, h);
    const ts = Math.max(now, this.lastTs + 1); // VIDEO mode needs strictly increasing timestamps
    this.lastTs = ts;
    const t0 = performance.now();
    const result = this.landmarker.detectForVideo(this.input, ts);
    this.inferenceMs = performance.now() - t0;
    const lm = result.landmarks?.[0]?.[INDEX_TIP];
    if (lm && lm.x >= 0 && lm.x <= 1 && lm.y >= 0 && lm.y <= 1) {
      this.tip = this.tip
        ? { x: this.tip.x + SMOOTHING * (lm.x - this.tip.x), y: this.tip.y + SMOOTHING * (lm.y - this.tip.y) }
        : { x: lm.x, y: lm.y };
      this.lastSeen = now;
      return { kind: 'point', x: this.tip.x, y: this.tip.y };
    }
    if (this.tip && now - this.lastSeen > LOST_AFTER_MS) { this.tip = null; return { kind: 'lost' }; }
    return { kind: 'none' };
  }

  lastTip(view: Viewport): Point | null {
    return this.tip ? { x: this.tip.x * view.width, y: this.tip.y * view.height } : null;
  }

  lastInferenceMs(): number { return this.inferenceMs; }
}
