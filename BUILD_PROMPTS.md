# GazeShift Incremental Build Prompt Pack

> **For agentic workers:** Use `superpowers:subagent-driven-development` to execute these prompts one at a time after implementation is requested. Use the Gang's write-path agent for file changes and independent Superpowers review before merging. This document prepares the work; it does not authorize starting the app by itself.

**Goal:** Record an iPhone 13 demonstration of camera-tracked air tracing followed by live eyes moving a copy of affected image content to an explicitly chosen display offset.

**Architecture:** Reconfigure the same ARKit session between two stages. Setup uses the front-camera image, face/eye estimates and Vision hand landmarks for air tracing. Live assist uses the rear scene plus front-derived face/eye estimates; recalibrated display gaze positions a user-reviewed approximate region and one translated rectangular copy from the original frame. Invalid tracking or placement returns to the original healthy scene with a visible status.

**Tech stack:** Swift, SwiftUI controls, ARKit, Vision `VNDetectHumanHandPoseRequest`, and one minimal native rendering path. Prefer an `MTKView` with Metal following Apple's camera-rendering example; reuse a suitable renderer if present. No second scene engine, cloud inference, new pretrained model, or backend.

**Spec:** [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) and the existing [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md). This pack expands that native plan into copyable work instructions. As of 2026-10-11 the repository contains documentation, not a working prototype.

## The decision: native ARKit first

Native is the better starting point for this experiment because Apple exposes the combined rear-camera/face-tracking configuration and eye-related estimates directly. It does **not** guarantee sufficiently accurate gaze on this phone or a successful six-hour build. The first device test decides that.

| Requirement | Native ARKit path | Website on the iPhone |
| --- | --- | --- |
| Air tracing during setup | `ARFaceTrackingConfiguration` supplies the front image; Vision detects index/thumb tips for a virtual 2D cursor | Separate browser hand model and camera compatibility work would be needed |
| Rear scene plus front-camera tracking | One `ARWorldTrackingConfiguration` with `userFaceTrackingEnabled`, when runtime support is confirmed | Simultaneous front/rear `getUserMedia` remains a device/browser question; historical WebKit issues make it risky |
| Eye information | `ARFaceAnchor.lookAtPoint` and eye transforms | RGB landmarks can be estimated with MediaPipe; ARKit/TrueDepth gaze is not exposed through ordinary browser APIs |
| Both raw camera videos | Combined ARKit supplies the selected rear image plus face anchors, not two raw video feeds | Must independently prove two genuinely live streams |
| Screen gaze | Personal calibration and held-out validation required | Personal calibration and held-out validation required |
| Deployment | Signed native build on the physical phone | HTTPS site; Vercel can host static files |
| Role in this plan | Main build | Optional companion page after the native demonstration |

The two stages are:

```text
SETUP: front image → Vision hand cursor → air-traced outline → reviewed ellipse
       face/eye estimates → setup gaze calibration → fixation check while tracing
SWITCH the same session; clear old data; recalibrate and validate live-mode gaze
LIVE: rear original image + live gaze + stored region → translated crop → display
```

Apple's existing tracking supplies estimates; **you do not need to train a new AI model**. Personal gaze calibration remains necessary in each camera configuration. Vision supplies 2D hand landmarks, not an ARKit finger API or a 3D pointing ray. The finger moves a virtual cursor; actual tracing is in the air, never silently replaced by touchscreen drawing.

For the smallest build, trace one closed outline and review a **bounding ellipse derived from its minimum/maximum coordinates**. This is an explicit approximation, not an inferred defect. Preserve its offset from the fixation reference. Live assist copies the rectangular original-image crop covering that ellipse to one user-chosen offset; it duplicates content and covers some destination content. It does not reconstruct normal vision. A required, clearly labeled Demo comparison shows Original / Simulated blur / Simulated blur + copy in the same full viewport. Simulation is off until selected; normal Live assist stays unblurred.

## Exact six-hour schedule

The 360-minute estimate is conditional on functioning Xcode, signing, device access, and available tools. The known unaccepted Xcode license must be resolved by the user. If setup happens during the event, it consumes the same six-hour window; it is not free extra time. Unsupported capture or unreliable gaze can also stop the build.

| Prompt | Build minutes | Deliverable and decision |
| --- | --- | --- |
| P0 — preflight | Before starting; record actual time | Ready Mac, trusted phone, signing and repository workflow; otherwise report setup blocker |
| P1 — both configurations | 0–30 | Prove front-image hand tracking plus face data, then rear image plus face data, on the same session |
| P2 — setup gaze | 30–90 | Front-mode calibration and held-out eye-only test; minute-90 go/no-go |
| P3 — air map and switch | 90–150 | Valid air trace, reviewed ellipse, camera switch, live-mode recalibration and validation; minute-150 go/no-go |
| P4 — patch relocation | 150–210 | One original-image crop follows gaze at the chosen offset, with placement and recovery checks |
| P5 — device verification | 210–300 | Recorded alignment, drift, performance and failure results; highest-impact fixes |
| P6 — evidence and handoff | 300–360 | Playable actual-device recording, honest pitch, review and final build status |

This optimistic budget now includes **90 minutes sensor/gaze + 60 minutes mapping/switch + 60 minutes relocation + 90 minutes testing + 60 minutes evidence**. Air gestures and a second gaze calibration increase the risk; six hours is not guaranteed. Do not add a second web build. At either failed gate, preserve the blocker. A labeled prerecorded scene is allowed for a rear-capture failure; live eyes and actual air tracing remain mandatory. Manual/scripted gaze is only for labeled debugging.

