import './style.css';
import { Compositor } from './compositor';
import {
  closureRadius, Defaults, fitTrace, planComposition, SIMULATION_LABEL,
  type ComparisonMode, type CompositionPlan, type Ellipse, type Point, type Viewport,
} from './geometry';
import { PerfMeter } from './perf';
import {
  CameraError, isContinuityCamera, listCameras, openCamera, openSampleScene,
  type CameraRequest, type Facing, type FrameSource,
} from './sources';
import { HandDrawing } from './handDrawing';

// ---------- DOM ----------
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const stage = $('stage');
const canvas = $<HTMLCanvasElement>('view');
const video = $<HTMLVideoElement>('video');
const perfEl = $('perf');
const sourceBadge = $('source-badge');
const startPanel = $('start-panel');
const errorPanel = $('error-panel');
const errorText = $('error-text');
const statusEl = $('status');
const placementErrorEl = $('placement-error');
const hintEl = $('hint');
const drawControls = $('draw-controls');
const reviewControls = $('review-controls');
const acceptedControls = $('accepted-controls');
const offsetReadout = $('offset-readout');
const simLabel = $('sim-label');
const modeButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('[data-mode]'));
const sourceButtons = Array.from(document.querySelectorAll<HTMLButtonElement>('[data-source]'));
const finishBtn = $<HTMLButtonElement>('finish-btn');
const airBtn = $<HTMLButtonElement>('air-btn');
const cameraSelect = $<HTMLSelectElement>('camera-select');

// ---------- State ----------
type Phase =
  | { kind: 'idle' }
  | { kind: 'armed'; startedAt: number }
  | { kind: 'tracing'; startedAt: number }
  | { kind: 'review'; ellipse: Ellipse }
  | { kind: 'accepted'; ellipse: Ellipse }
  | { kind: 'invalid'; reason: string };

const compositor = new Compositor(canvas);
const perf = new PerfMeter();
let source: FrameSource | null = null;
let currentFacing: Facing = 'user';
let lastRequest: CameraRequest = { facing: 'user' };
let autoPickedIPhone = false;
let viewport: Viewport = { width: 0, height: 0 };
let dpr = 1;
let phase: Phase = { kind: 'idle' };
let trace: Point[] = [];
let offset: Point = { x: 0, y: 0 };
let mode: ComparisonMode = 'simulatedBlur';
let lastPlan: CompositionPlan | null = null;
let lastProcessedFrame: number | null = null;
let airDrawing = false;
const hand = new HandDrawing();

const OFFSET_STEP = 16;
const BLUR_STRENGTH = 40; // downscale factor of the simulated blur (visual strength, not a vision model)

const rejectionText: Record<string, string> = {
  insufficientSamples: 'Too few points — draw a bigger loop (at least 20 distinct points).',
  openStroke: 'The loop didn’t return to the start dot. Finish inside the dashed ring.',
  degenerateStroke: 'The outline encloses no area. Draw a loop around something.',
  invalidTouch: 'The stroke left the camera view, so it was cleared.',
  stalePair: 'The camera feed paused, so the stroke was cleared.',
  geometryChanged: 'The view size changed, so the drawing was reset.',
  handLost: 'Index finger lost for too long — stroke cleared.',
};

// ---------- Layout ----------
function layout(): void {
  const width = Math.min(stage.parentElement!.clientWidth, 960);
  // Height comes from width only, so the iOS Safari toolbar collapsing never resizes the view.
  const aspect = window.matchMedia('(min-width: 700px)').matches ? 3 / 4 : 4 / 3;
  const next = { width: Math.round(width), height: Math.round(width * aspect) };
  const nextDpr = Math.min(window.devicePixelRatio || 1, 2);
  if (next.width === viewport.width && next.height === viewport.height && nextDpr === dpr) return;
  const hadDrawing = phase.kind !== 'idle' && phase.kind !== 'invalid';
  viewport = next;
  dpr = nextDpr;
  stage.style.width = `${viewport.width}px`;
  stage.style.height = `${viewport.height}px`;
  canvas.style.width = `${viewport.width}px`;
  canvas.style.height = `${viewport.height}px`;
  compositor.resize(viewport, dpr);
  // Same rule as iOS: a geometry change invalidates the screen-fixed stroke and region.
  if (hadDrawing) invalidate('geometryChanged');
}
window.addEventListener('resize', layout);

