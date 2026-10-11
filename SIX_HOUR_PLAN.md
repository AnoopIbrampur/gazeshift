# GazeShift Six-Hour Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` to implement this plan task by task after implementation is authorized. Steps use checkboxes to preserve completion evidence.

**Goal:** Record an iPhone demo in which live eye movements drive a live transformation of the displayed camera scene around an explicitly assumed or simulated blind-spot region.

**Architecture:** A single native ARKit session supplies rear-camera frames and front-camera face/eye estimates. A calibrated mapping converts face-relative gaze into physical-screen coordinates; one simple image warp follows that gaze. Invalid tracking clears the marker and adaptive effect, returns to the original feed, and displays “Tracking unavailable — original view” until valid tracking returns.

**Tech stack:** Swift, ARKit, Apple's existing tracking/ML, and a minimal native image-rendering path. No new model training or cloud LLM in the live loop.

**Spec:** [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md).

## Global constraints

- Status: plan only; no app exists yet. Start implementation only when requested.
- Available hardware: iPhone 13 and a Mac/laptop; limited hardware budget.
- Six hours means **360 minutes of build time after preflight succeeds**, not a promise that setup or device capability will work.
- Known 2026-10-11 blocker: the user must resolve the unaccepted Xcode license and verify device signing/deployment. Do not accept the license or install applications on their behalf.
- One ARKit session; check `supportsUserFaceTracking` before enabling `ARWorldTrackingConfiguration.userFaceTrackingEnabled`. Do not run competing ARKit/AVFoundation sessions.
- `ARFaceAnchor.lookAtPoint` is face-relative; calibration to the physical display is required. Camera projection alone is not screen gaze.
- Live eye tracking is essential. No fake gaze or substitution of head movement. Prerecorded rear-scene input is an allowed fallback only when clearly labeled; keep live gaze.
- No accounts, backend, object recognition, hardware purchase, clinical calibration, or feature expansion.
- One controlled seated demo with an adjustable assumed/simulated region. No diagnosis, proven patient benefit, restored sight, cure, or prescription/inserts replacement claims.
- Use feature branches and the Gang's write-path agent. Commit and verify, then obtain independent Superpowers review before merging/pushing `main`.

## Files and deliverables

The current repository contains only `README.md` (idea/status), `PROJECT_CONTEXT.md` (durable context), and this plan. When app implementation is authorized, create the smallest native iOS project and record its actual file paths in the feature-branch work summary. Keep session handling, gaze calibration, and rendering responsibilities clear without scaffolding unrelated features. Record real-device test outcomes and the location of the final video; do not commit signing secrets or large recordings to Git.

## Review focus

- **Coordinate mismatch:** held-out screen targets and edge targets must reveal orientation, mirroring, preview-crop, or camera/display alignment errors.
- **Head movement mistaken for eye tracking:** eyes must move the calibrated marker with the head still; then test head movement separately.
- **Lost, blinking, or invalid tracking:** the marker and adaptive effect must clear, the original image must return, and “Tracking unavailable — original view” must remain visible until valid tracking returns.
- **Drift and delay:** repeat calibration targets later and inspect recorded motion for visible lag; report observations without fabricated measurements.
- **Fallback misrepresented as live input:** the recording and pitch must label prerecorded scene input and still demonstrate live eye tracking.

## Preflight — before the six-hour clock

- [ ] User resolves the Xcode license; verify a working Xcode installation and signing account.
- [ ] Connect the iPhone 13, confirm device trust/developer setup as required, and run a minimal signed native app on the actual phone.
- [ ] Check the native combined-tracking capability on that device. If unsupported, document the result before spending the build window.
- [ ] Prepare a stable seated setup, lighting, a few physical/onscreen targets, and a way to record the actual demonstration.

## Task 1 — live capture and calibrated eyes (minutes 0–90)

**Deliverable:** Rear-camera feed plus a visible calibrated screen-gaze marker on the iPhone.