## How to use the prompts

Paste the master prompt once into the implementation chat, then paste P0 and each subsequent prompt when its prerequisite is satisfied. Every phase ends with a verified checkpoint and a short handoff. Stopping at that boundary prevents scope growth; it is not a request for fresh permission for every reversible edit. Never infer a hardware test result from silence.

If the coding agent cannot observe your physical iPhone, it must give a short on-phone checklist and record your result as **user-reported**. Evidence must be labeled **agent-observed**, **user-reported**, or **not tested**. Desktop, simulator and successful-build results cannot pass a physical-device gate. Independent work may continue while required device results are pending; dependent claims and implementation must wait.

### Master prompt — paste once

```text
You are helping me build GazeShift in the existing private repository:
https://github.com/Hussain-coder-eng/gazeshift
Local workspace: /Users/hussianaltufayli/Documents/Codex/2026-09-29/ai/gazeshift

Read README.md, PROJECT_CONTEXT.md, SIX_HOUR_PLAN.md and BUILD_PROMPTS.md.
Follow the applicable AGENTS.md and relevant Superpowers skills. The Gang
handles implementation: use a Codex write-path subagent on a feature branch;
use Explore/Plan/research agents for read-only work where useful. No app files
on main. Reuse the repo, existing dependencies and suitable native code.

Goal: actual air tracing followed by live gaze-driven patch relocation on an
iPhone 13. Use the SAME ARSession in two configurations, never two competing
capture sessions. Setup uses supported ARFaceTrackingConfiguration: front
ARFrame image for Vision hand tracking, face anchors for eye estimates. Live
assist uses supported ARWorldTrackingConfiguration.userFaceTrackingEnabled:
rear image plus face anchors, not a raw front-camera buffer. Verify both modes.
Clear old timestamps/anchors/cursors at a switch and recalibrate live-mode gaze.
Never replace eyes with head pose, finger position, target coordinates or fake
gaze. Air tracing is required; touch may operate Review/Redo and offset controls.

Map one continuous closed air outline while fixating a stationary reference.
Use a reviewed min/max bounding ellipse as an explicit approximation. Store its
display-coordinate center offset from fixation and radii, not a world anchor;
do not recenter its centroid onto gaze. In live assist, copy the rectangle
covering that region from the ORIGINAL frame to one explicit user-chosen offset.
Reject unavailable/out-of-bounds/overlapping placements; no auto-clamp or random
placement. Do not add a full-scene warp or generative reconstruction.

Keep a minimal native app. Prefer SwiftUI controls plus one MTKView/Metal
renderer, unless an existing simpler working renderer can be reused. Make
that choice once; no framework comparisons during the build. No accounts,
backend, frame uploads, cloud LLM per frame, object recognition, hardware
purchase, new pretrained-model training or clinical participant work.

lookAtPoint is a 3D face-coordinate estimate, not display pixels. Personal
calibration and held-out testing are required. Do not call camera projection
physical-screen calibration. Track the exact orientation, viewport, display
scale and phone-to-face setup. Recalibrate after geometry changes.

Use named configuration constants. Initial operational defaults are
MAX_SAMPLE_AGE_MS=250 and RECOVERY_VALID_SAMPLES=3. These are provisional
engineering choices, not clinical standards; document changes and reasons.
Reject nonfinite, missing, untracked or stale data immediately. isTracked
is transform validity, not gaze confidence. Derive explicit quality checks;
do not invent a confidence score the API does not provide.
Keep validation scoring separate from display rejection: finite off-screen
predictions still count toward accuracy error, even though the live view must
bypass them. Record missing/rejected samples against the full test window.

On gaze loss, clear the marker and disable the adaptive effect. If the scene
is healthy show it unchanged and show “Tracking unavailable — original view”.
Keep that message during loss; clear it and resume only after the required
fresh valid samples. If the scene itself stalls, show “Scene unavailable”
or “Paused”; never present a frozen frame as live. Stop/restart and interruption
handling must avoid competing sessions and stale relocated patches.

The user-drawn approximate region is assumed for this healthy-user demo, never
a measured or diagnosed blind spot. Fixating while tracing is required; following
the finger with the eyes invalidates the stroke. Clinical PRL offsets, boundaries
and separate per-eye maps are unknown; the phone shows one common image.
Do not claim diagnosis, restored sight, a cure, prescription replacement or
patient benefit. Healthy fixation calibration does not validate patient mapping.
Keep pose/distance stable; geometry changes require recalibration/remapping.
Normal live assist adds NO artificial blur. Implement the REQUIRED Demo comparison:
Original / Simulated blur / Simulated blur + copy in the SAME full viewport.
Label simulation clearly and keep it off until selected. Apply the assumed blur
LAST to both simulated variants of the same frame; copy original pixels first.
Simulated blur + copy MUST show LIVE calibrated gaze moving both the simulated
region and copied patch together, under the same loss/recovery rules. A labeled
frozen comparison is supplementary only; it cannot replace this live evidence.

Work only on the current phase. Keep responsibilities small: capture,
calibration and rendering; no generic architecture or future scaffolding.
Use typed interfaces and explicit boundary errors. For nontrivial coordinate,
fit, mapping or copy logic leave the smallest runnable check that detects a failure.
Run the affected checks/build before a checkpoint; a build cannot prove gaze.

After each phase: report exact changed files, commands/checks and results,
device evidence provenance, elapsed time, remaining risk and next gate;
commit on the feature branch and stop. Do not merge until an independent
Superpowers reviewer has reviewed the committed BASE/HEAD and all Critical
and Important findings are fixed and re-reviewed. Re-review orphaned branches.
Use the existing remote; no new repository or external messages.

If a device result is unavailable, provide its short physical-phone checklist
and wait for that result before dependent work. Never assume a pass after a
timeout. Do not accept the Xcode license or install Mac applications for me.
Report user-controlled setup actions clearly. Do not start P1 until P0 passes.
```

