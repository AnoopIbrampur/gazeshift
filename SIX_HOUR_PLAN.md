# GazeShift Six-Hour Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` for implementation and the Gang's write-path agent on feature branches. This plan and [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) supersede the gaze requirements in historical [BUILD_PROMPTS.md](BUILD_PROMPTS.md).

**Goal:** Record actual camera-tracked air tracing, reviewed ellipse placement and one original-image copy on the physical iPhone 15 Pro Max. No eye tracking or gaze calibration.

**Architecture:** Reconfigure one ARSession from front-camera hand tracing to the rear scene. The reviewed ellipse stays fixed in display coordinates; a user-selected offset positions its rectangular copy. Reuse Swift, SwiftUI, ARKit, Vision and the existing Metal renderer.

**Status:** Baseline `5876905` was built, installed and launched on this phone before pivot edits on 2026-10-11. The user reported that the baseline camera opens. The manual flow is in progress and awaits physical-device verification. A launch proves deployment only. The original iPhone 13 and pending-license setup notes are historical.

The 360-minute budget below is an optimistic work allocation, not a guarantee or a statement of time remaining. Setup or signing problems during the build consume that budget.

## Global constraints

- Actual finger-in-air tracing remains required; touch may operate Review, Redo and copy-offset controls.
- No runtime eye estimates, gaze calibration, synthetic gaze or gaze-driven movement. The manual region cannot track a retinal blind spot.
- One ARSession: front `ARFaceTrackingConfiguration` for camera frames only, then rear world tracking with `userFaceTrackingEnabled = false`.
- Preserve bounds/overlap rejection, original-image sampling, blur-last ordering and hand/scene freshness.
- Normal Live assist stays unblurred. Preserve labeled Original / Simulated blur / Simulated blur + copy in identical full-viewport geometry.
- No new dependencies, backend, cloud frame upload, hardware purchases, new diseases or clinical calibration.
- Keep the repository private, historical diagnostics intact, secrets/large recordings out of Git, and independent review before merge/push.

## 0–90 minutes — manual input and camera switch

- [ ] Build the pivot and launch it on the actual phone; record device/iOS, commit, orientation and evidence provenance.
- [ ] Show fresh front imagery and an actual Vision index/thumb cursor; verify orientation, crop, y-flip and front mirroring.
- [ ] Pinch to trace one continuous closed outline, return to its start and release. Reject insufficient, open, zero-area, nonfinite or out-of-viewport traces.
- [ ] Reject broken strokes after hand loss, occlusion or stale samples; require Redo rather than joining missing points.
- [ ] Review the raw outline and its bounding ellipse explicitly; preserve the chosen screen position and one selected copy offset.
- [ ] Switch the same session to rear capture, clear transient frame/hand state and prove fresh scene frames without eye-tracking data.

**Go/no-go:** Actual air tracing, explicit review and fresh rear imagery must work on the phone. No simulator, touchscreen stroke or successful build substitutes for this gate.

## 90–210 minutes — fixed-region copy and comparison

- [ ] Keep the reviewed ellipse fixed in display coordinates when the eyes or head move; remove eye-dependent runtime gates and controls.
- [ ] Copy its enclosing rectangle from the original frame to the chosen offset. Show the source duplication and destination occlusion honestly.
- [ ] Reject invalid image/view bounds and destination overlap with the region. The named fixed-region gap is zero extra engineering clearance. Show “No valid placement — original view”; do not clamp or invent pixels.
- [ ] Preserve Original, Simulated blur and Simulated blur + copy using one frame/mask/viewport. Copy original pixels first and apply blur last. Normal Live assist remains unblurred.
- [ ] Clear effects on stale/failed scene input and show “Scene unavailable” or “Paused”; do not label a frozen frame live. Check Stop/Retry and background/resume.
- [ ] Run the relevant core checks and affected build; verify fixed-region placement, coordinate conversion, bounds/overlap, disabled-copy identity and original-before-blur behavior.

## 210–300 minutes — physical-device challenges

- [ ] Exercise the complete trace → review → offset → rear-scene flow and Redo/repeated switching.
- [ ] Test hand loss, pinch release, broken/open strokes, image edges, invalid placement and source failure/recovery.
- [ ] Confirm eye movement does not move the reviewed region or patch and no eye calibration is required.
- [ ] Verify a distinctive source object is copied intact; Original removes the effect; all three comparison modes keep identical geometry and clear labels.
- [ ] Measure actual frame/update rates, processing time and sample age only if instrumentation is available; do not call sample age end-to-end latency.
- [ ] Record pass/fail/not-tested and agent-observed/user-reported provenance. Fix the highest-impact failures and rerun their specific checks.

## 300–360 minutes — evidence, review and integration

- [ ] Record actual air tracing, explicit review, chosen offset, rear-scene copying, all three comparison modes and visible failure/recovery. Include an external hand view when possible.
- [ ] Open the saved recording and verify playback and visible behavior; record its location, device and build/commit. Label any prerecorded scene fallback while retaining live air tracing.
- [ ] Prepare an honest pitch: manual screen approximation, duplicate/occluded content, no retinal tracking, no diagnosis or demonstrated patient benefit. Future benefit needs comparison with magnification.
- [ ] Commit and obtain independent Superpowers review of final BASE/HEAD; fix all Critical/Important findings, rerun affected checks and re-review before permitted merge/push. Verify remote state.
- [ ] Report every unfinished device, comparison, recording, review or integration gate. Do not turn a build or launch into an end-to-end success claim.

Clinical vision mapping, PRL/binocular validation, wearable hardware and patient benefit remain separate research. Participant access and partnerships are unconfirmed. A companion website is outside this build.