// ---------- Sources ----------
// Per-viewer convenience only: remember the chosen camera; the app works without storage.
const PREF_KEY = 'gazeshift.cameraId';
const savedCameraId = (): string | null => { try { return localStorage.getItem(PREF_KEY); } catch { return null; } };
const saveCameraId = (id: string) => { try { localStorage.setItem(PREF_KEY, id); } catch { /* storage unavailable */ } };

/** "Use camera": a saved choice first, otherwise the default camera (then prefer a connected iPhone). */
async function useDefaultCamera(): Promise<void> {
  const saved = savedCameraId();
  const known = saved ? (await listCameras()).some((c) => c.deviceId === saved) : false;
  await useCamera(known && saved ? { deviceId: saved } : { facing: 'user' });
}

async function refreshCameraList(activeId: string): Promise<void> {
  const cams = await listCameras();
  cameraSelect.replaceChildren(...cams.map((c) => {
    const o = document.createElement('option');
    o.value = c.deviceId;
    o.textContent = isContinuityCamera(c.label) ? `📱 ${c.label}` : c.label;
    o.selected = c.deviceId === activeId;
    return o;
  }));
  cameraSelect.hidden = cams.length < 2;
  // A Mac with an iPhone connected (Continuity Camera): use the phone unless the viewer chose otherwise.
  const iphone = cams.find((c) => isContinuityCamera(c.label));
  if (iphone && iphone.deviceId !== activeId && !savedCameraId() && !autoPickedIPhone) {
    autoPickedIPhone = true;
    await useCamera({ deviceId: iphone.deviceId });
  }
}

async function useCamera(request: CameraRequest): Promise<void> {
  lastRequest = request;
  if ('facing' in request) currentFacing = request.facing;
  stopSource();
  startPanel.hidden = true;
  errorPanel.hidden = true;
  setStatus('Opening camera…');
  try {
    const cam = await openCamera(video, request);
    source = cam;
    onSourceChanged();
    void refreshCameraList(cam.deviceId);
  } catch (err) {
    const e = err instanceof CameraError ? err : new CameraError(String(err), 'other');
    showCameraError(e.message);
  }
}

function useSample(): void {
  stopSource();
  startPanel.hidden = true;
  errorPanel.hidden = true;
  source = openSampleScene();
  onSourceChanged();
}

function stopSource(): void {
  source?.stop();
  source = null;
  if (airDrawing) setAirDrawing(false);
}

function onSourceChanged(): void {
  sourceBadge.textContent = source?.label ?? '';
  sourceBadge.classList.toggle('sample', source?.kind === 'sample');
  sourceButtons.forEach((b) => b.classList.toggle('active',
    (b.dataset.source === 'sample' && source?.kind === 'sample')
    || (source?.kind === 'camera' && 'facing' in lastRequest && b.dataset.source === currentFacing)));
  // An in-progress stroke cannot continue across a source switch; a reviewed region is screen-fixed and stays.
  if (phase.kind === 'armed' || phase.kind === 'tracing') invalidate('stalePair');
  airBtn.disabled = source?.kind !== 'camera';
  if (source?.kind !== 'camera' && airDrawing) void setAirDrawing(false);
  render();
}

function showCameraError(message: string): void {
  errorText.textContent = message;
  errorPanel.hidden = false;
  sourceBadge.textContent = 'No camera';
  setStatus('Camera unavailable');
}

const sourceFresh = (now: number): boolean => {
  const last = source?.lastFrameAt();
  return last != null && now - last <= Defaults.maximumSampleAgeSeconds * 1000;
};

// ---------- Drawing session (port of AirTraceSession screen-touch rules) ----------
function startDrawing(): void {
  if (!source) return;
  trace = [];
  phase = { kind: 'armed', startedAt: performance.now() };
  if (airDrawing) hand.reset();
  render();
}

function invalidate(reason: string): void {
  trace = [];
  phase = { kind: 'invalid', reason };
  render();
}