## P0 — preflight and scope lock

**Resources:** [Run an app on a physical device](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) explains signing and device launch. [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) covers the phone's user-controlled setup. [ARKit support and permission](https://developer.apple.com/documentation/arkit/verifying-device-support-and-user-permission) covers capability checks and camera permission. [Branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches) explains the review setting.

```text
Execute P0 only. Goal: prove this Mac and physical iPhone are ready for the
native build; do not call this a working gaze prototype.

Inputs: the master prompt, existing repository, iPhone 13 and available Xcode
tools. Inspect git status, branch, remote, existing files and applicable rules.
Preserve unrelated changes. Create/reuse a suitable feature branch; do not
create a second repo. State the current app status before touching code.

Check Xcode availability and its license status without accepting the license.
The user resolves license/account/trust/Developer Mode steps. Use existing
Apple development tools, preferably available Xcode tooling. Verify a signing
team and real-device run destination without printing secrets. Do not promise
the six-hour budget if any of this is unresolved. For read-only Git operations
blocked by the Xcode license, DEVELOPER_DIR=/Library/Developer/CommandLineTools
may be used if those tools already exist; this does not fix native-build setup.

Once setup is ready, create the smallest iOS app if none exists. Use a clear
camera-use description. Launch a minimal signed screen on the actual phone.
Choose a fixed supported orientation and a stable seated setup with consistent
lighting and viewing distance. Keep controls outside the measured render view.
Record the device/iOS, Xcode, orientation, viewport and actual setup duration.

Deliverable: minimal runnable app plus a concise preflight result. Check that
the launched binary is this build, not an old screenshot or simulator. Record
whether the result was agent-observed or user-reported; not tested is a blocker.
Inspect main branch protection and enable required PR reviews when available
under the existing repository permissions/plan. Preserve protections; if they
conflict with direct merge/push, use a PR through the rules. Report unavailable
protection; do not disable rules or purchase an upgrade to bypass a blocker.

Run the relevant minimal build check, commit only scoped changes, and stop.
Gate: P1 starts only after actual-device launch, signing and tooling pass.
```

## P1 — prove both configurations and the air cursor

