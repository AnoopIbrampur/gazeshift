# What we tried (2026-10-11)

A chronological record of every approach in this repository, what happened, and why the direction changed. Results are labeled **agent-observed**, **user-reported**, or **software-only** (tests/builds, not device evidence). For current scope see [README](../README.md) and [PROJECT_CONTEXT](../PROJECT_CONTEXT.md).

## 1. Original plan: eye-tracked region relocation (superseded)

Goal: track where the user looks (ARKit face `lookAtPoint`), let them **air-trace** an assumed blind region with a pinch, and move a blurred mask and a copied patch with their gaze. See [BUILD_PROMPTS](../BUILD_PROMPTS.md) (historical spec).

| Step | PRs / commits | Outcome |
|---|---|---|
| Preflight, signed app shell on the iPhone 15 Pro Max (iOS 27) | P0 merges `925b6b2`, `14fd2d2` | Built and launched on the phone (user-reported). |
| Capture pipeline: one ARSession, front face + Vision hand landmarks, rear world + face | #1 | Software tests pass. Black preview on the phone was traced to **Xcode Device Hub holding the camera**; closing it fixed the preview (user-reported). See [P1_CAPTURE](P1_CAPTURE.md). |
| Gaze core: personal 9-target affine calibration, timed held-out protocol, air-trace region core, placement planner | `phase-2-gaze-core`, `phase-3-region-placement-core` | 31 core tests (software-only). |
| Calibrated live gaze marker and calibration UI | #3 | Merged. |
| Flow package (`GazeShiftFlow`): same-frame hand+gaze pairing, comparison/composition planner, compositor shader; air map wired into the app | #2 (Anoop) | Merged; a duplicate calibration runner was removed in favor of #3. |
| Fail-closed safety, gaze axis and pose diagnostics | #6, #7, #13 | Merged. |
| **Physical gaze accuracy** | #4, #8, [rear blocker](P2_REAR_GAZE_BLOCKER.md), [front blocker](P2_FRONT_DIAGNOSTIC_BLOCKER.md), [off-screen diagnostics](P2_OFFSCREEN_DIAGNOSTICS.md) | **Failed both gates** (user-reported): front median ≈ 85 pt, rear ≈ 160 pt against a 54 pt limit; left/right weaker than up/down; predictions often off-screen. |
| Green-outline simulated blur following gaze; Original / Simulated blur / Simulated blur + copy | #5 (Anoop) | Merged. On the phone the blur never appeared, because no live gaze marker existed. |
| Front→rear region hand-off (setup ID no longer includes the capture generation) | #9 → #10 (Anoop) | Merged (#9 first landed on the wrong base; #10 carried it to main). |
| Demo unblockers: "Unvalidated gaze demo" toggle, position-free fixation in demo mode, on-screen **blur checklist**, edge-pinned off-screen gaze | #11, #12, #14 (Anoop) | Merged. The checklist showed the first failing gate was **"Live gaze dot outside the camera view"**, i.e. the calibration itself. |
| Fixed-position blur without gaze | #15 (Anoop) | **Closed.** Superseded by the manual pivot below. |

**Lesson:** front-camera ARKit gaze on this phone, at ~25–30 cm and handheld, was not accurate enough (tens to hundreds of points) to drive a screen-space mask. The safety-first design correctly refused to draw effects on bad gaze, which made the demo invisible.

## 2. Pivot: manual screen-fixed region, no eye tracking (current)

Decision: drop eye tracking; the region stays **fixed to the screen** where it was drawn. See README/PROJECT_CONTEXT.

| Step | PRs / commits | Outcome |
|---|---|---|
| Hand-only, screen-fixed air trace (pinch) | `ab5994c` | Installed build `1011.18.10`: **no line appeared** (user-reported). Pinch dropped. |
| **Index-finger-only** drawing with explicit Start drawing / Finish shape / Accept region | `c4ae504` | User reported it "looks pretty good" (user-reported, not recorded). |
| Full-width camera preview; presentation UI tried then reverted; visible copy arrows restored | `6d1847f`, `31e2ad8`, `f0dbf01` | Current layout. |
| **Upright camera in landscape** (orientation-aware ARKit transform and Vision orientation; 4:3 landscape layout) | #18 (Anoop) | Merged; build OK (software-only). |
| **Rear touchscreen drawing**: draw the region directly on the rear camera image | `5a405be` | Merged; physical verification pending. |

## 3. Open alternatives (not on main)

| PR | Idea | Status |
|---|---|---|
| #17 | **Tolerant index drawing** (Measure-style): skip single missed or low-confidence frames, clear only after >1 s loss; smoothing; loose auto-close | Open. Tests pass; awaiting a phone A/B test. |
| #16 | **Touch relocate** screen: circle on the rear view, copy appears at a rule-of-thirds point, drag it anywhere | Open. Largely overlaps the merged rear touchscreen drawing; keep only as a fallback. |

## Device and setup notes

- Device: Anoop's **iPhone 15 Pro Max, iOS 27.0**, built from Hussain's Mac (Personal Team signing). Anoop's Mac (macOS 27, Xcode 27.0) builds for the iOS Simulator; no simulator runtime is installed by choice (no camera there).
- Keep **Xcode Device Hub / mirroring closed** during camera tests.
- Rotating the phone is a layout change and resets an in-progress stroke or region; draw and demo in one orientation.