function consumePoint(p: Point, now: number): void {
  if (phase.kind !== 'armed' && phase.kind !== 'tracing') return;
  const last = source?.lastFrameAt();
  if (last == null) return; // no live source yet: nothing to draw on (iOS: no source timestamp → ignore)
  if (now - last > Defaults.maximumSampleAgeSeconds * 1000) { invalidate('stalePair'); return; }
  if (!(Number.isFinite(p.x) && Number.isFinite(p.y)) || p.x < 0 || p.y < 0 || p.x > viewport.width || p.y > viewport.height) {
    invalidate('invalidTouch');
    return;
  }
  trace.push(p);
  phase = { kind: 'tracing', startedAt: phase.startedAt };
}

function finishDrawing(): void {
  if (phase.kind !== 'armed' && phase.kind !== 'tracing') return;
  const result = fitTrace(trace, viewport);
  phase = result.ok ? { kind: 'review', ellipse: result.ellipse } : { kind: 'invalid', reason: result.reason };
  if (!result.ok) trace = [];
  render();
}

function accept(): void {
  if (phase.kind !== 'review') return;
  phase = { kind: 'accepted', ellipse: phase.ellipse };
  offset = { x: 0, y: 0 };
  mode = 'simulatedBlur'; // iOS: Accept region selects the Simulated blur preview
  render();
}

function nudge(dx: number, dy: number): void {
  if (phase.kind !== 'accepted') return;
  offset = { x: offset.x + dx * OFFSET_STEP, y: offset.y + dy * OFFSET_STEP };
  if (mode !== 'simulatedBlurPlusCopy') mode = 'simulatedBlurPlusCopy';
  render();
}

// Pointer input: mouse, pen and touch share one code path.
const toView = (e: PointerEvent): Point => {
  const r = canvas.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
};
canvas.addEventListener('pointerdown', (e) => {
  if (airDrawing || (phase.kind !== 'armed' && phase.kind !== 'tracing')) return;
  canvas.setPointerCapture(e.pointerId);
  trace = [];
  consumePoint(toView(e), performance.now());
  e.preventDefault();
});
canvas.addEventListener('pointermove', (e) => {
  // Armed too: if the touch-down landed before a fresh frame, the stroke starts at the first usable point.
  if (airDrawing || (phase.kind !== 'armed' && phase.kind !== 'tracing') || !canvas.hasPointerCapture(e.pointerId)) return;
  const events = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : [e];
  for (const ev of events.length ? events : [e]) consumePoint(toView(ev), performance.now());
});
const endPointer = (e: PointerEvent) => {
  if (airDrawing || !canvas.hasPointerCapture(e.pointerId)) return;
  canvas.releasePointerCapture(e.pointerId);
  // iOS rear touch: lifting the finger freezes the candidate for review. A touch that never produced a
  // usable point leaves the session armed instead of failing it.
  if (phase.kind === 'tracing') finishDrawing();
};
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', (e) => { if (canvas.hasPointerCapture(e.pointerId)) invalidate('invalidTouch'); });

// ---------- Air drawing (stretch: MediaPipe index fingertip, front camera) ----------
async function setAirDrawing(on: boolean): Promise<void> {
  airDrawing = on;
  airBtn.classList.toggle('active', on);
  airBtn.textContent = on ? 'Air drawing: on' : 'Air drawing (beta)';
  finishBtn.hidden = !on;
  if (on) {
    setStatus('Loading hand tracker…');
    const ok = await hand.load().catch((err) => { console.error(err); return false; });
    if (!ok) { airDrawing = false; finishBtn.hidden = true; airBtn.classList.remove('active'); airBtn.textContent = 'Air drawing (beta)'; setStatus('Hand tracker failed to load — use touch or mouse drawing'); }
  }
  if (phase.kind === 'armed' || phase.kind === 'tracing') invalidate('stalePair');
  render();
}

// ---------- Controls ----------
$('start-camera').addEventListener('click', useDefaultCamera);
$('start-sample').addEventListener('click', useSample);
$('retry-btn').addEventListener('click', () => useCamera(lastRequest));
$('error-sample-btn').addEventListener('click', useSample);
sourceButtons.forEach((b) => b.addEventListener('click', () => {
  const s = b.dataset.source as 'user' | 'environment' | 'sample';
  if (s === 'sample') useSample(); else useCamera({ facing: s });
}));
cameraSelect.addEventListener('change', () => {
  saveCameraId(cameraSelect.value);
  void useCamera({ deviceId: cameraSelect.value });
});
$('start-btn').addEventListener('click', startDrawing);
$('redo-btn').addEventListener('click', startDrawing);
$('redraw-btn').addEventListener('click', startDrawing);
$('accept-btn').addEventListener('click', accept);
finishBtn.addEventListener('click', finishDrawing);
airBtn.addEventListener('click', () => setAirDrawing(!airDrawing));
modeButtons.forEach((b) => b.addEventListener('click', () => { mode = b.dataset.mode as ComparisonMode; render(); }));

