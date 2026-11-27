// Frame sources: a live camera (getUserMedia) or a bundled synthetic sample scene.
// Both expose the same small interface so the frame loop never cares which one is active.

export type Facing = 'user' | 'environment';

export interface FrameSource {
  readonly kind: 'camera' | 'sample';
  readonly label: string;
  /** True when the displayed image should be mirrored (front-camera selfie preview). */
  readonly mirrored: boolean;
  /** Intrinsic size of the drawable, or 0 × 0 before the first frame. */
  size(): { width: number; height: number };
  drawable(): CanvasImageSource;
  /** performance.now() of the newest decoded frame, or null before the first frame. */
  lastFrameAt(): number | null;
  stop(): void;
}

export class CameraError extends Error {
  constructor(message: string, readonly code: string) { super(message); }
}

/** Human-readable reasons for the common getUserMedia failures (including Meet holding the webcam). */
const CAMERA_TIMEOUT_MS = 15000;

/** getUserMedia can wait forever on an unanswered permission prompt; give up visibly instead. */
function withTimeout(request: Promise<MediaStream>, ms: number): Promise<MediaStream> {
  return new Promise((resolve, reject) => {
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      reject(Object.assign(new Error('timeout'), { name: 'TimeoutError' }));
    }, ms);
    request.then((stream) => {
      clearTimeout(timer);
      // A stream granted after we gave up must not keep the camera light on.
      if (timedOut) stream.getTracks().forEach((t) => t.stop()); else resolve(stream);
    }, (err) => { clearTimeout(timer); if (!timedOut) reject(err); });
  });
}

export function describeCameraError(err: unknown): CameraError {
  const name = (err as { name?: string })?.name ?? '';
  switch (name) {
    case 'TimeoutError':
      return new CameraError('The camera didn’t start. Check for a permission prompt in the address bar (and macOS System Settings → Privacy → Camera), then press Retry — or use the sample scene.', 'timeout');
    case 'NotAllowedError':
    case 'SecurityError':
      return new CameraError('Camera permission was denied. Allow camera access in the browser’s site settings and press Retry — or use the sample scene.', 'denied');
    case 'NotFoundError':
    case 'OverconstrainedError':
      return new CameraError('No matching camera was found on this device. Try the other camera or use the sample scene.', 'notfound');
    case 'NotReadableError':
    case 'AbortError':
      return new CameraError('The camera is busy — another app (for example a video call) may be using it. Close it and press Retry, or use the sample scene.', 'busy');
    default:
      return new CameraError(`Camera unavailable${name ? ` (${name})` : ''}. Use the sample scene instead.`, 'other');
  }
}

export interface CameraInfo { deviceId: string; label: string }

/** iPhone used as a Mac webcam (Continuity Camera) shows up as its own video device. */
export const isContinuityCamera = (label: string) => /iphone|continuity/i.test(label);

/** Video inputs. Labels are only filled in after camera permission has been granted once. */
export async function listCameras(): Promise<CameraInfo[]> {
  if (!navigator.mediaDevices?.enumerateDevices) return [];
  const devices = await navigator.mediaDevices.enumerateDevices().catch(() => [] as MediaDeviceInfo[]);
  return devices.filter((d) => d.kind === 'videoinput' && d.deviceId)
    .map((d, i) => ({ deviceId: d.deviceId, label: d.label || `Camera ${i + 1}` }));
}

export type CameraRequest = { facing: Facing } | { deviceId: string };

