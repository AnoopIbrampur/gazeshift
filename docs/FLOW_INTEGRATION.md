# Flow integration (ANO-8, ANO-10, ANO-11, ANO-15, ANO-20)

Prepared on `anoop/flow-and-ui`; review fixes are on `feat-flow-integration`. These components are **not wired into the running app**. Physical air tracing, live gaze-driven composition and the compositor on the iPhone GPU remain **NOT TESTED**.

## What was verified

Baseline at PR2 head `fdb609f`, before review fixes:

- Full Xcode checks passed: 24 Flow fixture tests and 31 Core tests. These prove software logic, not device calibration, air tracing or live-eye behavior.
- Core and Flow cross-built for arm64 iOS; the Flow SwiftUI files compiled to an iOS object/module against the iPhoneOS 27 SDK.
- The original app built for unsigned iOS, but that target did not include the Flow screens, package or compositor.
- `CompositeShaders.metal` compiled into a runtime library and render pipeline on the Mac's Apple M4 GPU. Offline iOS Metal compilation was blocked by the missing optional Metal Toolchain. Neither result proves iPhone GPU behavior.

Re-run affected checks on the final review-fix commit. Keep physical gates separate from these baseline checks.

One change to Hussain's core: `GazeShiftCore/Sources/GazeShiftCore/Calibration.swift` gets explicit `[Double]` types on the design/target concatenation. Swift 6.2 (Command Line Tools) failed with "unable to type-check this expression in reasonable time". The values and order are unchanged.

## What's in it

| Ticket | Piece | Where |
|---|---|---|
| ANO-20 | `AirTracePairer`/`AirTraceFlow`: pairs each Vision result with gaze **from the same ARFrame**. Every source eye event independently validates the active stroke, including frames skipped by Vision. A watchdog expires source and hand streams; any loss clears the whole stroke until Redo. | `GazeShiftFlow/Sources/GazeShiftFlow/AirTraceFlow.swift` |
| ANO-15 | Retain the reviewed P2 `GazeSession` as the **sole active calibrator**: nine targets, ≥15 distinct valid training samples per target, insufficient-target retry, separate held-out protocol and explicit eye-only report. `CalibrationRun`/`CalibrationController` remain unused alternatives; do not wire them as a second owner. | `GazeShift/GazeSession.swift`, `GazeShift/GazeCalibrationControls.swift` |
| ANO-8 | `AirMapOverlay` renders raw trace, min/max ellipse and fixation `+` in the full measured preview. Separate `AirMapReviewControls` provide Accept / Redo and explicit copy-offset nudges outside that viewport. | `GazeShift/Flow/AirMapReviewScreen.swift` |
| ANO-10/11 | `CompositionPlanner`: Live = copy only; Original = nothing; Simulated blur = mask at gaze + region offset; Blur + copy = same ellipse for mask and copy. Lost gaze or rejected placement → original + status. The Metal compositor samples original pixels for the copy and applies the blur last. | `GazeShiftFlow/.../Composition.swift`, `GazeShift/Flow/ComparisonControls.swift`, `GazeShift/Flow/CompositeShaders.metal` |

## Integration steps (Hussain / integrator, in Xcode)

