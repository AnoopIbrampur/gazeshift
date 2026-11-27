// Faithful TypeScript port of the screen-fixed geometry in the iOS app:
//   GazeShiftCore/Sources/GazeShiftCore/AirTrace.swift  (AirTraceSession.finishCandidate)
//   GazeShiftCore/Sources/GazeShiftCore/Placement.swift (PlacementPlanner.planScreenFixed)
//   GazeShiftFlow/Sources/GazeShiftFlow/Composition.swift (CompositionPlanner.planScreenFixed)
// Check order and constants match the Swift code, because tests assert which check fails first.
// All values are viewport (CSS) pixels with a top-left origin, never raw camera pixels.

export interface Point { x: number; y: number }
export interface Rect { x: number; y: number; width: number; height: number }
export interface Viewport { width: number; height: number }
export interface Ellipse { center: Point; radii: Point }

export const Defaults = {
  /** AirTraceDefaults.closureRadiusDiagonalFraction */
  closureRadiusDiagonalFraction: 0.03,
  /** AirTraceDefaults.minimumDistinctSamples */
  minimumDistinctSamples: 20,
  /** AirTraceDefaults.minimumTouchAreaBoundingFraction (numerical degeneracy guard) */
  minimumTouchAreaBoundingFraction: 1e-6,
  /** AirTraceDefaults.maximumSampleAgeSeconds, used for camera-source freshness */
  maximumSampleAgeSeconds: 0.25,
  /** PlacementDefaults.screenFixedSafetyGapPoints: zero extra clearance; bounds and overlap still apply */
  screenFixedSafetyGapPoints: 0,
} as const;

export type TraceRejection = 'insufficientSamples' | 'degenerateStroke' | 'openStroke';
export type TraceResult =
  | { ok: true; ellipse: Ellipse }
  | { ok: false; reason: TraceRejection };

export const diagonal = (v: Viewport): number => Math.hypot(v.width, v.height);

/** Radius around the start point that counts as "returned to start". */
export const closureRadius = (v: Viewport): number => Defaults.closureRadiusDiagonalFraction * diagonal(v);

/**
 * Port of AirTraceSession.finishCandidate() for the screen-touch path:
 * distinct points → non-zero bounds → closure → enclosed area → min/max bounding ellipse.
 */
export function fitTrace(trace: readonly Point[], viewport: Viewport): TraceResult {
  const distinct: Point[] = [];
  for (const p of trace) {
    if (!distinct.some((d) => d.x === p.x && d.y === p.y)) distinct.push(p);
  }
  if (distinct.length < Defaults.minimumDistinctSamples) return { ok: false, reason: 'insufficientSamples' };

  const xs = trace.map((p) => p.x);
  const ys = trace.map((p) => p.y);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minY = Math.min(...ys), maxY = Math.max(...ys);
  if (!(maxX > minX && maxY > minY)) return { ok: false, reason: 'degenerateStroke' };

  const first = trace[0];
  const last = trace[trace.length - 1];
  if (Math.hypot(last.x - first.x, last.y - first.y) > closureRadius(viewport)) {
    return { ok: false, reason: 'openStroke' };
  }

  // Shoelace area in viewport-normalized units, relative to the first point (screen-touch path).
  let twiceArea = 0;
  let previous = first;
  for (const point of trace.slice(1)) {
    twiceArea += ((previous.x - first.x) / viewport.width) * ((point.y - first.y) / viewport.height)
      - ((point.x - first.x) / viewport.width) * ((previous.y - first.y) / viewport.height);
    previous = point;
  }
  const boundingArea = ((maxX - minX) / viewport.width) * ((maxY - minY) / viewport.height);
  if (!(Math.abs(twiceArea) / 2 > boundingArea * Defaults.minimumTouchAreaBoundingFraction)) {
    return { ok: false, reason: 'degenerateStroke' };
  }

  return {
    ok: true,
    ellipse: {
      center: { x: minX + (maxX - minX) / 2, y: minY + (maxY - minY) / 2 },
      radii: { x: (maxX - minX) / 2, y: (maxY - minY) / 2 },
    },
  };
}

export type PlacementRejection =
  | 'invalidOffset' | 'invalidSamplingBounds' | 'sourceOutsideBounds'
  | 'destinationOutsideBounds' | 'destinationOverlapsRegion';
export type PlacementResult =
  | { ok: true; source: Rect; destination: Rect; gap: number }
  | { ok: false; reason: PlacementRejection };

const finite = (n: number) => Number.isFinite(n);

function validRectangle(r: Rect): boolean {
  return finite(r.x) && finite(r.y) && finite(r.width) && finite(r.height)
    && r.width > 0 && r.height > 0 && finite(r.x + r.width) && finite(r.y + r.height);
}

