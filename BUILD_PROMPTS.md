# GazeShift Incremental Build Prompt Pack

> **For agentic workers:** Use `superpowers:subagent-driven-development` to execute these prompts one at a time after implementation is requested. Use the Gang's write-path agent for file changes and independent Superpowers review before merging. This document prepares the work; it does not authorize starting the app by itself.

**Goal:** Record an actual iPhone 13 demonstration in which live eye movement drives one experimental transformation of the displayed scene.

**Architecture:** One native ARKit session supplies the rear-camera image and front-camera face/eye estimates. Personal calibration maps eye-derived features into physical display coordinates. One local image warp follows the calibrated gaze; invalid tracking returns to the original healthy scene with a visible status.

**Tech stack:** Swift, SwiftUI for a small control surface, ARKit, and one minimal native rendering path. Prefer an `MTKView` with Metal following Apple's camera-rendering example; reuse a suitable renderer if one already exists. No second scene engine, cloud inference, new pretrained model, or backend.

**Spec:** [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) and the existing [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md). This pack expands that native plan into copyable work instructions. As of 2026-10-11 the repository contains documentation, not a working prototype.

## The decision: native ARKit first

Native is the better starting point for this experiment because Apple exposes the combined rear-camera/face-tracking configuration and eye-related estimates directly. It does **not** guarantee sufficiently accurate gaze on this phone or a successful six-hour build. The first device test decides that.

| Requirement | Native ARKit path | Website on the iPhone |
| --- | --- | --- |
| Rear scene plus front-camera tracking | One `ARWorldTrackingConfiguration` with `userFaceTrackingEnabled`, when runtime support is confirmed | Simultaneous front/rear `getUserMedia` remains a device/browser question; historical WebKit issues make it risky |
| Eye information | `ARFaceAnchor.lookAtPoint` and eye transforms | RGB landmarks can be estimated with MediaPipe; ARKit/TrueDepth gaze is not exposed through ordinary browser APIs |
| Both raw camera videos | Combined ARKit supplies the selected rear image plus face anchors, not two raw video feeds | Must independently prove two genuinely live streams |
| Screen gaze | Personal calibration and held-out validation required | Personal calibration and held-out validation required |
| Deployment | Signed native build on the physical phone | HTTPS site; Vercel can host static files |
| Role in this plan | Main build | Optional companion page after the native demonstration |

The intended native pipeline is:

```text
Rear ARFrame.capturedImage ────────────────────────┐
                                                ▼
Front face/eye estimates → personal calibration → one local warp → phone display
                          physical screen gaze
```

Apple's existing tracking supplies estimates; **you do not need to train a new AI model**. Fitting a small personal calibration is still necessary. A coding assistant helps write and debug the app; it is not part of the live image-processing loop. A raw dual-camera capture framework alone does not supply gaze.

## Exact six-hour schedule

The 360-minute estimate is conditional on functioning Xcode, signing, device access, and available tools. The known unaccepted Xcode license must be resolved by the user. If setup happens during the event, it consumes the same six-hour window; it is not free extra time. Unsupported capture or unreliable gaze can also stop the build.

| Prompt | Build minutes | Deliverable and decision |
| --- | --- | --- |
| P0 — preflight | Before starting; record actual time | Ready Mac, trusted phone, signing and repository workflow; otherwise report setup blocker |
| P1 — combined sensor proof | 0–30 | Physical iPhone shows a fresh rear scene and fresh tracked face/eye data simultaneously |
| P2 — calibrated live gaze | 30–90 | Personal calibration, held-out eye-only test, explicit go/no-go at minute 90 |
| P3 — one warp | 90–150 | One mathematically bounded image transformation with a zero-strength identity check |
| P4 — live integration | 150–210 | Warp follows measured gaze; controls, tracking loss, scene failure and recovery work |
| P5 — device verification | 210–300 | Recorded alignment, drift, performance and failure results; highest-impact fixes |
| P6 — evidence and handoff | 300–360 | Playable actual-device recording, honest pitch, review and final build status |

This preserves the original plan's **90 minutes tracking + 120 minutes warp + 90 minutes testing + 60 minutes evidence**. Do one path well; do not attempt a second complete web build inside the same six hours. At a missed gate, preserve the work and state the blocker. A clearly labeled prerecorded scene is allowed if rear capture is the only problem; live eyes remain mandatory. Manual or scripted gaze is useful only for labeled renderer debugging, never a passed demonstration.

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