1. **Packages:** File → Add Package Dependencies → Add Local… → `GazeShiftFlow`. Link the `GazeShiftFlow` and `GazeShiftCore` libraries to the `GazeShift` target.
2. **Sources:** add `FlowAdapters.swift`, `AirMapReviewScreen.swift` and `ComparisonControls.swift` to the target. Keep `GazeSession`/`GazeCalibrationControls` as the calibration owner; do not add `CalibrationScreen.swift` to the active flow.
3. **Shader:** add `GazeShift/Flow/CompositeShaders.metal` to Copy Bundle Resources **as text**, the same way as `CameraShaders.metal`, not as a compiled source. Load it with a second `device.makeLibrary(source:)` and build a separate pipeline with `compositeVertex` and `compositeFragment`. Keep the existing pipeline as a fallback until it's verified on the phone.
4. **Measured viewport:** put `AirMapOverlay(model: airTrace, geometry: measuredGeometry)` in the existing camera preview's `ZStack`. Supply the exact current full preview geometry used by capture and gaze calibration. Put `AirMapReviewControls(model: airTrace)` outside that viewport. The overlay has no controls or second `GeometryReader`; it renders nothing for a geometry mismatch. Preserve preview size **and origin** across phase/control changes. Do not scale old trace coordinates into a smaller panel.
5. **Renderer inputs:** compute the plan each frame, using only a passed **rear-mode** report and the calibrated marker:
   ```swift
   let sceneHealthy = snapshot.renderPacket?.identity.isFresh(at: now) == true
   let liveGaze = sceneHealthy && gaze.report?.passesCompleteGate == true ? gaze.marker(at: now) : nil
   let plan = CompositionPlanner.plan(mode: viewMode, region: rearRegion, gaze: liveGaze, geometry: rearGeometry,
                                      userOffset: airTrace.patchOffset ?? .init(x: .nan, y: .nan),
                                      liveMargin: LivePlacementMargin(p90ErrorPoints: rearReport.overallErrors?.p90Points ?? .nan,
                                                                     geometry: rearGeometry, validated: rearReport.passesCompleteGate),
                                      cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: rearGeometry.width, height: rearGeometry.height))
   var gpu = CompositeUniformValues(plan: plan, geometry: rearGeometry).gpu
   encoder.setFragmentBytes(&gpu, length: MemoryLayout<CompositeUniformValues.GPU>.stride, index: 1)
   ```
   Raw `CaptureFreshness.trackingAvailable` is insufficient: it does not reject calibrated off-screen predictions. `GazeSession.marker(at:)` requires three **distinct, increasing, fresh** source observations with valid calibrated predictions inside the measured viewport. Off-screen, blinking, missing or invalid gaze clears the marker and adaptive layers; the first and second valid predictions do not recover them. Scene freshness is independent: a stalled source clears the scene/effects and shows “Scene unavailable” or “Paused”, never a frozen image labeled live. A healthy scene with unavailable gaze stays original with the tracking warning. A NaN offset is deliberately rejected until the user chooses one. Full-viewport `cameraSamplingBounds` is valid only when the ARKit aspect-fill mapping covers that viewport; otherwise derive valid sampling bounds from the camera extent.
6. **Air-trace feed** (future ordered capture events, not snapshot “latest eyes”):
   - For **every** front source frame, emit its exact raw eyes—including nil, blinking or untracked eyes—before its Vision completion can be delivered: `airTrace.ingestEyes(eyes, identity: frameIdentity, calibration: frontCalibration)`. A bad eye-only event immediately invalidates an active stroke even when Vision drops that frame.
   - For each Vision completion, call `airTrace.ingestHand(observationOrNil, identity: item.identity, geometry: frontGeometry)`, including nil/error results. Forward a rejected stale completion as loss with its original identity; never retimestamp it. Hand and gaze pair by generation plus ARKit timestamp, never with a newer snapshot's eyes.
   - From the host watchdog, call `airTrace.expireInputs(now: now, geometry: frontGeometry)` every `CaptureLimits.watchdogInterval` (currently 50 ms), even while callbacks have stopped. Source and hand age use original monotonic capture times and the provisional 250 ms limit. Fresh camera/eye events do not conceal missing hand results. Event callbacks also check expiry before accepting new data.
   - Call `airTrace.interrupt()` on mode switch, pause, layout change or a new generation.
