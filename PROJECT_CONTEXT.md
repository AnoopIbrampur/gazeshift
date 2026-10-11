# GazeShift — project context

Use this document as durable context for the ChatGPT project and future implementation work. Read it with [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md) and the authoritative phase instructions in [BUILD_PROMPTS.md](BUILD_PROMPTS.md).

## Current state and owner

- Working title: **GazeShift**.
- Owner: a solo Penn State AI Engineering student, using an iPhone 13 and a Mac/laptop with a limited hardware budget.
- Repository: https://github.com/Hussain-coder-eng/gazeshift (private).
- As of 2026-10-11: documentation only; no prototype or measured results yet. The GitHub connector was separately verified to identify this private repository and read this document.
- Known preflight blocker on 2026-10-11: the Xcode license has not been accepted. The user must resolve that and verify Xcode, signing, and real-device deployment before treating the six-hour estimate as feasible. Do not accept licenses or install applications on the user's behalf.

## Main idea

Explore gaze-contingent image relocation for residual central vision loss. The long-term direction is wearable glasses/headsets; the immediate phone experiment has two stages: camera-tracked air tracing during Setup/map, then Live assist. The healthy-user demo traces an explicitly assumed region while maintaining fixed gaze. A reviewed bounding ellipse approximates the outline; it is not a diagnosed defect.

The core pipeline is:

**Front image + Vision hand landmarks + calibrated fixation → air outline → reviewed ellipse with fixation-relative offset → switch/recalibrate → rear original image + live gaze → one translated rectangular copy → phone display.**

The copy applies only to the displayed image. Actual air tracing and live eye tracking are essential; do not substitute touchscreen tracing, head movement, scripted gaze or a dwell-selection app. Touch controls may operate Review/Redo and the chosen copy offset.

## Technical starting point

Use native Swift, ARKit and Vision; no new model training or cloud LLM in the live loop. Use the same ARSession sequentially: supported `ARFaceTrackingConfiguration` provides the front image and face anchors during setup; `VNDetectHumanHandPoseRequest` finds index/thumb tips for a virtual 2D cursor, not a 3D finger ray. Supported `ARWorldTrackingConfiguration.userFaceTrackingEnabled` provides the rear image and face anchors during Live assist, not both raw camera feeds. Check each configuration on the actual phone; never start competing capture sessions.

`ARFaceAnchor.lookAtPoint` is face-relative, not screen pixels. Calibrate and validate held-out screen gaze in setup mode, then clear old data and refit/revalidate after switching to live mode. Follow the fixed-window coverage and per-target accuracy gates in BUILD_PROMPTS. Camera projection alone is not physical-screen gaze. Test orientation, crop, mirroring and y-axis conversion exactly once. Geometry/distance changes invalidate calibration and the region; normalization does not correct visual-angle changes.

Air tracing requires a stationary fixation reference and valid hand/gaze signals throughout one closed stroke. Drift, occlusion or missing points invalidates the stroke; require Redo rather than joining gaps. Review a min/max bounding ellipse, preserve its center offset from fixation and keep the raw trace/session metadata only in memory. This approximation loses irregular outline details; do not silently recenter it onto gaze or claim per-eye clinical mapping.

In Live assist, the region follows gaze plus the stored offset. Copy its enclosing rectangle from the original unblurred frame to one user-chosen offset, over the original scene. Source and destination must fit valid image/view bounds; destination must avoid the assumed region plus a provisional live-gaze-error margin. Otherwise show “No valid placement — original view” and bypass. No recursive sampling, auto-clamping, invented pixels or full-scene radial warp. The copy duplicates content, covers destination content and can move again when looked at; this is a peripheral-viewing experiment.

Normal Live assist adds no artificial blur. Optional observer simulation is off by default and applies the same assumed blur last to original and copied variants of the same frame. Never sample already blurred pixels. Live assist uses the full calibrated viewport; altered layouts require recalibration.

On invalid gaze, clear the indicator/copy and show the healthy original scene with “Tracking unavailable — original view” until three fresh valid samples recover. A failed source instead shows “Scene unavailable” or “Paused”; never label a frozen frame live. Keep finite off-screen estimates in accuracy scoring before rejecting them from the display.

## Six-hour constraints

The 360-minute plan is conditional on a ready Mac/Xcode/signing setup and an available real device:

1. First 90 minutes: prove both configurations and actual hand/eye data, then calibrate front-mode gaze and pass the held-out eye-only gate.
2. Minutes 90–150: air-trace and review the approximate ellipse, switch modes, refit and validate live gaze. Minute 150 is a second go/no-go gate.
3. Minutes 150–210: implement one original-image rectangular copy with explicit placement checks and loss/recovery.
4. Minutes 210–300: test mapping, switching, gaze, placement, drift and failures on the device.
5. Final 60 minutes: record actual air tracing and eye-driven relocation, prepare the pitch and finish review.

Gesture tracking and the second calibration make this optimistic. Setup during the event consumes the same six-hour window; missed gates are reported, not silently removed.

Do not add accounts, a backend, object recognition, hardware purchases, new model training, or clinical calibration during this build. Preserve a controlled seated demo. If live rear input fails, clearly labeled prerecorded scene input is an allowed fallback; live gaze remains core. If live gaze itself fails, report the blocker and do not claim the core demo works.

## What counts as evidence

Success means actual air tracing followed by live eyes driving patch relocation, demonstrated on the device in a playable recording. Record test outcomes, limitations and whether evidence is agent-observed, user-reported or not tested. Do not invent accuracy, FPS, latency or benefit figures. A build, simulator screenshot or passing software check is not proof of either live input.

Future user benefit requires validation beyond this experiment, including comparison with ordinary magnification. Retinal mapping, actual scotoma shape/offset, PRL calibration, binocular/bilateral viewing, and adaptation/stability are unresolved clinical research questions. The simulated region is not diagnosis or a medical correction. Do not claim normal sight is restored, prescriptions/inserts are replaced, disease is cured, or patient benefit is proven.

No clinical participant access, partner commitment, Nittany AI selection, or startup validation is confirmed. Treat those as future possibilities and use conditional wording such as “if selected.”

## Working instructions

Keep work small and practical. Reuse native features and existing dependencies. Work on a feature branch; dispatch file changes through the Gang's write-path agent. Commit and verify changes, then obtain an independent Superpowers code review before merging and pushing to `main`. Re-review any branch carried over from an earlier session before merging. Do not implement the app until implementation is requested.

Communicate what exists, what was verified, and what remains blocked separately. Keep supplied facts and scope; do not invent access, outcomes, clinical claims, or connector status.

## References

- Apple: [Combining user face tracking and world tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking).
- Apple: [`ARFaceAnchor.lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint).
- Apple: [Hand-pose and pinch example](https://developer.apple.com/videos/play/wwdc2020/10653/) and [Vision with ARFrame](https://developer.apple.com/videos/play/wwdc2021/10039/).
- Research: [Fixation and mapping limitations](https://pmc.ncbi.nlm.nih.gov/articles/PMC7937995/); an air outline is not clinical per-eye mapping.
- Research: [PRL and video calibration](https://pmc.ncbi.nlm.nih.gov/articles/PMC5714047/).
- Research: [Simulated image-remapping study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/); simulation is not patient efficacy.
- Research: [Stability limits](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/).
