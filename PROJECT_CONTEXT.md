# GazeShift — project context

Use this document as durable context for the ChatGPT project and future implementation work. Read it with [SIX_HOUR_PLAN.md](SIX_HOUR_PLAN.md).

## Current state and owner

- Working title: **GazeShift**.
- Owner: a solo Penn State AI Engineering student, using an iPhone 13 and a Mac/laptop with a limited hardware budget.
- Repository: https://github.com/Hussain-coder-eng/gazeshift (private).
- As of 2026-10-11: documentation only; no prototype or measured results yet. Creating the repository does not prove the ChatGPT GitHub connector can access it.
- Known preflight blocker on 2026-10-11: the Xcode license has not been accepted. The user must resolve that and verify Xcode, signing, and real-device deployment before treating the six-hour estimate as feasible. Do not accept licenses or install applications on the user's behalf.

## Main idea

Explore gaze-contingent image remapping for residual central vision loss, including conditions such as age-related macular degeneration. The long-term direction is wearable glasses/headsets, but the immediate experiment runs on the phone. Shift or warp the displayed camera image around an adjustable assumed/simulated blind-spot region that follows calibrated gaze on the display.

The core pipeline is:

**Live rear-camera scene + live front-camera eye estimates → calibrated screen gaze → one simple gaze-following image warp → phone display.**

The correction applies only to the displayed image. Live eye tracking is essential. Do not replace it with head movement, a fake eye tracker, scripted gaze, or a dwell-selection reading application. Prioritize eye-tracking feasibility before visual polish or added features.

## Technical starting point

Use native Swift and Apple's existing tracking/ML capabilities; do not train a new model or place a cloud LLM in the time-critical loop. Start with a single ARKit session using `ARWorldTrackingConfiguration` and `userFaceTrackingEnabled`, after checking `supportsUserFaceTracking` on the actual device and configuration. Capability and runtime evidence decide feasibility; the phone model alone is not proof.

`ARFaceAnchor.lookAtPoint` is a face-coordinate estimate, not a screen pixel position. Calibrate a mapping to the physical display and validate it on held-out targets. Distinguish physical-screen coordinates from camera-image projection. Account explicitly for orientation, preview transformations, and display alignment. Do not start competing ARKit/AVFoundation sessions for the two camera streams.

Keep the first warp simple and adjustable. On lost or invalid tracking, clear the gaze indicator, stop the adaptive effect, and show the original feed. Do not leave a stale active warp on screen.

## Six-hour constraints

The 360-minute plan is conditional on a ready Mac/Xcode/signing setup and an available real device:

1. First 90 minutes: run on the iPhone; prove simultaneous rear frames and eye estimates; calibrate a visible gaze marker and test it with the head still. This is the go/no-go gate.
2. Next 120 minutes: add one experimental warp that follows gaze around the adjustable assumed/simulated region.
3. Next 90 minutes: test alignment, latency, held-out targets, screen edges, head still/moving, blinks, drift, and tracking loss.
4. Final 60 minutes: fix the highest-impact faults, record the actual demo video, and prepare the pitch.

Do not add accounts, a backend, object recognition, hardware purchases, new model training, or clinical calibration during this build. Preserve a controlled seated demo. If live rear input fails, clearly labeled prerecorded scene input is an allowed fallback; live gaze remains core. If live gaze itself fails, report the blocker and do not claim the core demo works.

## What counts as evidence

Success now means live eyes drive a live image transformation on the device, demonstrated in a recorded video. Record actual test outcomes, limitations, and setup conditions. Do not invent accuracy, FPS, latency, or benefit figures. A build, simulator screenshot, or passing software check is not proof of live eye tracking or a working device demo.

Future user benefit requires validation beyond this experiment, including comparison with ordinary magnification. Retinal mapping, actual scotoma shape/offset, PRL calibration, binocular/bilateral viewing, and adaptation/stability are unresolved clinical research questions. The simulated region is not diagnosis or a medical correction. Do not claim normal sight is restored, prescriptions/inserts are replaced, disease is cured, or patient benefit is proven.

No clinical participant access, partner commitment, Nittany AI selection, or startup validation is confirmed. Treat those as future possibilities and use conditional wording such as “if selected.”

## Working instructions

Keep work small and practical. Reuse native features and existing dependencies. Work on a feature branch; dispatch file changes through the Gang's write-path agent. Commit and verify changes, then obtain an independent Superpowers code review before merging and pushing to `main`. Re-review any branch carried over from an earlier session before merging. Do not implement the app until implementation is requested.

Communicate what exists, what was verified, and what remains blocked separately. Keep supplied facts and scope; do not invent access, outcomes, clinical claims, or connector status.

## References

- Apple: [Combining user face tracking and world tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking).
- Apple: [`ARFaceAnchor.lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint).
- Research: [PRL and video calibration](https://pmc.ncbi.nlm.nih.gov/articles/PMC5714047/).
- Research: [Simulated image-remapping study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/); simulation is not patient efficacy.
- Research: [Stability limits](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/).
