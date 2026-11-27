// Rolling frame-rate and per-frame processing time. Processing time is the JS/Canvas compose work
// for one frame (draw original → copy → blur). It is NOT end-to-end camera-to-display latency.
export class PerfMeter {
  private readonly frameTimes: number[] = [];
  private readonly costs: number[] = [];
  constructor(private readonly window = 60) {}

  record(frameAt: number, processingMs: number): void {
    this.frameTimes.push(frameAt);
    this.costs.push(processingMs);
    if (this.frameTimes.length > this.window) this.frameTimes.shift();
    if (this.costs.length > this.window) this.costs.shift();
  }

  fps(): number {
    const n = this.frameTimes.length;
    if (n < 2) return 0;
    const span = this.frameTimes[n - 1] - this.frameTimes[0];
    return span > 0 ? ((n - 1) * 1000) / span : 0;
  }

  meanMs(): number {
    return this.costs.length ? this.costs.reduce((a, b) => a + b, 0) / this.costs.length : 0;
  }

  p95Ms(): number {
    if (!this.costs.length) return 0;
    const sorted = [...this.costs].sort((a, b) => a - b);
    return sorted[Math.min(sorted.length - 1, Math.ceil(0.95 * sorted.length) - 1)];
  }
}
