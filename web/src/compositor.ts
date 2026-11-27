// Canvas 2D compositor mirroring the iOS Metal compositor's contract (CompositeShaders.metal):
//   1. sample the ORIGINAL current frame;
//   2. apply the copy, reading only original pixels;
//   3. apply the simulated blur LAST, clipped to the reviewed ellipse.
// Blur uses a downscale/upscale pass instead of ctx.filter, so it behaves the same in Chrome and
// iOS Safari (ctx.filter support varies) and stays cheap enough for a phone.

import { coverCrop, type CompositionPlan, type Rect, type Viewport } from './geometry';
import type { FrameSource } from './sources';

export class Compositor {
  /** Original frame at display resolution; the only canvas the copy ever reads from. */
  readonly original = document.createElement('canvas');
  private readonly originalCtx = this.original.getContext('2d', { alpha: false })!;
  private readonly small = document.createElement('canvas');
  private readonly smallCtx = this.small.getContext('2d')!;
  private readonly region = document.createElement('canvas');
  private readonly regionCtx = this.region.getContext('2d')!;

  constructor(private readonly out: HTMLCanvasElement) {}

  /** Backing-store size in device pixels for a viewport in CSS pixels. */
  resize(view: Viewport, dpr: number): void {
    const w = Math.max(1, Math.round(view.width * dpr));
    const h = Math.max(1, Math.round(view.height * dpr));
    for (const c of [this.out, this.original]) {
      if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    }
  }

  /** Draws the source into the original buffer with object-fit "cover", mirroring once if needed. */
  drawOriginal(source: FrameSource): boolean {
    const { width: sw, height: sh } = source.size();
    if (!sw || !sh) return false;
    const crop = coverCrop(sw, sh, { width: this.original.width, height: this.original.height });
    const ctx = this.originalCtx;
    ctx.save();
    if (source.mirrored) {
      ctx.translate(this.original.width, 0);
      ctx.scale(-1, 1);
    }
    ctx.drawImage(source.drawable(), crop.x, crop.y, crop.width, crop.height, 0, 0, this.original.width, this.original.height);
    ctx.restore();
    return true;
  }

  /** Composites one frame from the original buffer according to `plan` (CSS-pixel geometry). */
  composite(plan: CompositionPlan | null, dpr: number, blurStrength: number): void {
    const ctx = this.out.getContext('2d', { alpha: false })!;
    ctx.drawImage(this.original, 0, 0);
    if (!plan) return;
    if (plan.copy) {
      const s = scale(plan.copy.source, dpr);
      const d = scale(plan.copy.destination, dpr);
      // Reads from `original`, never from `out`, so the copy can't sample blurred or copied pixels.
      ctx.drawImage(this.original, s.x, s.y, s.width, s.height, d.x, d.y, d.width, d.height);
    }
    if (plan.blur) {
      const { center, radii } = plan.blur;
      const pad = 8;
      const box = scale({
        x: center.x - radii.x - pad, y: center.y - radii.y - pad,
        width: 2 * radii.x + 2 * pad, height: 2 * radii.y + 2 * pad,
      }, dpr);
      const bx = Math.max(0, Math.floor(box.x)), by = Math.max(0, Math.floor(box.y));
      const bw = Math.min(this.out.width - bx, Math.ceil(box.width));
      const bh = Math.min(this.out.height - by, Math.ceil(box.height));
      if (bw <= 0 || bh <= 0) return;
      // Snapshot the composited region (blur is last), shrink it, then scale it back up with smoothing.
      this.region.width = bw; this.region.height = bh;
      this.regionCtx.drawImage(this.out, bx, by, bw, bh, 0, 0, bw, bh);
      const factor = Math.max(4, blurStrength);
      const sw = Math.max(2, Math.round(bw / factor)), sh = Math.max(2, Math.round(bh / factor));
      this.small.width = sw; this.small.height = sh;
      this.smallCtx.imageSmoothingEnabled = true;
      this.smallCtx.imageSmoothingQuality = 'high';
      this.smallCtx.drawImage(this.region, 0, 0, sw, sh);
      ctx.save();
      ctx.beginPath();
      ctx.ellipse(center.x * dpr, center.y * dpr, radii.x * dpr, radii.y * dpr, 0, 0, Math.PI * 2);
      ctx.clip();
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(this.small, 0, 0, sw, sh, bx, by, bw, bh);
      // Opaque scotoma-style patch on top: solid in the middle, feathered at the rim.
      ctx.translate(center.x * dpr, center.y * dpr);
      ctx.scale(radii.x * dpr, radii.y * dpr);
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
      g.addColorStop(0, 'rgba(48,48,52,1)');
      g.addColorStop(0.7, 'rgba(48,48,52,1)');
      g.addColorStop(1, 'rgba(48,48,52,0.55)');
      ctx.fillStyle = g;
      ctx.fillRect(-1, -1, 2, 2);
      ctx.restore();
    }
  }
}

const scale = (r: Rect, k: number): Rect => ({ x: r.x * k, y: r.y * k, width: r.width * k, height: r.height * k });