Goal: an actual iPhone 13 demo where live eyes drive one local image warp.
Use one supported ARWorldTrackingConfiguration with userFaceTrackingEnabled.
The rear ARFrame image is the scene; ARFaceAnchor supplies eye information.
Do not start competing ARKit and AVFoundation sessions. Two raw camera feeds
are not required. Never replace eyes with head pose, cursor position, target
coordinates, prerecorded gaze or an animated marker.

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

On gaze loss, clear the marker and disable the adaptive effect. If the scene
is healthy show it unchanged and show “Tracking unavailable — original view”.
Keep that message during loss; clear it and resume only after the required
fresh valid samples. If the scene itself stalls, show “Scene unavailable”
or “Paused”; never present a frozen frame as live. Stop/restart and interruption
handling must avoid competing sessions and stale active warps.

The adjustable region is assumed/simulated, never a measured blind spot.
Do not claim diagnosis, restored sight, a cure, prescription replacement or
patient benefit. Healthy fixation calibration does not validate calibration
for central vision loss or a person's preferred retinal locus (PRL).

Work only on the current phase. Keep responsibilities small: capture,
calibration and rendering; no generic architecture or future scaffolding.
Use typed interfaces and explicit boundary errors. For nontrivial coordinate,
fit or warp logic leave the smallest runnable check that detects a failure.
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

## P1 — prove combined capture on the phone

