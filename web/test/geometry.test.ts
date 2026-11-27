// Cases ported from the Swift tests:
//   GazeShiftCore/Tests/GazeShiftCoreTests/ScreenTouchTraceTests.swift
//   GazeShiftCore/Tests/GazeShiftCoreTests/PlacementTests.swift
//   GazeShiftFlow/Tests/GazeShiftFlowTests/ScreenFixedTests.swift
import { describe, expect, it } from 'vitest';
import {
  closureRadius, coverCrop, Defaults, fitTrace, planComposition, planPlacement, type Ellipse, type Point,
} from '../src/geometry';

// ScreenTouchTraceTests geometry: 400 × 300; diagonal 500 → closure radius 15.
const touchView = { width: 400, height: 300 };
// Same 24-step circle as the Swift fixtures: center (120, 140), radii (30, 20); point 24 returns to point 0.
const circle = (i: number): Point => {
  const a = ((i % 24) * 2 * Math.PI) / 24;
  return { x: 120 + 30 * Math.cos(a), y: 140 + 20 * Math.sin(a) };
};
const closedCircle = () => Array.from({ length: 25 }, (_, i) => circle(i));

describe('fitTrace (AirTraceSession.finishCandidate)', () => {
  it('fits the min/max bounding ellipse of a closed loop', () => {
    const result = fitTrace(closedCircle(), touchView);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.ellipse.center.x).toBeCloseTo(120, 9);
    expect(result.ellipse.center.y).toBeCloseTo(140, 9);
    expect(result.ellipse.radii.x).toBeCloseTo(30, 9);
    expect(result.ellipse.radii.y).toBeCloseTo(20, 9);
  });

  // testFinishRejectsEmptyShortOpenAndClosedCollinearTouch
  it.each([
    ['empty', [] as Point[], 'insufficientSamples'],
    ['19 points', Array.from({ length: 19 }, (_, i) => circle(i)), 'insufficientSamples'],
    ['open diagonal', Array.from({ length: 25 }, (_, i) => ({ x: 50 + i, y: 50 + i })), 'openStroke'],
    ['closed collinear out-and-back', Array.from({ length: 25 }, (_, i) => ({ x: 50 + (i % 24), y: 50 + (i % 24) })), 'degenerateStroke'],
  ])('rejects %s', (_name, trace, reason) => {
    expect(fitTrace(trace, touchView)).toEqual({ ok: false, reason });
  });

  it('counts distinct points, not samples (repeats do not reach 20)', () => {
    const repeated = Array.from({ length: 40 }, (_, i) => circle(i % 10));
    expect(fitTrace(repeated, touchView)).toEqual({ ok: false, reason: 'insufficientSamples' });
  });

  it('rejects a flat stroke as degenerate before checking closure', () => {
    const flat = Array.from({ length: 24 }, (_, i) => ({ x: 80 + i, y: 140 }));
    flat.push({ x: 80, y: 140 });
    expect(fitTrace(flat, touchView)).toEqual({ ok: false, reason: 'degenerateStroke' });
  });

  it('uses 0.03 × viewport diagonal as the closure radius', () => {
    expect(closureRadius(touchView)).toBeCloseTo(15, 9);
    const nearlyClosed = [...closedCircle().slice(0, 24), { x: 150 - 14.9, y: 140 }];
    expect(fitTrace(nearlyClosed, touchView).ok).toBe(true);
    const justOpen = [...closedCircle().slice(0, 24), { x: 150 - 15.1, y: 140 }];
    expect(fitTrace(justOpen, touchView)).toEqual({ ok: false, reason: 'openStroke' });
  });
});

// Placement fixtures: 300 × 400 view, region ellipse center (120, 140), radii (30, 20).
const view = { width: 300, height: 400 };
const fullBounds = { x: 0, y: 0, width: 300, height: 400 };
const region: Ellipse = { center: { x: 120, y: 140 }, radii: { x: 30, y: 20 } };

