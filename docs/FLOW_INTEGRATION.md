# Flow integration (ANO-8, ANO-10, ANO-11, ANO-20)

Branch `anoop/flow-and-ui`. Written on a Mac without Xcode, so **nothing here has been built for iOS or run on a device**.

## Status

- **Air map (ANO-20, ANO-8) is wired into the app.** `GazeShiftFlow` and `GazeShift/Flow/*.swift` are in the Xcode project. `ContentView` has an **AIR MAP** section and a viewport overlay. It needs an iOS build and a phone test.
- **Comparison and copy (ANO-10, ANO-11) are logic only.** The planner, the controls and `CompositeShaders.metal` exist, but the renderer isn't switched over yet. `CompositeShaders.metal` is in the project navigator but **in no build phase**.
- **Calibration:** Hussain's merged `GazeSession` / `GazeCalibrationControls` handle it. The earlier duplicate `CalibrationRun` / `CalibrationScreen` from this branch has been removed.

## What was verified

- `GazeShiftFlow`: **18 Swift Testing tests pass** with `swift test` using the Command Line Tools. They use **synthetic fixtures only** and prove flow logic, not real air tracing or live eyes.
- Earlier, two deliberately injected bugs were caught by the tests, then reverted.
- `ContentView`, `GazeSession`, `GazeCalibrationControls` and `GazeShift/Flow/*.swift` type-check against the **macOS** SDK. That run used stand-ins for the iOS-only `CameraView` / `CaptureModel` and swapped `.topBarTrailing` → `.automatic`, in scratch copies only. They have not been compiled against the iOS SDK.
- `project.pbxproj` passes `plutil -lint`. The new IDs (`F000…01`–`0B`) each have one definition and the expected uses.
- `CompositeShaders.metal` has **not been compiled.**
- One change to the core: `Calibration.swift` gets explicit `[Double]` types, because the Swift 6.2 CLI couldn't type-check that expression. Values and order are unchanged.

## How the air map runs

1. Front setup → Hussain's calibration → held-out test → eye-only check. **AIR MAP → Start** is enabled only when `gaze.report?.passesCompleteGate == true` (ANO-19).
2. `AirTraceModel` subscribes to `capture.$snapshot`, so view updates can't coalesce snapshots away. For each new frame it records `rawEyes` / `rawEyeIdentity` through `gaze.calibration`. For each new `snapshot.hand` it pairs the hand with the gaze **from the same frame** (generation + ARKit frame timestamp) and feeds the core `AirTraceSession`.
3. A white `+` at the viewport center is the stationary fixation reference. You pinch, trace, return to the start and release.
   - **Clears the whole stroke:** a stale or missing hand (no new hand result for 250 ms, because the snapshot carries only detected hands), missing same-frame gaze, a blink, drift beyond 0.10 of the diagonal, a generation change, a mode change, Stop/Retry or a geometry change.
4. Review shows the raw trace (yellow) and the min/max ellipse (cyan), with explicit Accept/Redo and copy-offset nudges (green preview box). There's no default offset.

## Open issue for Hussain: region carry-over to rear mode

`GazeSession.configure` sets `viewingSetupID = "capture-generation-<n>-origin-<x>-<y>"`. Switching to Rear + eyes advances the generation, so the setup ID changes. Core `ReviewedRegion.retainedForModeTransition(to:)` requires the same `viewingSetupID`, so an accepted front region will be rejected with `invalidModeTransition` in rear mode. **Proposed fix:** keep the generation out of `viewingSetupID` and invalidate the calibration on a generation change separately. This is Hussain's file, so it hasn't been changed here. ANO-10/11 live relocation needs this.

## Remaining wiring for ANO-10/11 (after the carry-over fix)

1. Add `CompositeShaders.metal` to Copy Bundle Resources **as text**. Load it with a second `device.makeLibrary(source:)` and build a pipeline with `compositeVertex` / `compositeFragment`. Keep the existing pipeline as a fallback until it's verified on the phone.
2. Per frame:
   ```swift
   let plan = CompositionPlanner.plan(mode: viewMode, region: rearRegion, gaze: gaze.marker(at: now), geometry: rearGeometry,
                                      userOffset: airTrace.patchOffset ?? .init(x: .nan, y: .nan),
                                      liveMargin: LivePlacementMargin(p90ErrorPoints: rearReport.overallErrors?.p90Points ?? .nan,
                                                                     geometry: rearGeometry, validated: rearReport.passesCompleteGate),
                                      cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: rearGeometry.width, height: rearGeometry.height))
   var gpu = CompositeUniformValues(plan: plan, geometry: rearGeometry).gpu
   encoder.setFragmentBytes(&gpu, length: MemoryLayout<CompositeUniformValues.GPU>.stride, index: 1)
   ```
   - `gaze.marker(at:)` is already nil unless gaze is valid, recovered (3 samples) and on-screen.
   - A NaN offset is rejected as `invalidOffset`, so the original is shown until the user chooses an offset.
   - Full-viewport sampling bounds are valid only while the ARKit transform is aspect-fill.
3. Add `ComparisonControls(mode:plan:)` below the viewport in rear mode.

## Run the flow tests (no Xcode needed)

```bash
cd GazeShiftFlow
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F
```
With Xcode installed, a plain `swift test` works.