// Press-and-hold repeat for the offset arrows.
document.querySelectorAll<HTMLButtonElement>('[data-dx]').forEach((b) => {
  let timer: number | undefined;
  const dx = Number(b.dataset.dx), dy = Number(b.dataset.dy);
  const stop = () => { window.clearTimeout(timer); window.clearInterval(timer); timer = undefined; };
  b.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    nudge(dx, dy);
    stop();
    timer = window.setTimeout(() => { timer = window.setInterval(() => nudge(dx, dy), 70); }, 350);
  });
  ['pointerup', 'pointerleave', 'pointercancel'].forEach((ev) => b.addEventListener(ev, stop));
});
window.addEventListener('keydown', (e) => {
  const keys: Record<string, [number, number]> = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
  if (keys[e.key] && phase.kind === 'accepted') { e.preventDefault(); nudge(...keys[e.key]); }
  if (e.key === 'Enter' && phase.kind === 'review') accept();
});

function setStatus(text: string): void { statusEl.textContent = text; }

// ---------- UI state ----------
function render(): void {
  drawControls.hidden = !(phase.kind === 'idle' || phase.kind === 'armed' || phase.kind === 'tracing' || phase.kind === 'invalid');
  reviewControls.hidden = phase.kind !== 'review';
  acceptedControls.hidden = phase.kind !== 'accepted';
  $<HTMLButtonElement>('start-btn').disabled = !source;
  $<HTMLButtonElement>('start-btn').textContent = phase.kind === 'invalid' ? 'Draw again' : 'Start drawing';
  modeButtons.forEach((b) => b.classList.toggle('active', b.dataset.mode === mode));
  offsetReadout.textContent = `offset ${offset.x >= 0 ? '+' : ''}${offset.x}, ${offset.y >= 0 ? '+' : ''}${offset.y} px`;
  simLabel.hidden = !(phase.kind === 'accepted' && mode !== 'original');
  simLabel.textContent = SIMULATION_LABEL;

  const hints: Record<Phase['kind'], string> = {
    idle: source ? 'Press Start drawing, then draw a closed loop around part of the scene.' : 'Choose a camera or the sample scene to begin.',
    armed: airDrawing ? 'Show your index finger to the camera and trace a loop; press Finish shape at the start dot.' : 'Draw a closed loop with your mouse or finger. Finish back at the yellow start dot.',
    tracing: airDrawing ? 'Tracing — return to the start dot, then press Finish shape.' : 'Drawing… return to the start dot and release.',
    review: 'Review the yellow trace and cyan ellipse, then Accept region or Draw again.',
    accepted: 'Move the copy with the arrows (or arrow keys) and compare the three modes.',
    invalid: phase.kind === 'invalid' ? (rejectionText[phase.reason] ?? `Stroke cleared (${phase.reason}).`) : '',
  };
  hintEl.textContent = hints[phase.kind];
  hintEl.classList.toggle('warn', phase.kind === 'invalid');
}