export async function openCamera(video: HTMLVideoElement, request: CameraRequest): Promise<FrameSource & { deviceId: string }> {
  const facing: Facing = 'facing' in request ? request.facing : 'user';
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    throw new CameraError('Camera access needs HTTPS and a supported browser. Use the sample scene instead.', 'insecure');
  }
  let stream: MediaStream;
  try {
    // `ideal` (not `exact`) so single-camera laptops still open their only camera.
    stream = await withTimeout(navigator.mediaDevices.getUserMedia({
      audio: false,
      video: 'deviceId' in request
        ? { deviceId: { exact: request.deviceId }, width: { ideal: 1280 }, height: { ideal: 720 } }
        : { facingMode: { ideal: facing }, width: { ideal: 1280 }, height: { ideal: 720 } },
    }), CAMERA_TIMEOUT_MS);
  } catch (err) {
    throw describeCameraError(err);
  }
  video.srcObject = stream;
  video.muted = true;
  video.playsInline = true;
  await video.play().catch(() => undefined);

  const track = stream.getVideoTracks()[0];
  const settings = track?.getSettings?.() ?? {};
  const actualFacing = settings.facingMode as string | undefined;
  const trackLabel = track?.label ?? '';
  // Mirror selfie-style cameras only. Laptops often report no facingMode, so fall back to the label;
  // an iPhone used as a Mac webcam (Continuity Camera) films the scene and is never mirrored.
  const mirrored = isContinuityCamera(trackLabel) ? false
    : actualFacing ? actualFacing === 'user'
    : 'deviceId' in request ? /facetime|front|integrated|webcam|user/i.test(trackLabel)
    : facing === 'user';
  const label = isContinuityCamera(trackLabel) ? `iPhone camera (${trackLabel})`
    : actualFacing === 'environment' ? 'Rear camera'
    : actualFacing === 'user' ? 'Front camera'
    : (trackLabel || (facing === 'user' ? 'Front camera' : 'Camera'));

  let last: number | null = null;
  let stopped = false;
  const anyVideo = video as HTMLVideoElement & {
    requestVideoFrameCallback?: (cb: () => void) => number;
  };
  if (typeof anyVideo.requestVideoFrameCallback === 'function') {
    const onFrame = () => {
      if (stopped) return;
      last = performance.now();
      anyVideo.requestVideoFrameCallback!(onFrame);
    };
    anyVideo.requestVideoFrameCallback(onFrame);
  } else {
    // Fallback: treat an advancing currentTime as a new frame.
    let lastTime = -1;
    const poll = () => {
      if (stopped) return;
      if (video.currentTime !== lastTime && video.readyState >= 2) { lastTime = video.currentTime; last = performance.now(); }
      requestAnimationFrame(poll);
    };
    requestAnimationFrame(poll);
  }

  return {
    kind: 'camera',
    deviceId: settings.deviceId ?? ('deviceId' in request ? request.deviceId : ''),
    label,
    mirrored,
    size: () => ({ width: video.videoWidth, height: video.videoHeight }),
    drawable: () => video,
    lastFrameAt: () => last,
    stop: () => {
      stopped = true;
      stream.getTracks().forEach((t) => t.stop());
      video.srcObject = null;
    },
  };
}

/**
 * Bundled synthetic scene (no media files): readable text plus moving shapes, so the per-frame copy
 * is visibly live. Always labeled in the UI as a sample, never presented as a camera.
 */
export function openSampleScene(): FrameSource {
  const canvas = document.createElement('canvas');
  canvas.width = 1280;
  canvas.height = 720;
  const ctx = canvas.getContext('2d')!;
  let last: number | null = null;
  let stopped = false;
  const lines = [
    'Central vision loss can hide exactly what you look at.',
    'Draw around the hidden part, then place a copy where you can see it.',
    'Bus 42 · Downtown · arriving in 3 min',
    'EXIT  →   Platform 2   ·   Pharmacy open until 9 PM',
  ];
  const draw = (t: number) => {
    if (stopped) return;
    const s = t / 1000;
    const g = ctx.createLinearGradient(0, 0, 1280, 720);
    g.addColorStop(0, '#16324f');
    g.addColorStop(1, '#2a6f6a');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 1280, 720);
    // Checkerboard "shelf" in the lower third for visible texture.
    for (let x = 0; x < 1280; x += 64) {
      for (let y = 480; y < 720; y += 64) {
        ctx.fillStyle = ((x + y) / 64) % 2 === 0 ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.10)';
        ctx.fillRect(x, y, 64, 64);
      }
    }
    ctx.fillStyle = '#f4f1e8';
    ctx.font = '600 44px system-ui, -apple-system, Segoe UI, sans-serif';
    lines.forEach((line, i) => ctx.fillText(line, 64, 120 + i * 78));
    // Moving marker and rotating square: proof that the copy is re-sampled every frame.
    const bx = 640 + Math.sin(s * 1.3) * 420;
    ctx.fillStyle = '#ffcc33';
    ctx.beginPath();
    ctx.arc(bx, 560, 46, 0, Math.PI * 2);
    ctx.fill();
    ctx.save();
    ctx.translate(1080, 600);
    ctx.rotate(s);
    ctx.fillStyle = '#ff5d73';
    ctx.fillRect(-50, -50, 100, 100);
    ctx.restore();
    ctx.fillStyle = 'rgba(255,255,255,0.9)';
    ctx.font = '500 28px ui-monospace, Menlo, monospace';
    ctx.fillText(new Date().toLocaleTimeString(), 64, 680);
    last = performance.now();
    requestAnimationFrame(draw);
  };
  requestAnimationFrame(draw);
  return {
    kind: 'sample',
    label: 'Sample scene — not live camera',
    mirrored: false,
    size: () => ({ width: canvas.width, height: canvas.height }),
    drawable: () => canvas,
    lastFrameAt: () => last,
    stop: () => { stopped = true; },
  };
}
