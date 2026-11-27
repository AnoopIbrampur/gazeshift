// Stretch goal placeholder: index-fingertip air drawing (MediaPipe HandLandmarker) is added later.
import type { Point, Viewport } from './geometry';

export type HandSample = { kind: 'point'; x: number; y: number } | { kind: 'lost' } | { kind: 'none' };

export class HandDrawing {
  async load(): Promise<boolean> { return false; }
  reset(): void {}
  detect(_frame: HTMLCanvasElement, _now: number): HandSample { return { kind: 'none' }; }
  lastTip(_view: Viewport): Point | null { return null; }
  lastInferenceMs(): number { return 0; }
}
