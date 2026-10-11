# GazeShift — project context

Use this document and [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md) as the maintained specification. [BUILD_PROMPTS.md](BUILD_PROMPTS.md) and the diagnostic reports under `docs/` preserve the superseded gaze experiment; their eye-tracking requirements do not govern the manual pivot.

## Current state and owner

- Working title: **GazeShift**; owner: a Penn State AI Engineering student with a Mac/laptop and a limited hardware budget.
- Repository: [Hussain-coder-eng/gazeshift](https://github.com/Hussain-coder-eng/gazeshift), private.
- On 2026-10-11, baseline `5876905` was built, installed and launched on a physical **iPhone 15 Pro Max** before pivot edits. The user also reported “Camera opens; ready for new version.” The original plan named an iPhone 13; that was not the deployment device for this evidence.
- The earlier “documentation only” and pending-Xcode-license notes are historical. Baseline deployment succeeded; do not carry those notes forward as current blockers or infer that every setup condition is guaranteed for a future run.
- The user explicitly pivoted completely away from eye tracking while retaining finger-in-air tracing. Manual-flow implementation is in progress and awaits physical-device verification of gestures and end-to-end operation.

## Current scope

Build a manual screen-space approximation:

**Front image → Vision index/thumb landmarks → pinch air trace → reviewed bounding ellipse → chosen copy offset → rear original image → fixed display region and translated rectangular copy.**

The region stays fixed in display coordinates after review. It does not follow the eyes, head or a retinal defect. Remove runtime eye estimates, gaze calibration, gaze validation and gaze-driven placement; do not replace them with synthetic gaze. Actual camera-tracked air tracing remains essential. Touch may operate Review, Redo and offset controls, not silently replace tracing.

Use one continuous closed stroke and review the min/max bounding ellipse derived from it. The ellipse loses irregular outline details and represents an assumed region, not a diagnosed defect. Keep trace and region data in session memory. Choose one explicit copy offset; do not auto-clamp, shrink or search for a different placement.

## Technical path

Reuse the existing native Swift, SwiftUI, ARKit, Vision and Metal implementation. No new dependency, model training, backend or cloud processing belongs in the image loop.

Use the same ARSession sequentially. Front setup retains supported `ARFaceTrackingConfiguration` solely as the camera-frame source for `VNDetectHumanHandPoseRequest`; its name does not mean eye or face estimates drive the app. Rear mode uses `ARWorldTrackingConfiguration` with `userFaceTrackingEnabled = false`. Do not start competing capture sessions or require simultaneous front/rear video.

Vision supplies a virtual 2D cursor from hand landmarks, not a 3D pointing ray. Verify orientation, viewport crop, front mirroring and y-axis conversion on the phone. Only fresh, valid hand samples may form the outline. Hand loss, stale data, occlusion or a broken stroke must invalidate the stroke and require Redo rather than joining gaps. Clear transient frame/hand state at a camera switch and require fresh rear imagery before displaying effects.

Copy the enclosing rectangle from the original unblurred frame. Source and destination must fit valid image/view bounds, and destination must clear the approximate region plus the named placement safety gap. The gap is an engineering guard, not a measured gaze error or evidence of usable peripheral vision. Invalid placement shows “No valid placement — original view” and bypasses the copy. Never recursively sample an earlier copy, clamp partial source pixels, invent content or introduce a full-scene warp.

Normal Live assist adds no artificial blur. Preserve Original / Simulated blur / Simulated blur + copy using the same source frame, mask and full-viewport geometry. Simulation is explicitly labeled and off until selected. Copy original pixels first, then apply the identical simulated blur last to both simulated modes. The reviewed region remains fixed in all modes; eye movements must not move it.

Track scene freshness independently of the hand stroke. A stalled or failed source must clear effects and show “Scene unavailable” or “Paused”, never a frozen frame labeled live. Stop, retry, background/resume and reconfiguration must not retain stale effect state. Keep one orientation and stable viewing distance for the controlled demonstration; verify layout changes before reusing a region.

## What counts as evidence

The six-hour budget is an estimate for completing the manual phone experiment, not a guarantee or a fresh claim that six hours remain. Reuse the already deployed baseline and prioritize actual air tracing, one copy and device evidence. The current checks are in [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md); old gaze accuracy gates are superseded.

Success means actual air tracing, explicit ellipse review, rear-scene copying at the chosen offset, all three comparison modes, and visible failure/recovery demonstrated on the phone in a playable recording. Keep agent-observed, user-reported and not-tested results separate. A successful build, install, launch or simulator check does not prove physical gestures or the full flow. Do not invent frame rates, latency, accuracy or benefit figures. Sample age is not end-to-end latency.

If live rear input fails, a local prerecorded scene is a clearly labeled fallback; air tracing remains live. State which source the recording uses. No prerecorded or regenerated media may stand in for working gesture evidence.

## Claims and limits

The manual region is fixed to the screen, whereas a retinal blind spot moves within the displayed scene as the eyes move. This prototype therefore cannot track the blind spot, measure retinal damage, infer a preferred retinal locus (PRL), diagnose disease, restore normal sight, replace prescriptions or establish patient benefit. Simulated blur is an illustration, not a patient's vision. The copy duplicates content and covers destination content.

Future assistance would require independently measured vision mapping, registration, PRL and binocular validation, and task-performance/comfort comparison with ordinary magnification. No clinical participant access, clinician partnership, Nittany AI selection or startup validation is confirmed; use conditional wording such as “if selected.”

## Working instructions

Keep work small and practical. No accounts, backend, object recognition, new diseases, hardware purchases, new model training or clinical calibration. Preserve diagnostic history; do not silently rewrite earlier results as successes. Synced `sources/` files remain read-only.

Use feature branches and the Gang's write-path agent. Commit and verify scoped changes, then obtain independent Superpowers review of final BASE/HEAD before merging and pushing. Re-review a branch carried over from an earlier session. Keep the repository private, preserve available protections and report unavailable protection without weakening privacy. Keep secrets, signing material and large recordings out of Git.