7. **Calibration feed and gates:** continue `GazeSession.receive(snapshot, now:)` with its raw-eye rejection metadata, target-presentation timing and periodic `tick(now:)`. Do not rebuild observations from filtered `snapshot.eyes`, which loses rejection reasons. Pass the front complete gate before actual air mapping, explicitly accept the region, switch the same session, then fit and pass all rear held-out/eye-only checks before composition. The provisional marker remains available for the eye-only check; provisional calibration alone cannot authorize mapping or composition.
8. **Mode-transition contract still needs integration:** current `GazeSession` geometry includes capture generation in `viewingSetupID`. A rear reconfiguration changes generation, so blindly passing its new geometry to `ReviewedRegion.retainedForModeTransition(to:)` correctly rejects retention. Implement and review an explicit same-physical-display transition adapter before wiring this step; do not falsify geometry equality or reuse the front calibration. Real geometry, distance, stand or lighting changes invalidate both calibration and region and require setup again.

Phase gate: passed front report → actual air trace and explicit review → permitted same-session transition → fresh rear fit and complete report → explicit offset → composition. Until physical P2 passes, these are preparation interfaces, not enabled P3/P4 behavior.

## Run the flow tests (no Xcode needed)

```bash
cd GazeShiftFlow
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F
```
With Xcode installed, a plain `swift test` (or ⌘U on the package) works.

## Current wiring on `anoop/flow-and-ui` (interim)

- `ContentView` already hosts the air map: `AirMapOverlay(model:geometry:)` inside the measured preview (only when `gaze.geometry` exists), `AirMapControls` (Start gated on Front + `.ready` + `gaze.report?.passesCompleteGate`, Redo/Accept/Close, offset nudges) below it, `airTrace.tick(now:geometry:)` on the existing timer (calls `expireInputs`), and `interrupt()` on Front/Rear/Stop/Retry.
- **Interim feed:** `AirTraceModel.attach(snapshots: capture.$snapshot)` records each new `rawEyeIdentity` frame and each new `snapshot.hand`. This is NOT the ordered capture-event feed in step 6. Snapshots can skip a frame's eyes, and empty Vision results are not delivered, so loss is caught by `expireInputs` rather than immediately. `ingestEyes`/`ingestHand`/`expireInputs` exist on the model for the step-6 wiring from `CaptureController`. Once that's in place, drop `attach`.
- Duplicate `CalibrationRun`/`CalibrationScreen` are removed from this branch; `GazeSession` is the only calibrator.
- Not built for iOS on this branch since the merge; the Flow logic tests pass (24/24, fixtures only).

## ANO-11 green-outline simulated blur (branch `anoop/ano-11-green-blur`)

- `CameraView` gets an optional `composite` uniform and a **separate** `compositeVertex`/`compositeFragment` pipeline built from the bundled `CompositeShaders.metal`, which is now in Copy Bundle Resources. With no layers, or if that shader fails, it draws the unchanged `cameraFragment` and reports the failure through `onCompositeFailure`.
- `ContentView` recomputes `CompositionPlanner.plan` every frame once a region is accepted. Live gaze is `gaze.marker(at:)` **only** when the scene is fresh and `gaze.report?.passesCompleteGate`. The margin is that report's p90.
- The viewport overlay draws a **green ellipse outline** around the simulated blind region (and a dashed white box for a copy destination). It's drawn only when the plan has those layers, so the outline and blur appear and clear together.
- `ComparisonControls` appears under AIR MAP after Accept. It shows the label, the context text ("Approximates a central blind spot … Not a medical simulation …") and orange notes explaining why the view is still original (no passed report, region not usable in this camera mode, no offset, shader unavailable).
- Verified: iOS Simulator `build-for-testing` succeeded with Xcode 27; `CompositeShaders.metal` is in the built `.app` and compiles into a render pipeline on the Mac's Apple M4 GPU (not an iPhone GPU); Flow 24/24. **Not run on the phone.** With the current failed P2 gates, the phone will show the notes, not the blur.
- **Unvalidated gaze demo (team-approved override, off by default):** a toggle above AIR MAP. When on, the air map and simulation use the provisional calibration even though the P2 gate hasn't passed. The viewport shows a persistent orange "UNVALIDATED GAZE — accuracy not verified" banner. Blur needs only a fitted calibration. Copy modes still need a held-out run, because the copy safety gap uses that report's **measured** p90. Nothing recorded with this on counts as P2/P3/P4 evidence.
