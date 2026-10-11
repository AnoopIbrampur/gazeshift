# GazeShift Six-Hour Implementation Plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` after implementation is requested. Follow the complete copyable prompts and exact evidence gates in [BUILD_PROMPTS.md](BUILD_PROMPTS.md); this is the concise schedule.

**Goal:** Record actual camera-tracked air tracing followed by live eyes driving one original-image patch copy on an iPhone 13.

**Architecture:** Reconfigure one ARSession between Setup/map and Live assist. Setup uses front imagery, face/eye estimates and Vision hand landmarks. The user traces one closed outline in the air while fixating a fixed reference, then reviews a bounding ellipse as an explicit approximation. Live mode uses the rear scene plus face anchors, a fresh gaze calibration and one rectangular copy at a chosen offset. No full-scene radial warp.

**Tech stack:** Swift, SwiftUI controls, ARKit, Vision hand-pose detection, and one minimal native renderer. No new pretrained model or backend.

**Spec:** [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md); detailed implementation prompts in [BUILD_PROMPTS.md](BUILD_PROMPTS.md).

## Global constraints

- Documentation only; no app exists. Implementation starts only when requested.
- Six hours is optimistic and conditional on tooling/device readiness. Setup during an event consumes the same six-hour window. Air gestures and recalibration increase risk.
- The user resolves the known unaccepted Xcode license, signing and device trust; do not accept licenses or install Mac applications on their behalf.
- One ARSession, sequential supported configurations: front `ARFaceTrackingConfiguration` for hand+face setup, then world tracking with `userFaceTrackingEnabled` for rear image+face anchors. No competing capture sessions or invented raw front buffer in world mode.
- `lookAtPoint` is face-relative. Calibrate physical-display gaze in each mode and pass P2's held-out fixed-window coverage/error gates, including after the switch.
- Air tracing is required. Touch Review/Redo controls are allowed; touchscreen drawing, head pose or scripted gaze cannot replace the requested inputs.
- A user-drawn approximate ellipse is not a retinal measurement. Preserve its fixation-relative center offset; no patient diagnosis, PRL inference, independent per-eye map or promised benefit.
- Normal Live assist has no artificial blur. Required Demo comparison offers Original / Simulated blur / Simulated blur + copy in identical full-viewport geometry; simulation stays off until selected, uses original source pixels and applies blur last.
- Source/destination must fit valid image/view bounds; destination must clear the approximate region and an error-based safety gap. Invalid placement bypasses to original, never clamps or invents content.
- Keep geometry, pose and distance stable; changes invalidate calibration/region. Copied content moves with gaze and may move when looked at; this is a peripheral-viewing experiment.
- No accounts, cloud frame upload, hardware purchase, clinical participants or feature expansion. Local prerecorded scene fallback must be labeled and retain real air tracing/live gaze.
- Gang write-path agent, feature branches, verified checkpoints and independent Superpowers review before merge/push. Keep secrets and large recordings out of Git.

## Preflight — P0

- [ ] Resolve user-controlled setup, verify signing and launch the minimal app on the actual phone.
- [ ] Record actual setup time, device/iOS, chosen orientation, viewport and evidence provenance.
- [ ] Preserve repository protections and unrelated work; report unavailable protection rather than bypassing it.

## P1 — configuration and sensor proof (minutes 0–30)

- [ ] Prove front image, face/eye data and actual Vision index/thumb landmarks concurrently; display a timestamped 2D air cursor.
- [ ] Test one image-to-display transform for orientation, crop, y-flip and front mirroring; no double transformation.
- [ ] Use one in-flight hand request, newest frames and confidence/staleness rejection; verify finger motion does not hide the eyes.
- [ ] Reconfigure the same session to rear+face tracking; clear old state and prove fresh scene/eye data. Return to front setup for P2.
- [ ] Record support/results and commit. Hand or eye failure blocks the requested build; rear-only failure may use labeled local recorded input.

## P2 — front-mode calibrated gaze (minutes 30–90)