// ---------- Frame loop ----------
function drawOverlay(ctx: CanvasRenderingContext2D, plan: CompositionPlan | null): void {
  ctx.save();
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if ((phase.kind === 'tracing' || phase.kind === 'review') && trace.length) {
    ctx.strokeStyle = '#ffd400';
    ctx.lineWidth = 3;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    trace.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
    ctx.stroke();
    const s = trace[0];
    if (phase.kind === 'tracing') {
      ctx.setLineDash([4, 4]);
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(s.x, s.y, closureRadius(viewport), 0, Math.PI * 2); // exact closure target
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.fillStyle = '#ffd400';
    ctx.beginPath();
    ctx.arc(s.x, s.y, 5, 0, Math.PI * 2);
    ctx.fill();
  }
  const ellipse = phase.kind === 'review' || phase.kind === 'accepted' ? phase.ellipse : null;
  if (ellipse && !(phase.kind === 'accepted' && mode === 'original')) {
    ctx.strokeStyle = phase.kind === 'review' ? '#00e5ff' : 'rgba(0,229,255,0.85)';
    ctx.lineWidth = 2;
    ctx.setLineDash([7, 5]);
    ctx.beginPath();
    ctx.ellipse(ellipse.center.x, ellipse.center.y, ellipse.radii.x, ellipse.radii.y, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (plan?.copy) {
    const d = plan.copy.destination;
    ctx.strokeStyle = 'rgba(255,255,255,0.95)';
    ctx.lineWidth = 1.5;
    ctx.setLineDash([5, 4]);
    ctx.strokeRect(d.x, d.y, d.width, d.height);
    ctx.setLineDash([]);
  }
  if (airDrawing) {
    const tip = hand.lastTip(viewport);
    if (tip) {
      ctx.fillStyle = '#ffd400';
      ctx.strokeStyle = '#000';
      ctx.beginPath();
      ctx.arc(tip.x, tip.y, 8, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
  }
  ctx.restore();
}

function frame(): void {
  requestAnimationFrame(frame);
  if (!viewport.width) return;
  const now = performance.now();
  const fresh = sourceFresh(now);

  // Watchdog (iOS expireInputs): a stalled camera clears an active stroke.
  if (phase.kind === 'tracing' && !fresh) invalidate('stalePair');

  const frameAt = source?.lastFrameAt() ?? null;
  const isNewFrame = frameAt != null && frameAt !== lastProcessedFrame;
  const ctx = canvas.getContext('2d', { alpha: false })!;
  if (!source || !fresh) {
    lastPlan = null;
    if (!source) { ctx.fillStyle = '#0b1220'; ctx.fillRect(0, 0, canvas.width, canvas.height); }
    if (source) setStatus('Scene unavailable');
    perfEl.textContent = source ? 'waiting for frames…' : '';
    return;
  }
  if (!isNewFrame && phase.kind !== 'tracing' && !airDrawing) {
    // Nothing changed in the source; keep the last composited frame.
    return;
  }
  lastProcessedFrame = frameAt;

  const t0 = performance.now();
  if (!compositor.drawOriginal(source)) return;
  if (airDrawing && source.kind === 'camera' && isNewFrame) {
    const sample = hand.detect(compositor.original, now);
    if (sample.kind === 'point' && (phase.kind === 'armed' || phase.kind === 'tracing')) {
      consumePoint({ x: sample.x * viewport.width, y: sample.y * viewport.height }, now);
    } else if (sample.kind === 'lost' && phase.kind === 'tracing') {
      invalidate('handLost');
    }
  }
  const ellipse = phase.kind === 'accepted' ? phase.ellipse : null;
  const plan = phase.kind === 'accepted'
    ? planComposition(mode, ellipse, true, viewport, offset, { x: 0, y: 0, width: viewport.width, height: viewport.height })
    : null;
  compositor.composite(plan, dpr, BLUR_STRENGTH);
  const t1 = performance.now();
  drawOverlay(ctx, plan);
  perf.record(now, t1 - t0);
  lastPlan = plan;

  const s = source.size();
  perfEl.textContent = `${perf.fps().toFixed(0)} fps · ${perf.meanMs().toFixed(1)} ms/frame (p95 ${perf.p95Ms().toFixed(1)}) · ${s.width}×${s.height} → ${viewport.width}×${viewport.height}@${dpr}x${airDrawing ? ` · hand ${hand.lastInferenceMs().toFixed(1)} ms` : ''}`;
  if (phase.kind === 'accepted' && lastPlan) {
    setStatus(lastPlan.statusText);
    const needsMove = mode === 'simulatedBlurPlusCopy' && offset.x === 0 && offset.y === 0;
    placementErrorEl.textContent = needsMove ? 'Use the arrows to move the copy off the region.' : (lastPlan.placementError ?? '');
    placementErrorEl.hidden = !placementErrorEl.textContent;
  } else {
    placementErrorEl.hidden = true;
    setStatus(source.kind === 'sample' ? 'Live sample scene' : 'Live camera');
  }
}

layout();
render();
requestAnimationFrame(frame);