**Resources:** [Face configuration](https://developer.apple.com/documentation/arkit/arfacetrackingconfiguration) supplies front imagery. [Combined tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) supplies the rear scene plus face anchors. [Camera selection](https://developer.apple.com/documentation/arkit/choosing-which-camera-feed-to-augment) distinguishes their outputs. [Apple's hand example](https://developer.apple.com/videos/play/wwdc2020/10653/) explains index/thumb gestures; [Vision with ARFrame](https://developer.apple.com/videos/play/wwdc2021/10039/) shows processing session imagery.

```text
Execute P1 only, minutes 0–30. Goal: prove the two camera configurations and
actual camera-tracked fingers on the physical iPhone, without parallel capture.

Inputs: passed P0 and minimal app. Check support for ARFaceTrackingConfiguration
and ARWorldTrackingConfiguration.supportsUserFaceTracking. Use ONE ARSession.
First run face configuration: its front ARFrame.capturedImage feeds Vision's
VNDetectHumanHandPoseRequest while ARFaceAnchor supplies face/eye estimates.
Detect index tip and thumb tip and draw a virtual 2D cursor. This is image-based
cursor control, not a 3D ray from a real finger to the screen.

Use one in-flight hand request, the newest available frame and no backlog.
Retain each image's timestamp/orientation with its result; discard stale or
superseded results. Use a named provisional MIN_HAND_JOINT_CONFIDENCE=0.5 and
MAX_HAND_AGE_MS=250; verify them on this phone. Require both tips. Show missing
hand/face states; do not fabricate a point when detection fails.

Define ONE tested transform from Vision image coordinates to the canonical
full-viewport display coordinates. Account for Vision's origin convention,
image orientation, aspect crop and deliberate front-preview mirroring exactly
once. Point at known display target locations and verify the virtual cursor's
left/right/top/bottom behavior; an attractive mirrored preview is not proof.
Prove fresh face/eye and finger data together for 30 seconds; moving fingers
must not obscure the eyes. This is sensor proof, not calibrated gaze accuracy.

Then reconfigure the SAME session to world tracking with userFaceTrackingEnabled
only if supported. Clear old image/hand/anchor timestamps and cursors; do not
reuse front results. Prove fresh rear images plus changing eye data together
for 30 seconds. The world configuration does not expose the raw front image.
Move a rear-scene object and test eyes with the head still. Return to face
configuration for P2; reset validity and wait for fresh data after each switch.

Deliverable: both configuration results and actual air-cursor proof, including
support flags/device/iOS and evidence provenance. Test permission denial,
missing face/hand, interruption and clean retry. Supply the short on-phone
checklist if the agent cannot observe; wait for results instead of assuming.

Run/build, commit and stop. Gate: front-mode simultaneous hand and eye signals
must pass. If rear capture alone fails, record it; an explicitly labeled local
recorded scene with live front-mode eyes is allowed. If hand or live eyes fail,
stop dependent work; do not substitute touch tracing, head pose or fake gaze.
```

## P2 — calibrate and validate real eye movement

**Resources:** [`lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint) defines the face-relative 3D estimate. [`leftEyeTransform`](https://developer.apple.com/documentation/arkit/arfaceanchor/lefteyetransform) and [`rightEyeTransform`](https://developer.apple.com/documentation/arkit/arfaceanchor/righteyetransform) describe eye coordinates. [`isTracked`](https://developer.apple.com/documentation/arkit/artrackable/istracked) concerns transform validity; [`blendShapes`](https://developer.apple.com/documentation/arkit/arfaceanchor/blendshapes) supplies expression coefficients for explicit blink checks. [PRL calibration research](https://pmc.ncbi.nlm.nih.gov/articles/PMC4201094/) explains why clinical interpretation needs separate work.

```text
Execute P2 only, minutes 30–90. Goal: a personal calibrated marker that responds
to live eyes on held-out physical-screen targets, including with the head still.

Inputs: P1's verified FRONT-mode session and full display. Calibrate in setup
mode; this fit cannot silently carry across the later camera switch. Document
the coordinate chain: face
coordinates -> eye-derived features -> calibrated view points -> normalized
render coordinates -> drawing-buffer pixels. Keep camera-image UV mapping
separate. lookAtPoint and a camera projectPoint result are not screen gaze.

Start with the smallest reasonable feature set: derive a face-relative gaze
direction from the midpoint of the eye positions toward lookAtPoint; use its
horizontal/vertical direction ratios when finite and safely away from a zero
denominator. Confirm the coordinate conventions against Apple documentation.
If this signal fails the eye-only check, investigate the existing eye transforms;
do not silently substitute head pose. Document the actual chosen features.

Fit separate small regularized linear mappings from [1, horizontal, vertical]
to view x/y points. Use a named regularization constant, normalize predictors,
and solve the tiny system with a stable existing/native numerical method.
Reject insufficient, singular or nonfinite calibration data explicitly. No
new machine-learning library or pretrained model training is needed.

Show nine targets at normalized x/y positions 0.15, 0.50 and 0.85 inside the
actual render view. Let the user fixate: ignore an initial 0.5-second settling
period and collect about 1 second of fresh valid samples per target. Repeat
invalid captures instead of fabricating samples. Labels are the displayed
target centers, never a pointer. Require a roughly still head, stable distance
and the selected orientation. Record sample counts and setup conditions.

Evaluate four novel positions at x/y positions 0.25 and 0.75, with two passes.
For every target/pass, allow 0.5 seconds to settle, then test for exactly 1 second
using 20 scheduled evaluation slots at 50 ms intervals. Each slot may consume
only one fresh sample captured inside that window with a previously unused
timestamp; missing, duplicate, stale, untracked, closed-eye or nonfinite samples
remain rejected slots. Do not extend a window until enough good samples arrive.

Count expected slots (20), received unique samples, valid finite predictions,
rejected slots and each rejection reason. Quality-eligible finite off-screen
predictions MUST remain in accuracy scoring before the live renderer rejects
them; never clamp or discard them to improve error statistics. Report aggregate
and per-target/pass errors in view points and viewport-diagonal percentage,
sample counts, valid fraction and rejected-sample distribution.

Predeclare the gate: every target/pass must have >=80% valid finite predictions
of its 20 scheduled slots and >=10 distinct prediction timestamps; missing or
insufficient windows fail. Median error must be <=10% and p90 <=20% of the
diagonal both overall and per target/pass, plus clear eye-only response. A rate
too low to meet coverage is a failed/not-passed gate, not permission to change
the schedule. These provisional engineering criteria are not medical accuracy;
do not lower coverage or accuracy requirements after seeing failures.

Interleave center once per pass as a repeat control; exclude it from novel-
position statistics because it was a training location. Report it separately.
Do not train on test samples or feed target position into live inference.

With the head still, look left/right/up/down and verify marker response. Then
hold fixation and move the head separately to expose sensitivity. Test held-out
edges too and show out-of-range predictions honestly. A marker following the
training targets during calibration does not pass. Repeat calibration once if
needed; if still poor, document the blocker instead of expanding the model.

Keep calibration tied to orientation, render-view geometry and viewing setup.
Invalidate it after orientation/layout changes; require a new calibration.
Allow explicit recalibration. Keep it in memory for this session; no profiles.
Use fresh tracked/finite data and the configured maximum age. Reject closed-eye
samples when either ARKit eye-blink coefficient reaches MAX_EYE_BLINK=0.6, a
provisional named threshold to verify on this phone. Reject unavailable eye
quality data and invalid/off-screen predictions from the live marker/copy;
retain quality-eligible finite off-screen predictions in test error scoring.
Do not clamp them into fake edge gaze. Expression coefficients are not gaze
confidence scores.
Any smoothing must be light and measured; it adds delay and cannot fix bias.

Deliverable: calibrated marker, minimal runnable fit/coordinate checks and
held-out test record with evidence provenance. Check synthetic known mappings,
degenerate inputs, orientation/crop/scale assumptions and finite output. Check
that missing target windows fail and finite off-screen errors remain scored.
Run/build, commit and stop. Minute-90 gate: only live eye-only response plus
the predeclared held-out criteria allow air mapping to proceed. This same
protocol must pass again for live-mode gaze after the configuration switch.
```

## P3 — air-trace, review the region, and switch modes

**Resources:** [Vision hand-pose guide](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision), [request API](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest) and [Apple's pinch example](https://developer.apple.com/videos/play/wwdc2020/10653/) support gesture capture. [ARKit configurations](https://developer.apple.com/documentation/arkit/configuration-objects) and [reset tracking](https://developer.apple.com/documentation/arkit/arsession/runoptions/resettracking) explain the mode transition. [Fixation and mapping research](https://pmc.ncbi.nlm.nih.gov/articles/PMC7937995/) explains why a trace is not a clinical retinal map.

```text
Execute P3 only, minutes 90–150. Goal: one camera-tracked air outline, one
explicitly reviewed approximate ellipse, and a separately validated live mode.

Inputs: passed front-mode P2 and P1's timestamped Vision cursor. Use the SAME
canonical full-viewport coordinates for finger cursor, fixation and gaze. Show
one fixed high-contrast fixation reference. The user must keep looking there,
not follow the finger. This healthy-user demo traces an explicitly assumed
region; do not ask a patient to self-diagnose a defect.

Use index/thumb pinch to begin a stroke, hold while tracing one closed outline,
return near the start and release to finish. Reuse Apple's simple gesture
pattern with named close/release thresholds and hysteresis verified on-device.
Touch Review/Redo controls are allowed; actual tracing must stay in the air.
Require fresh confident hand points and valid gaze near the fixed reference:
start with FIXATION_RADIUS_FRACTION=0.10 of the viewport diagonal, explicitly
provisional. This detects gross drift, not clinically precise fixation.
Pair each hand result with gaze from its captured ARFrame timestamp, not an
unrelated current gaze sample; an unavailable/stale pair cannot enter the trace.

If fixation drifts, hand/eye confidence fails, data becomes stale, or the face
is occluded, invalidate the entire active stroke and require Redo. Never bridge
unknown points or join across an interruption. Validate finite in-viewport
points, MIN_STROKE_SAMPLES=20 distinct samples, nonzero width/height and endpoint
closure within CLOSURE_RADIUS_FRACTION=0.03 of the diagonal. These named defaults
are provisional; show a rejected stroke and its reason. Do not
auto-invent missing boundaries. Keep the raw stroke only in session memory.

Derive ONE bounding ellipse from the accepted stroke's x/y minimum and maximum.
Overlay raw trace and ellipse for Review; state that irregular shape details
are approximated. Require explicit user acceptance before Live assist. Store
ellipse center minus FIXATION REFERENCE, its radii, and setup orientation,
viewport/display scale, pose/distance assumptions, camera mode and eye-state
metadata. Use normalized full-display coordinates with point conversion for
metrics. Never recenter onto the trace centroid or gaze; preserve the traced
region's offset from fixation. This is a user-drawn approximate region, not a
measured scotoma, PRL calibration or separate clinical map for each eye.

Switch the SAME session to supported world+user-face tracking. Clear prior
anchors, timestamps, cursor, calibration-valid flag and pending Vision results.
Stop hand inference; the new captured image is rear-facing. Prove fresh source
frames and eye data. Keep the accepted display-relative ellipse, not a world
anchor. REFIT gaze calibration in this mode and repeat ALL P2 held-out windows,
coverage and per-target/pass error gates. Front-mode success is not a live-mode
pass. If geometry/distance changes, invalidate calibration AND the region and
repeat setup. Do not claim the normalized shape fixes changes in visual angle.

If rear capture is the documented blocker, remain in the supported front mode
and display local prerecorded content labeled “Recorded scene / live gaze”.
Validate gaze in this actual final display layout too. This is not live-world
capture. No second ARKit/AVFoundation session and no silent touchscreen fallback.

Deliverable: real air-trace evidence, accepted approximation, and final-mode
calibration report. Check mirrored/y-flipped targets, fixation drift, occlusion,
incomplete stroke, restart, stored offset and fresh data after switching. Leave
one runnable check for coordinate/ellipse math and invalid inputs. Run/build,
commit and stop. Minute-150 gate: accepted air map AND passing final-mode gaze
are required before relocation; otherwise report the blocker and stop.
```

## P4 — relocate one original-image patch and recover safely

**Resources:** [ARKit Metal rendering](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal) supports the camera-to-display path. [P2](#p2--calibrate-and-validate-real-eye-movement) defines gaze validation; [P3](#p3--air-trace-review-the-region-and-switch-modes) defines the accepted region. [Remapping research](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/) motivates an experiment, not patient benefit.

```text
Execute P4 only, minutes 150–210. Goal: one local rectangular copy of original
scene content at a user-chosen offset, driven by validated live gaze.

Inputs: P3's accepted ellipse, final-mode calibrated gaze and fresh scene.
For gaze g, affected ellipse R has center g + stored fixation-relative offset
and the stored radii. Take its enclosing rectangle from the ORIGINAL current
camera frame, using the tested display-to-camera orientation/crop transform.
Translate that rectangle by one explicit user-chosen display offset delta.
Keep the original scene underneath and composite the copy at the destination.
Never sample a previous composited output or blurred/masked pixels. This is
local pixel copying, not generative fill or a perfect full-scene correction.
It duplicates source content and covers existing content at the destination.

Require the entire source crop and destination rectangle to fit valid viewport
AND camera sampling bounds. Reject unavailable/partial source pixels rather
than clamping them or inventing content at a gaze-shifted screen edge.
The entire destination must be outside the assumed affected region plus a
named safety gap tied to measured LIVE-mode p90 gaze error. A conservative
rectangle-overlap test against the region's expanded bounding box is sufficient;
record that simplification. User chooses a single offset using visible controls;
never auto-clamp, shrink, randomly jump or search for a new placement. If the
chosen offset cannot fit without overlap, show “No valid placement — original
view” and bypass the copy. Measured error is uncertain, so this margin is only
an engineering guard, not proof that destination pixels are clinically usable.

Use one existing renderer and bounded latest-frame/sample handoff, not another
engine. Provide Start/Stop, Setup/Redo, Original/Relocated and offset controls.
Full-viewport live assist adds NO artificial blur. Keep the region outline as
an optional clearly labeled approximation, not a blacked-out assistance area.
Both source and destination move with gaze: looking toward copied content may
make it move again. State that this is a peripheral-viewing experiment; do not
claim it solves that gaze-chasing behavior or provides normal vision.

Implement the REQUIRED Demo comparison with Original / Simulated blur /
Simulated blur + copy using the SAME source frame, mask and full-viewport geometry.
It may stay off until selected but cannot be cut from the deliverable. Build the copy
from original pixels FIRST, then apply the identical simulated blur LAST to
both simulated variants. Never copy already blurred source pixels. The mask
is an illustration, not exact patient vision. Simulated blur + copy MUST run
live: calibrated eye movement moves both the simulated region and relocated
patch together in the same full viewport. Apply the same gaze/source validity
and loss/recovery rules to both effects; invalid gaze clears blur and copy to
the healthy original view. No side-by-side layout is required. A labeled frozen
before/after comparison is supplementary only and cannot replace live gaze-
contingent blur evidence. Keep identical full-viewport geometry across views.

On missing, untracked, stale, blinking or invalid/off-screen gaze, clear the
marker and copy immediately. Keep “Tracking unavailable — original view” while
showing the healthy original source. Resume only after three fresh valid samples
with distinct timestamps; a persistent no-placement condition still bypasses.
Retain finite off-screen predictions for validation scoring before live rejection.
Track scene freshness separately: a stalled source shows “Scene unavailable”
or “Paused”, not a frozen image labeled live. Stop/retry/background/switching
must clear stale state and enforce calibration/region validity before resuming.

Deliverable: one copy compositor and observed live-eye relocation/loss/recovery.
Leave minimal runnable checks: asymmetric fixation-offset preservation; finite
coordinates; source-before-blur/output; overlap/out-of-bounds rejection; disabled
copy equals original; camera mirroring/y-flip; invalid gaze bypass. On the phone
verify a distinctive source object is copied intact, Original removes the copy,
eye-only motion moves it, invalid placement bypasses, and recovery is visible.
Run/build, commit and stop. Gate: no stale copy, recursive sampling, hidden source
failure or unsupported claim may remain in the normal demonstration flow.
```

## P5 — measure, challenge and fix the device demo

**Resources:** [ARKit Metal rendering](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal) supports frame/display debugging. [Remapping stability research](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/) provides context for movement/adaptation limitations. [PRL calibration research](https://pmc.ncbi.nlm.nih.gov/articles/PMC4201094/) prevents treating healthy fixation results as patient validation.

```text
Execute P5 only, minutes 210–300. Goal: a factual device test record and fixes
for the failures that most affect the controlled demonstration.

Inputs: P4's current build, declared calibration criteria and operational
constants. Freeze features. Add a compact debug overlay only if necessary.
Measure capture FPS, gaze-sample/update rate, render FPS, processing time and
sample age using actual timestamps. Name each metric correctly. Sample age
is not end-to-end latency; use a synchronized external observation if claiming
that. Do not manufacture missing timings or report simulator metrics as phone
performance. Record device/iOS, orientation, viewport, lighting and distance.

Repeat P2's four held-out positions with the same fixed windows, coverage and
per-target/pass accuracy gates, including a later pass to expose drift. Report
expected/received/valid/rejected counts, reasons, valid fractions and errors
in points/viewport percent, aggregate and per target/pass. Retain finite
off-screen errors before display rejection. Keep center repeats and additional
edge probes separate from the four-position statistics. Report failures and
calibration duration; never omit insufficient windows. Separate eye-only
motion with a still head from head movement with fixed fixation. Note eyeglass,
lighting, blinking and distance effects only if actually tested. Do not claim
general reliability from one person's successful seated run.

Challenge orientation/layout changes, display scale/crop, off-screen estimates,
invalid numeric inputs, stale timestamps, obscured face, looking away, camera
permission denial, background/resume and repeated Start/Stop. Verify disabled
relocation matches Original. Retest hand/face occlusion, broken stroke rejection,
fixation drift, reviewed offset preservation, camera switch/recalibration and
placement rejection. Test all three required Demo comparison views, identical
viewport/mask/frame, source-before-blur and blur-last ordering.
Verify LIVE eye-only movement drives simulated blur and copy together, and
both clear/recover under the same tracking rules. Static comparison cannot pass.
For every gaze-loss case check cleared marker,
disabled effect, original healthy source, persistent warning and valid recovery.
For a source failure check visible Scene unavailable/Paused, not frozen “live”.

Maintain one small meaningful runnable check for pure calibration/coordinate/
map/copy math; avoid test suites that merely restate implementation. Run it plus
the affected build after each fix. Obtain focused independent review of risky
coordinate, validity or shader changes when useful; fix Critical/Important
findings. Do not broaden testing after resolved concerns without a reason.

Deliverable: a concise test record in the repository, actual evidence references,
updated build and explicit pass/fail/not-tested rows. Mark agent-observed versus
user-reported device results. Prioritize the highest-impact defect, rerun its
specific test, then stop adding features. Commit and stop. Gate: only observed
working behavior may appear in the final demonstration claim; unresolved gaze
or source limitations must remain visible in the recording and pitch.
```

## P6 — record evidence, review and hand off

**Resources:** [iPhone screen recording](https://support.apple.com/guide/iphone/take-a-screen-recording-iph52f6e1987/ios) is the simplest recording route. [Protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches) governs the final integration. The [existing project boundaries](PROJECT_CONTEXT.md#what-counts-as-evidence) define the claims the pitch may make.

```text
Execute P6 only, minutes 300–360. Goal: preserve a playable recording of the
actual device demonstration and finish a reviewed, honestly described build.

Inputs: P5's tested checkpoint and limitations. Freeze features; fix only
faults that prevent recording. Use iOS screen recording first. Add a short
external view showing the person's hand, eyes and phone when possible, so air
tracing and eye-only motion can be judged; markers alone cannot prove inputs.
Do not spend the final hour building a custom codec/recording system.

Record a concise sequence: fixed-reference air tracing, rejected drift/occlusion
or Redo, explicit ellipse review, camera switch and live-mode calibration result,
held-out eye-only response with head still, Original/Relocated comparison,
chosen offset, invalid-placement bypass, gaze loss to original and recovery.
Record the required Original / Simulated blur / Simulated blur + copy comparison;
show LIVE eyes moving the simulated region and patch together plus their loss/
recovery. Label simulation and any supplementary frozen frame; frozen evidence
cannot replace the required live gaze-contingent blur demonstration.
Include source failure/retry if it was material. Keep “Recorded scene / live
gaze” visible if that fallback is used and “Simulated region” where relevant.
Do not use synthetic/regenerated media to improve evidence or replace failures.

Open the saved recording and verify playback, duration and visible behavior.
Record the actual file location and its device/build/commit relationship. Keep
large videos and signing material out of Git; only publish personal footage
where the user has authorized it. A screenshot, app build or claimed recording
is not a verified playable file. Record missing external-hand/eye evidence honestly.

Write a short pitch using only observed outcomes: the problem, this native
technical experiment, what was demonstrated, its limits, and the next test.
State that the transformation changes the displayed phone image and uses an
user-drawn approximate region and duplicate/occlusion/gaze-chasing limits. No
patient efficacy, restored sight, prescription
replacement or confirmed partner/participant access. Future validation should
compare with ordinary magnification and address PRL/scotoma calibration.

Run the final relevant checks/build and commit scoped changes. Obtain BASE_SHA
from git merge-base main HEAD and HEAD_SHA from git rev-parse HEAD. Dispatch
an independent superpowers:code-reviewer with the SHAs, spec, test record and
known limits. Fix all Critical/Important findings on the branch, rerun affected
checks, commit and re-review. Review must cover the actual final commit.

After review passes, integrate using the repository's required merge/PR path
and push through existing protections; never weaken protection to force a
direct push. If the standard reviewed local merge is permitted, follow the
AGENTS.md merge/push workflow. Confirm remote state and identify the final
commit. Attach any created PR to this chat. Do not claim a push/merge happened
unless its result is verified.

Deliverable: verified recording location, final commit/review/integration
status, build instructions, measured results and remaining gates. If minute
360 arrives with required blur comparison, recording, tests, review or integration unfinished,
report that exact remaining work. Do not label it fully complete. Stop here;
no website, new model, wearable build or extra features in this phase.
```

## Optional companion website, after the native evidence

Vercel can host a project page with the pitch, limitations and an authorized demo recording. It cannot turn a website into an ARKit app. A private GitHub repository does not automatically make a deployed site private. Check available [deployment protection](https://vercel.com/docs/deployment-protection) and the distinction between [preview and production](https://vercel.com/docs/deployments/environments) before sharing anything.

```text
Optional separate task, only after I request the companion site: use the existing
repository and verified native demonstration to create a minimal Vite page for
Vercel. Reuse existing tooling; include the concept, playable authorized video,
measured results and clear limits. No browser gaze implementation, accounts or
backend. No fabricated performance or clinical claims. Inspect existing Vercel
access/protection, state whether the proposed URL is public or protected and
preserve protections. Do not upload personal footage without authorization.
Build and locally verify the page and video playback, obtain independent review,
then use the already authorized deployment path. Verify the actual deployed
URL and playback; a successful build is not a verified deployment.
```

Use [Vite's guide](https://vite.dev/guide/) for the small site, [Vite static deployment](https://vite.dev/guide/static-deploy.html) for the output/build contract, and [Vercel's Vite guide](https://vercel.com/docs/frameworks/frontend/vite) for hosting. This is a later presentation task, not a prerequisite for the native experiment.

## Resource catalog and what each resource contributes

The linked Apple resources are for the **native path**, not browser capabilities. Read the relevant phase's links when implementing it; do not spend the build window surveying everything below.

| Resource | Why and how to use it |
| --- | --- |
| [Vision hand-pose guide](https://developer.apple.com/documentation/vision/detecting-hand-poses-with-vision), [hand request](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest), [pinch example](https://developer.apple.com/videos/play/wwdc2020/10653/), [Vision with ARFrame](https://developer.apple.com/videos/play/wwdc2021/10039/) | Native pretrained hand landmarks for front-image air cursor control; no model training, touchscreen substitution or invented 3D pointing ray. |
| [Face configuration](https://developer.apple.com/documentation/arkit/arfacetrackingconfiguration), [configuration objects](https://developer.apple.com/documentation/arkit/configuration-objects), [reset tracking](https://developer.apple.com/documentation/arkit/arsession/runoptions/resettracking) | Setup front imagery and controlled reconfiguration of the same session; clear old data and validate gaze after switching. |
| [Fixation and mapping limitations](https://pmc.ncbi.nlm.nih.gov/articles/PMC7937995/) | Explains why fixation, uncertain boundaries and binocular conditions limit a user-drawn approximation; it does not validate this app. |
| [Apple combined tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) | Start here for one world-tracking session with face tracking enabled; still check runtime support on the phone. |
| [Camera feed selection](https://developer.apple.com/documentation/arkit/choosing-which-camera-feed-to-augment) | Distinguishes the selected rear scene from front-derived face anchors; prevents assuming both raw camera buffers exist. |
| [lookAtPoint](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint), [left eye](https://developer.apple.com/documentation/arkit/arfaceanchor/lefteyetransform), [right eye](https://developer.apple.com/documentation/arkit/arfaceanchor/righteyetransform) | Defines the 3D eye signals and coordinate conventions used as calibration inputs. They are not calibrated display pixels. |
| [Tracked state](https://developer.apple.com/documentation/arkit/artrackable/istracked) | Read before defining validity; tracking a transform does not provide a probability that the screen gaze is accurate. |
| [ARKit Metal display](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal) | Reference for rendering captured camera imagery and coordinate/display conversion in one native path. |
| [Device run](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [ARKit permission](https://developer.apple.com/documentation/arkit/verifying-device-support-and-user-permission) | Resolves actual launch, phone setup and permission prerequisites; simulator operation does not test these sensors. |
| [AVCaptureMultiCamSession](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession) and [MultiCam sample](https://developer.apple.com/documentation/avfoundation/avmulticampip-capturing-from-multiple-cameras) | A separate future route if both raw camera videos become necessary. It does not supply gaze and must not be bolted onto a competing ARKit capture session. |
| [PRL calibration](https://pmc.ncbi.nlm.nih.gov/articles/PMC4201094/) and [video calibration research](https://pmc.ncbi.nlm.nih.gov/articles/PMC5714047/) | Background on fixation/retinal-reference problems. Do not equate a healthy user's target fit with a patient's blind-spot or PRL map. |
| [Simulated image remapping](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/) and [stability limitations](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/) | Motivation and constraints for an experiment; neither establishes this prototype's clinical benefit. |
| [MediaPipe Face Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/web_js) and [official web example](https://github.com/google-ai-edge/mediapipe-samples/blob/main/examples/face_landmarker/js/README.md) | Optional future browser research: pretrained RGB facial landmarks, including eye/iris geometry, with optional blendshapes/transforms. It is not a ready-made calibrated screen-gaze estimator. The example's iOS compatibility statement is not an iPhone performance guarantee. Pin SDK/model versions, verify model licenses and self-host runtime/model assets if revisited. |
| [MediaPipe Iris limitations](https://chuoling.github.io/mediapipe/solutions/iris.html) | Explicitly separates iris tracking from inferring where someone looks. Landmark count alone cannot pass the eye-only screen-gaze gate. |
| [WebKit dual-camera issue](https://bugs.webkit.org/show_bug.cgi?id=264288) | Historical iOS camera-concurrency risk, not proof of the latest phone/browser behavior. Any browser attempt must test both stream orders, independent lens obstruction and sustained fresh frames on the actual phone before claiming dual capture. |
| [getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia) and [enumerateDevices](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/enumerateDevices) | Browser HTTPS/permission/device-selection references only. Opening camera B can affect A; switching or duplicating a stream is not simultaneous front/rear capture. |
| [WebGazer](https://webgazer.cs.brown.edu/) and [its README](https://github.com/brownhci/WebGazer/blob/master/README.md) | Optional research comparison, not a required dependency. Official maintenance ended February 24, 2026; review its GPLv3/commercial licensing terms before reuse. It does not remove personal calibration or device validation. |
| [Vite](https://vite.dev/guide/), [Vercel Vite hosting](https://vercel.com/docs/frameworks/frontend/vite), [deployment protection](https://vercel.com/docs/deployment-protection) | Only for a later companion page. Hosting files is distinct from running native tracking or keeping a deployment private. |

The successful six-hour outcome is narrow: a verified technical demonstration on this phone, with measured limitations and real recording evidence. Retinal mapping, patient benefit, wearable hardware, bilateral viewing, adaptation and startup validation remain separate work.