**Resources:** [Combined face and world tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) is the session pattern. [Choosing the camera feed](https://developer.apple.com/documentation/arkit/choosing-which-camera-feed-to-augment) explains why the captured image and face anchors are different outputs. [Metal camera rendering](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal) provides the native display reference.

```text
Execute P1 only, minutes 0–30. Goal: prove simultaneous rear-scene frames and
front-camera face/eye updates on the physical iPhone 13.

Inputs: passed P0 and the minimal native app. Inspect existing capture/render
code before editing. Add a single ARSession. Check ARWorldTrackingConfiguration
support and supportsUserFaceTracking; enable userFaceTrackingEnabled only when
supported. Show an explicit unsupported/permission error if checks fail.

Display ARFrame.capturedImage as the rear scene using one native rendering
path. Use actual orientation, view size and ARFrame.displayTransform for image
mapping. Read face anchors and eye information from this same session. Do not
start a second camera session or require a front-camera raw preview. Use small
debug text for frame/update timestamps, tracked state and valid-data counts.
No estimated accuracy or invented gaze-confidence number.

On-phone check: move an object in front of the rear camera while keeping the
face visible to the front camera. Then move the eyes with the head still.
Observe fresh rear image updates and changing eye estimates together for at
least 30 seconds. Briefly obscure the face, restore it and verify the changes
are real. Distinguish head/anchor changes from eye-related values. This is a
sensor proof, not yet proof of screen gaze. Do not pretend a raw front feed
is available simply because face anchors exist.

Deliverable: live rear preview plus diagnostic evidence of simultaneous eye
data, and a short result with support flags/device/iOS. Check camera denial,
no-face state, session interruption and retry without duplicate sessions.
If the agent cannot observe the phone, supply this checklist and await the
user's result. Label the evidence source; desktop success cannot pass.

Build/run the affected path, commit and stop. Gate: proceed to P2 only if live
eye data is demonstrated. If rear input alone fails, document it and plan the
allowed local recorded-scene fallback while retaining live native eye data.
If eye data fails, stop the dependent build and preserve the failure evidence.
```

## P2 — calibrate and validate real eye movement

**Resources:** [`lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint) defines the face-relative 3D estimate. [`leftEyeTransform`](https://developer.apple.com/documentation/arkit/arfaceanchor/lefteyetransform) and [`rightEyeTransform`](https://developer.apple.com/documentation/arkit/arfaceanchor/righteyetransform) describe eye coordinates. [`isTracked`](https://developer.apple.com/documentation/arkit/artrackable/istracked) concerns transform validity. [PRL calibration research](https://pmc.ncbi.nlm.nih.gov/articles/PMC4201094/) explains why clinical interpretation needs separate work.

```text
Execute P2 only, minutes 30–90. Goal: a personal calibrated marker that responds
to live eyes on held-out physical-screen targets, including with the head still.

Inputs: P1's verified session and display. Document the coordinate chain: face
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

Evaluate on separate, interleaved targets at x/y positions 0.25 and 0.75 plus
center, with two passes. Do not train on these samples or feed target position
into live inference. Calculate errors in view points and as a percentage of
the viewport diagonal; report valid sample count, median and 90th percentile.
Declare the demo gate before collecting results: median <=10% and p90 <=20%
of the diagonal, plus clear eye-only directional response. These permissive
engineering thresholds are provisional demo criteria, not medical accuracy.
Do not relax them after seeing failures just to label the phase successful.

With the head still, look left/right/up/down and verify marker response. Then
hold fixation and move the head separately to expose sensitivity. Test held-out
edges too and show out-of-range predictions honestly. A marker following the
training targets during calibration does not pass. Repeat calibration once if
needed; if still poor, document the blocker instead of expanding the model.

Keep calibration tied to orientation, render-view geometry and viewing setup.
Invalidate it after orientation/layout changes; require a new calibration.
Allow explicit recalibration. Keep it in memory for this session; no profiles.
Use fresh tracked/finite data and the configured maximum age. Use available
blink/eye-openness evidence to reject closed-eye samples with a named threshold
verified on this phone; those coefficients are not gaze-confidence scores.
Any smoothing must be light and measured; it adds delay and cannot fix bias.

Deliverable: calibrated marker, minimal runnable fit/coordinate checks and
held-out test record with evidence provenance. Check synthetic known mappings,
degenerate inputs, orientation/crop/scale assumptions and finite output.
Run/build, commit and stop. Minute-90 gate: only live eye-only response plus
the predeclared held-out criteria allow the gaze-controlled warp to proceed.
```

## P3 — build one bounded experimental warp

**Resources:** [Metal with ARKit](https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal) anchors the rendering path. [Image-remapping research](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/) motivates an experiment, not patient efficacy. Keep [P2](#p2--calibrate-and-validate-real-eye-movement)'s coordinate definitions authoritative.

```text
Execute P3 only, minutes 90–150. Goal: one local image warp, tested independently
of noisy gaze before connection to the live signal. P2 must have passed.

Inputs: the working original scene renderer and the calibrated coordinate
contract. Use the existing renderer; add one small shader/kernel, not another
scene engine or renderer abstraction. Keep a developer-only fixed-center test
mode clearly labeled as simulated gaze; it is not demonstration evidence.

Implement one bounded radial displacement by inverse sampling in display
coordinates. Define an adjustable center, radius and strength. Work in an
isotropic metric such as display points so the region stays circular on a
non-square view. For output point p, center c, radius R and strength s in [0,1],
let d=p-c and q=length(d)/R. Inside R use source point
c + d * (1 - s * (1-q)^2); outside R use p. This is an exploratory outward
remapping of source content inside a local region, not a calibrated correction
or a claim to move every feature outside a blind spot. R must be positive.

Apply the display-to-camera mapping after computing the sampled display point.
Respect the original preview's orientation/crop. At strength zero, use exactly
the original sampling path. Handle image boundaries deliberately, using a
documented clamp/border policy; prevent NaNs, holes and out-of-bounds access.
An optional blind-spot mask belongs only in a labeled observer simulation mode,
off by default. Do not blank the normal demo's center or apply the mask twice.
Label it “Simulated region”; it is not a retinal measurement.

Deliverable: one shader plus controls for radius/strength and original view.
Leave a tiny runnable CPU-side reference check for the coordinate math: zero
strength is identity; center is finite; radius boundary is identity; interior
samples remain finite; off-screen centers and non-square view dimensions are
handled; invalid radius is rejected. Compare test points against the shader's
behavior. Check a visual grid on the actual phone for stretch/crop/mirroring.

Use named initial parameters and record them; do not invent clinical units.
Run the math check and device rendering check, commit and stop. Gate: P4 begins
only after the original path and one bounded warp render correctly. If the
warp lacks useful appearance, adjust this one transform; do not add a menu of
algorithms or claim its clinical value.
```

## P4 — connect live gaze and safe recovery

**Resources:** [Combined tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) remains the single-session contract. [ARKit support and permission](https://developer.apple.com/documentation/arkit/verifying-device-support-and-user-permission) covers unavailable-camera conditions. [P2](#p2--calibrate-and-validate-real-eye-movement) and [P3](#p3--build-one-bounded-experimental-warp) define the interface being connected.

```text
Execute P4 only, minutes 150–210. Goal: the verified live eye estimate moves
the verified warp, with honest scene state and reliable loss/recovery.

Inputs: P2's calibrated samples and P3's tested renderer. Feed the newest valid
calibrated display point to the warp center. Add a separately named adjustable
simulated-region offset if needed; never hide it in calibration. Keep marker
and warp center in the same physical-view coordinates, including display scale.
Default to the controlled seated orientation; invalidate calibration on change.

Do not queue old frames/samples. Use a bounded latest-sample handoff and one
in-flight render/update as appropriate. Keep processing local. Record timestamps
and expose current sample age, frame rate and processing time; these are not
automatically end-to-end eye-to-display latency. Do not add a worker pipeline,
extra engine or performance framework without a measured bottleneck.

Provide Start/Stop, Recalibrate, Original/Transformed, radius, strength and a
small visible status. Keep controls readable and accessible. On missing,
untracked, stale or invalid gaze, clear the marker immediately and disable the
adaptive warp. With a healthy scene show the unmodified scene and the exact
message “Tracking unavailable — original view”. Keep it until three consecutive
fresh valid samples arrive, then clear it and resume. Never leave a stale warp.

Independently track scene freshness and session interruptions. When the rear
source stops updating, show “Scene unavailable”/“Paused” visibly. Do not claim
that a frozen camera image is live. Retry should restart the same session
cleanly; Stop releases or pauses resources intentionally. Returning from the
background cannot silently reuse stale calibration/data as a fresh pass.

Only if rear input is the proven blocker, support one locally selected or
bundled prerecorded scene while retaining live eye estimates. Keep “Recorded
scene / live gaze” visible throughout. Verify playback orientation and freshness;
no network video service. This fallback does not satisfy a live-world claim.

Deliverable: live gaze-driven warp and a short loss/recovery record. On-phone
checks: eyes move while head is still; original toggle really removes the warp;
brief blink, covered face, looking away, Stop/Start and background/foreground
produce the correct states; valid recovery clears the warning and resumes.
Test scene interruption separately from gaze loss. Run relevant checks/build,
commit and stop. Gate: no stale active warp, hidden source failure or fake
gaze path may remain in the normal demonstration flow.
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

Repeat held-out center/edge targets, including a later pass after several
minutes to expose drift. Report errors in points and viewport-diagonal percent,
sample count, median/p90, failures and calibration duration. Separate eye-only
motion with a still head from head movement with fixed fixation. Note eyeglass,
lighting, blinking and distance effects only if actually tested. Do not claim
general reliability from one person's successful seated run.

Challenge orientation/layout changes, display scale/crop, off-screen estimates,
invalid numeric inputs, stale timestamps, obscured face, looking away, camera
permission denial, background/resume and repeated Start/Stop. Verify zero warp
strength matches Original. For every gaze-loss case check cleared marker,
disabled effect, original healthy source, persistent warning and valid recovery.
For a source failure check visible Scene unavailable/Paused, not frozen “live”.

Maintain one small meaningful runnable check for pure calibration/coordinate/
warp math; avoid test suites that merely restate implementation. Run it plus
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
external view showing the person's eyes and phone when possible, so the
eye-only test can be judged; a screen marker alone cannot prove its input.
Do not spend the final hour building a custom codec/recording system.

Record a concise sequence: setup and labels, calibration already completed,
held-out eye-only response with head still, original/transformed comparison,
radius/strength adjustment, tracking loss to original view and valid recovery.
Include source failure/retry if it was material. Keep “Recorded scene / live
gaze” visible if that fallback is used and “Simulated region” where relevant.
Do not use synthetic/regenerated media to improve evidence or replace failures.

Open the saved recording and verify playback, duration and visible behavior.
Record the actual file location and its device/build/commit relationship. Keep
large videos and signing material out of Git; only publish personal footage
where the user has authorized it. A screenshot, app build or claimed recording
is not a verified playable file. Record missing external-eye evidence honestly.

Write a short pitch using only observed outcomes: the problem, this native
technical experiment, what was demonstrated, its limits, and the next test.
State that the transformation changes the displayed phone image and uses an
assumed/simulated region. No patient efficacy, restored sight, prescription
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
360 arrives with recording, device tests, review or integration unfinished,
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