function contains(outer: Rect, inner: Rect): boolean {
  return validRectangle(inner) && inner.x >= outer.x && inner.y >= outer.y
    && inner.x + inner.width <= outer.x + outer.width
    && inner.y + inner.height <= outer.y + outer.height;
}

/** Closed intervals: edge-touching counts as overlap (conservative, as in the Swift code). */
function overlapsExpandedSource(d: Rect, s: Rect, gap: number): boolean {
  return d.x <= s.x + s.width + gap && d.x + d.width >= s.x - gap
    && d.y <= s.y + s.height + gap && d.y + d.height >= s.y - gap;
}

/** The enclosing rectangle of the ellipse; this is what gets copied. */
export const ellipseBounds = (e: Ellipse): Rect => ({
  x: e.center.x - e.radii.x, y: e.center.y - e.radii.y, width: 2 * e.radii.x, height: 2 * e.radii.y,
});

/**
 * Port of PlacementPlanner.planScreenFixed: no clamping, shrinking or searching for another offset.
 * `samplingBounds` is the valid camera image extent in the same viewport coordinates.
 */
export function planPlacement(ellipse: Ellipse, viewport: Viewport, offset: Point,
                              samplingBounds: Rect | null,
                              gap: number = Defaults.screenFixedSafetyGapPoints): PlacementResult {
  if (!finite(offset.x) || !finite(offset.y)) return { ok: false, reason: 'invalidOffset' };
  if (!samplingBounds || !validRectangle(samplingBounds)) return { ok: false, reason: 'invalidSamplingBounds' };
  const source = ellipseBounds(ellipse);
  const destination = { x: source.x + offset.x, y: source.y + offset.y, width: source.width, height: source.height };
  const view = { x: 0, y: 0, width: viewport.width, height: viewport.height };
  if (!contains(view, source) || !contains(samplingBounds, source)) return { ok: false, reason: 'sourceOutsideBounds' };
  if (!contains(view, destination) || !contains(samplingBounds, destination)) {
    return { ok: false, reason: 'destinationOutsideBounds' };
  }
  if (overlapsExpandedSource(destination, source, gap)) return { ok: false, reason: 'destinationOverlapsRegion' };
  return { ok: true, source, destination, gap };
}

export const placementMessage: Record<PlacementRejection, string> = {
  invalidOffset: 'Invalid offset',
  invalidSamplingBounds: 'Camera image bounds unavailable',
  sourceOutsideBounds: 'Region extends past the camera image',
  destinationOutsideBounds: 'Copy would go off-screen — move it back',
  destinationOverlapsRegion: 'Copy overlaps the region — move it further away',
};

export type ComparisonMode = 'original' | 'simulatedBlur' | 'simulatedBlurPlusCopy';
export interface CompositionPlan {
  copy: { source: Rect; destination: Rect } | null;
  blur: Ellipse | null;
  statusText: string;
  /** Detailed reason when a placement was rejected (shown as a visible error). */
  placementError: string | null;
}

export const SIMULATION_LABEL = 'Simulated blur — demonstration only';

/** Port of CompositionPlanner.planScreenFixed for the three comparison modes. */
export function planComposition(mode: ComparisonMode, ellipse: Ellipse | null, sourceAvailable: boolean,
                                viewport: Viewport, offset: Point, samplingBounds: Rect | null): CompositionPlan {
  const originalOnly = (statusText: string, placementError: string | null = null): CompositionPlan =>
    ({ copy: null, blur: null, statusText, placementError });
  if (!sourceAvailable) return originalOnly('Scene unavailable');
  if (mode === 'original') return originalOnly('Original');
  if (!ellipse) return originalOnly('No reviewed region — original view');
  if (mode === 'simulatedBlur') {
    return { copy: null, blur: ellipse, statusText: 'Screen-fixed simulated blur', placementError: null };
  }
  const result = planPlacement(ellipse, viewport, offset, samplingBounds);
  if (!result.ok) return originalOnly('No valid placement — original view', placementMessage[result.reason]);
  return {
    copy: { source: result.source, destination: result.destination },
    blur: ellipse,
    statusText: 'Screen-fixed simulated blur + copy',
    placementError: null,
  };
}

/**
 * Object-fit "cover" mapping of a source frame into the viewport. Returns the source crop that fills
 * the viewport; the full viewport is then valid sampling bounds.
 */
export function coverCrop(srcW: number, srcH: number, view: Viewport): Rect {
  const scale = Math.max(view.width / srcW, view.height / srcH);
  const w = view.width / scale, h = view.height / scale;
  return { x: (srcW - w) / 2, y: (srcH - h) / 2, width: w, height: h };
}
