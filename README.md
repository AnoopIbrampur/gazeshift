# GazeShift

> **Anoop Ibrampur's version.** This repository is my independent continuation of GazeShift, copied with full history on 2026-10-12 from [Hussain-coder-eng/gazeshift](https://github.com/Hussain-coder-eng/gazeshift). The project was originally co-built with Hussain Altufayli at a hackathon (October 2026); everything up to commit `5a405be` is our joint work. Changes after that point are mine. Hussain continues his own version separately.

GazeShift is a working title for an experimental phone display tool: draw an assumed affected region, review an approximate ellipse, and copy the original image content from that region to a chosen display offset.

**Current direction: manual screen-space approximation using front-camera index tracing or rear screen drawing, with no eye tracking.** The prior thumb/pinch build `1011.18.10` was installed on a physical **iPhone 15 Pro Max**, but the user reported that their physical tracing attempt produced no line and failed. The user explicitly dropped thumb/pinch input. A successful end-to-end phone demo remains unverified.

**Rear screen drawing (`1011.18.24`):** Select **Rear scene**, wait for the live camera, then tap **Start drawing**. Draw a closed loop directly on the camera image, return to the yellow start dot, and lift to review the yellow trace and cyan ellipse. **Finish shape** also freezes the outline. Tap **Accept region**, then use the always-visible **← → ↑ ↓** copy-offset controls. **Start drawing** or **Draw again** replaces the current region. Front setup keeps camera-tracked index-finger air drawing. This update includes the upright portrait/landscape camera layout; rear touch delivery and the complete workflow still need physical-phone verification.

## The front air-drawing demo

Use the front camera and Vision index-finger landmarks. Tap **Start drawing** to arm recording; ordinary finger movement before Start creates no shape. Trace one closed loop with the index finger only and watch the outline accumulate. Return to the start and keep the index visible while the other hand taps **Finish shape**, which freezes a valid candidate for review. Review its min/max bounding ellipse, then separately tap **Accept region** to commit it. Choose one copy offset, then switch the same ARSession to the rear scene. The reviewed region stays fixed in display coordinates; copy its enclosing rectangle from the original frame to the selected offset. Reject unavailable, overlapping or off-screen placements. The copy affects only the phone display and covers existing destination content.

Actual camera-tracked air tracing remains required in Front setup; rear drawing uses screen touches with a fresh rear camera source. Existing checks still require a closed loop with at least 20 distinct points, valid samples and matching source identity. Eye movement and head movement do not drive the region, and there is no gaze calibration or synthetic gaze input. Accept region selects the labeled Simulated blur preview. Normal Live assist stays unblurred. Preserve the labeled, full-viewport Original / Simulated blur / Simulated blur + copy comparison, using original source pixels and applying blur last.

Success means a playable recording of actual air tracing, explicit review, rear-scene copying and the three comparison modes on the physical phone. Gesture behavior, placement, source freshness and loss/recovery still need device verification; a build or launch cannot pass those gates.

## Project documents

- [Project context and working instructions](PROJECT_CONTEXT.md): current scope, architecture and evidence limits.
- [Six-hour build plan](SIX_HOUR_PLAN.md): concise manual-flow implementation and device checks.
- [Historical build prompts](BUILD_PROMPTS.md): superseded gaze requirements; do not execute them as the current spec.
- [This repository](https://github.com/AnoopIbrampur/gazeshift) (Anoop's version) · [original shared repository](https://github.com/Hussain-coder-eng/gazeshift).
- [ChatGPT project](https://chatgpt.com/g/g-p-6acbc5e009008191a0d00a958ec143d0/project).

The [rear gaze blocker](docs/P2_REAR_GAZE_BLOCKER.md), [front diagnostic blocker](docs/P2_FRONT_DIAGNOSTIC_BLOCKER.md) and [off-screen diagnostics](docs/P2_OFFSCREEN_DIAGNOSTICS.md) preserve earlier results. They describe the superseded gaze approach, not current acceptance gates.

## Evidence and boundaries

A hand-drawn screen region does not measure retinal damage or follow a retinal blind spot as the eyes move. This manual approximation cannot diagnose disease, restore normal sight, replace prescriptions or establish patient benefit. Simulated blur illustrates the selected region; it does not reproduce a patient's vision. The copy duplicates content and occludes destination content.

Future assistive benefit requires separate user and clinical validation, including comparison with ordinary magnification and independently measured vision mapping. No low-vision participant, clinician partnership or startup validation is confirmed. The present scope is the phone demonstration, not wearable hardware or medical treatment.
