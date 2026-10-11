# GazeShift

GazeShift is a working title for an experimental phone display tool: trace an assumed affected region with a finger in the air, review an approximate ellipse, and copy the original image content from that region to a chosen display offset.

**Current direction: manual screen-space approximation, with no eye tracking.** The user explicitly chose this pivot on 2026-10-11 after the gaze experiments failed their accuracy gates. The baseline at `5876905` was built, installed and launched on a physical **iPhone 15 Pro Max** before the pivot edits. The user also reported that the baseline camera opens. That proves deployment and a user-reported camera opening, not air tracing or the new end-to-end flow. Pivot work is in progress and awaits physical-device verification.

## The first demo

Use the front camera and Vision hand landmarks to pinch and trace one closed outline in the air. Review its min/max bounding ellipse as an explicit approximation, choose one copy offset, then switch the same ARSession to the rear scene. The reviewed region stays fixed in display coordinates; copy its enclosing rectangle from the original frame to the selected offset. Reject unavailable, overlapping or off-screen placements. The copy affects only the phone display and covers existing destination content.

Actual camera-tracked air tracing remains required. Touch controls may operate Review, Redo and offset selection. Eye movement and head movement do not drive the region, and there is no gaze calibration or synthetic gaze input. Normal Live assist stays unblurred. Preserve the labeled, full-viewport Original / Simulated blur / Simulated blur + copy comparison, using original source pixels and applying blur last.

Success means a playable recording of actual air tracing, explicit review, rear-scene copying and the three comparison modes on the physical phone. Gesture behavior, placement, source freshness and loss/recovery still need device verification; a build or launch cannot pass those gates.

## Project documents

- [Project context and working instructions](PROJECT_CONTEXT.md): current scope, architecture and evidence limits.
- [Six-hour build plan](SIX_HOUR_PLAN.md): concise manual-flow implementation and device checks.
- [Historical build prompts](BUILD_PROMPTS.md): superseded gaze requirements; do not execute them as the current spec.
- [Private GitHub repository](https://github.com/Hussain-coder-eng/gazeshift).
- [ChatGPT project](https://chatgpt.com/g/g-p-6acbc5e009008191a0d00a958ec143d0/project).

The [rear gaze blocker](docs/P2_REAR_GAZE_BLOCKER.md), [front diagnostic blocker](docs/P2_FRONT_DIAGNOSTIC_BLOCKER.md) and [off-screen diagnostics](docs/P2_OFFSCREEN_DIAGNOSTICS.md) preserve earlier results. They describe the superseded gaze approach, not current acceptance gates.

## Evidence and boundaries

A hand-drawn screen region does not measure retinal damage or follow a retinal blind spot as the eyes move. This manual approximation cannot diagnose disease, restore normal sight, replace prescriptions or establish patient benefit. Simulated blur illustrates the selected region; it does not reproduce a patient's vision. The copy duplicates content and occludes destination content.

Future assistive benefit requires separate user and clinical validation, including comparison with ordinary magnification and independently measured vision mapping. No low-vision participant, clinician partnership or startup validation is confirmed. The present scope is the phone demonstration, not wearable hardware or medical treatment.