- [ ] Fit nine-target personal calibration in physical display coordinates.
- [ ] Test four novel quarter positions twice using P2's fixed 1-second windows, 20 scheduled slots, >=80% valid coverage and >=10 distinct timestamps per target/pass; report rejected counts/reasons.
- [ ] Keep finite off-screen estimates in error scoring; report median/p90 aggregate and per target/pass against predeclared thresholds. Center repeats are separate controls.
- [ ] Demonstrate eye-only movement with the head still; reject blinking/stale/nonfinite samples without inventing confidence.
- [ ] Run relevant checks/build, commit and stop. **Minute-90 gate:** all setup gaze criteria pass before air mapping.

## P3 — air outline, review and live-mode validation (minutes 90–150)

- [ ] Fixate the stationary reference, pinch to trace one closed outline in the air, return to its start and release. Drift, occlusion or missing data invalidates the whole stroke; require Redo.
- [ ] Reject nonfinite/out-of-viewport, insufficient, open or zero-area traces; never invent missing boundary points.
- [ ] Show raw outline and its min/max bounding ellipse for explicit review. Store center offset from fixation, radii and setup metadata in session memory; preserve the offset, not irregular shape details.
- [ ] Reconfigure the same session, clear old anchors/timestamps/hand results and calibration validity, and prove fresh rear scene/eye samples.
- [ ] Refit and repeat ALL P2 gaze criteria in the actual live layout. If using the recorded-scene fallback, validate that final layout too.
- [ ] Verify mapping/switching math and on-device behavior, commit and stop. **Minute-150 gate:** actual air map, explicit review and final-mode gaze validation pass before relocation.

## P4 — original-image patch copy (minutes 150–210)

- [ ] Position the reviewed ellipse at gaze plus its stored fixation-relative offset; take its enclosing rectangular crop from the original current frame.
- [ ] Copy it to one user-chosen offset over the original scene. Explain source duplication, destination occlusion and gaze-chasing limitations.
- [ ] Require valid in-bounds source and destination; conservatively reject destination overlap with the region plus the live-error safety gap. Show “No valid placement — original view” on rejection.
- [ ] On invalid gaze, clear marker/copy and show “Tracking unavailable — original view” over a healthy source until three distinct fresh valid samples recover. A stalled scene instead shows “Scene unavailable” or “Paused”.
- [ ] Implement all three required Demo comparison views with the same frame/mask/viewport; copy before blur and blur last. A labeled frozen comparison is allowed, separate from real-time gaze evidence. Normal Live assist stays unblurred.
- [ ] Check offset preservation, source-before-blur/output, coordinate transforms, disabled-copy identity, bounds/overlap and loss/recovery. Commit the verified checkpoint.

## P5 — real-device verification (minutes 210–300)

- [ ] Repeat P2 coverage/error gates and drift tests in live mode; keep all insufficient windows and off-screen errors in the report.
- [ ] Challenge air-trace fixation drift, hand/face occlusion, incomplete strokes, switching, layout/distance changes, edge placements and stale/invalid data.
- [ ] Verify separate source failure, gaze loss, placement failure and recovery; no stale copied patch or frozen frame labeled live.
- [ ] Measure actual frame/update rates, processing time and sample age without calling them end-to-end latency.
- [ ] Record agent-observed, user-reported and not-tested results separately; fix the highest-impact failures, rerun affected checks and commit.

## P6 — evidence, review and integration (minutes 300–360)

- [ ] Record actual air tracing/fixation, ellipse review, camera-switch/calibration results, live eye-only relocation, all three required blur-comparison views and failure/recovery behavior. Label frozen comparisons as frozen.
- [ ] Verify the saved recording plays; use an external hand/eye view when possible. Keep assumed-region and recorded-source labels visible; no regenerated evidence.
- [ ] Prepare an honest pitch covering the technical result, approximation, duplication/occlusion/gaze-chasing limits and future comparison with magnification.
- [ ] Commit and obtain independent review of final BASE/HEAD; resolve all Critical/Important findings before permitted merge/push and verify remote state.
- [ ] Report any missing required blur comparison, device test, recording, review or integration gate at minute 360; do not cut scope silently. A build alone does not prove either requested live input.

## After the hackathon

Clinical scotoma/PRL mapping, separate-eye/binocular needs, fixation reliability, wearable hardware and patient benefit require separate validation. Participant access and partnerships are unconfirmed. Vercel may host an optional later companion page; it is not the native tracking runtime.