describe('planPlacement (PlacementPlanner.planScreenFixed)', () => {
  // ScreenFixedTests.fixedCopyUsesOriginalBoundsWithoutGazeMargin
  it('copies the enclosing rectangle to the chosen offset with zero extra gap', () => {
    const r = planPlacement(region, view, { x: 100, y: 150 }, fullBounds);
    expect(r).toEqual({
      ok: true,
      source: { x: 90, y: 120, width: 60, height: 40 },
      destination: { x: 190, y: 270, width: 60, height: 40 },
      gap: Defaults.screenFixedSafetyGapPoints,
    });
  });

  it('rejects edge-touching overlap and accepts one pixel of clearance', () => {
    expect(planPlacement(region, view, { x: 60, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'destinationOverlapsRegion' });
    expect(planPlacement(region, view, { x: 0, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'destinationOverlapsRegion' });
    const ok = planPlacement(region, view, { x: 61, y: 0 }, fullBounds);
    expect(ok.ok && ok.destination.x).toBe(151);
  });

  it('rejects an off-screen destination without clamping', () => {
    expect(planPlacement(region, view, { x: 300, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'destinationOutsideBounds' });
  });

  // PlacementTests.testOverlapAndP90GapRejectWithoutSearchingForAnotherOffset (gap = 10)
  it('honors an explicit safety gap (gaze-era p90 margin case)', () => {
    expect(planPlacement(region, view, { x: 65, y: 0 }, fullBounds, 10)).toEqual({ ok: false, reason: 'destinationOverlapsRegion' });
    expect(planPlacement(region, view, { x: 70, y: 0 }, fullBounds, 10)).toEqual({ ok: false, reason: 'destinationOverlapsRegion' });
    const ok = planPlacement(region, view, { x: 71, y: 0 }, fullBounds, 10);
    expect(ok.ok && ok.destination.x).toBe(161);
  });

  // PlacementTests.testRejectsSourceAndDestinationOutsideViewportAndSamplingBounds
  it('rejects sources and destinations outside the viewport or camera sampling bounds', () => {
    const nearLeftEdge: Ellipse = { center: { x: 10, y: 130 }, radii: { x: 30, y: 20 } };
    expect(planPlacement(nearLeftEdge, view, { x: 130, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'sourceOutsideBounds' });
    expect(planPlacement(region, view, { x: 200, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'destinationOutsideBounds' });
    expect(planPlacement(region, view, { x: 130, y: 0 }, { x: 100, y: 0, width: 200, height: 400 })).toEqual({ ok: false, reason: 'sourceOutsideBounds' });
    expect(planPlacement(region, view, { x: 130, y: 0 }, { x: 0, y: 0, width: 250, height: 400 })).toEqual({ ok: false, reason: 'destinationOutsideBounds' });
    expect(planPlacement(region, view, { x: 130, y: 0 }, { x: NaN, y: 0, width: 300, height: 400 })).toEqual({ ok: false, reason: 'invalidSamplingBounds' });
    expect(planPlacement(region, view, { x: 130, y: 0 }, { x: 0, y: 0, width: 0, height: 400 })).toEqual({ ok: false, reason: 'invalidSamplingBounds' });
    expect(planPlacement(region, view, { x: 130, y: 0 }, null)).toEqual({ ok: false, reason: 'invalidSamplingBounds' });
  });

  it('rejects a non-finite offset', () => {
    expect(planPlacement(region, view, { x: Infinity, y: 0 }, fullBounds)).toEqual({ ok: false, reason: 'invalidOffset' });
  });
});

describe('planComposition (CompositionPlanner.planScreenFixed)', () => {
  const plan = (mode: Parameters<typeof planComposition>[0], healthy = true, offset = { x: 100, y: 150 }) =>
    planComposition(mode, region, healthy, view, offset, fullBounds);

  // ScreenFixedTests.comparisonsUseIdenticalFixedRegionAndClearOnSourceLoss
  it('uses the identical fixed region for both blur modes; Original adds nothing', () => {
    expect(plan('original').copy).toBeNull();
    expect(plan('original').blur).toBeNull();
    expect(plan('simulatedBlur').copy).toBeNull();
    expect(plan('simulatedBlur').blur).toEqual(plan('simulatedBlurPlusCopy').blur);
    expect(plan('simulatedBlurPlusCopy').copy?.destination).toEqual({ x: 190, y: 270, width: 60, height: 40 });
  });

  it('clears every layer when the camera source is unavailable', () => {
    for (const mode of ['original', 'simulatedBlur', 'simulatedBlurPlusCopy'] as const) {
      const p = plan(mode, false);
      expect(p.copy).toBeNull();
      expect(p.blur).toBeNull();
      expect(p.statusText).toBe('Scene unavailable');
    }
  });

  it('shows a visible placement error and falls back to the original view', () => {
    const p = plan('simulatedBlurPlusCopy', true, { x: 60, y: 0 });
    expect(p.copy).toBeNull();
    expect(p.blur).toBeNull();
    expect(p.statusText).toBe('No valid placement — original view');
    expect(p.placementError).toMatch(/overlaps/);
  });

  it('needs a reviewed region before adding layers', () => {
    expect(planComposition('simulatedBlur', null, true, view, { x: 0, y: 0 }, fullBounds).statusText)
      .toBe('No reviewed region — original view');
  });
});

describe('coverCrop', () => {
  it('crops the wider source to fill a taller viewport', () => {
    expect(coverCrop(1280, 720, { width: 360, height: 480 })).toEqual({ x: 370, y: 0, width: 540, height: 720 });
  });
  it('crops the taller source to fill a wider viewport', () => {
    const c = coverCrop(720, 1280, { width: 640, height: 480 });
    expect(c.x).toBe(0);
    expect(c.width).toBe(720);
    expect(c.height).toBeCloseTo(540, 9);
  });
});