- [ ] Use a single combined-tracking ARKit session and prove rear frames and face/eye estimates arrive together.
- [ ] Display the unmodified rear scene with the orientation and display mapping made explicit.
- [ ] Gather calibration samples at onscreen targets and map the face-relative estimate to the physical screen.
- [ ] Test held-out targets, screen edges, and eye movement with the head still; test head movement separately.
- [ ] Trigger tracking loss and verify the marker clears, the original feed remains visible, and “Tracking unavailable — original view” appears. Verify the status clears and the marker resumes only after valid tracking returns.
- [ ] Record the actual device/configuration, results, and blockers; commit the working checkpoint on the feature branch.

**Go/no-go at minute 90:** Continue to remapping only if simultaneous data and useful calibrated live eye response have been demonstrated on the phone. If rear-scene capture is the only blocker, use clearly labeled prerecorded scene input while preserving live gaze. If gaze cannot be demonstrated, preserve the experiment and failure evidence; do not silently spend the remaining window on a substitute app or claim the core goal succeeded.

## Task 2 — one gaze-following warp (minutes 90–210; 120 minutes)

**Deliverable:** One adjustable experimental warp around the assumed/simulated region, following calibrated gaze in display coordinates.

- [ ] Add controls for the region's assumed size/offset and a simple warp strength; explicitly label the region as assumed/simulated.
- [ ] Implement the smallest useful image transformation and verify its center follows the calibrated display marker.
- [ ] Include an original/transformed view toggle for comparison. Keep the image visible at edges and avoid invalid rendering coordinates.
- [ ] On invalid/lost tracking, clear the marker, disable the adaptive effect, show the original feed, and display “Tracking unavailable — original view.” On valid tracking recovery, clear the status and resume the marker/effect; verify both transitions on the phone.
- [ ] Leave one small runnable check for any nontrivial coordinate/warp logic, then commit the checkpoint. This check supplements real-device evidence.

Do not tune a clinically meaningful scotoma or PRL mapping here. The adjustable parameters support an experiment, not retinal diagnosis.

## Task 3 — alignment, latency, and failure tests (minutes 210–300; 90 minutes)

**Deliverable:** A short factual test record and a stable controlled demonstration.

- [ ] Re-test held-out center/edge targets, orientation/alignment, and eyes moving with the head still.
- [ ] Test head motion separately, then blinks, looking away, obscured face, tracking recovery, and invalid gaze.
- [ ] Verify each tracking-loss case returns to the original feed with no stale active warp and the visible “Tracking unavailable — original view” status. Verify the status persists during loss and clears only when valid tracking returns and the marker/effect resume.
- [ ] Revisit calibration targets after elapsed use to observe drift; inspect frame/gaze/warp motion for visible delay.
- [ ] Compare original/transformed views. Document only actual observations and measured values when a real measurement exists.
- [ ] Fix the highest-impact failure, repeat its check, and commit the checkpoint. Obtain independent review before merging any branch.

## Task 4 — fixes, video, and pitch (minutes 300–360; 60 minutes)

**Deliverable:** Recorded video of the actual device and a short pitch with honest limits.

- [ ] Freeze features; resolve faults that prevent the controlled seated demo.
- [ ] Record live eyes driving the marker and image warp; include the original/transformed comparison and tracking-loss behavior.
- [ ] Label prerecorded scene input if used. State that the region is assumed/simulated and the transformation affects the phone display only.
- [ ] Preserve the recording and document its location with the device, setup, and remaining limitations. A build or simulator screenshot does not replace this video.
- [ ] Explain the long-term wearable idea, immediate technical result, and next validation step: compare with ordinary magnification before claiming user benefit.
- [ ] Commit verified changes, complete independent review, fix Critical/Important findings, and merge/push only after review passes. If review or recording is unfinished at the cutoff, report it as remaining work; do not label the project fully complete.

## After the hackathon

Retinal/scotoma mapping, PRL calibration, bilateral viewing, stability/adaptation, clinical study design, and wearable integration are separate future research. Participant access and partner commitments are unconfirmed. Nittany AI and startup resources are possible next steps, conditional on eligibility/selection and actual validation. See the [source links and clinical boundaries](PROJECT_CONTEXT.md#references).
