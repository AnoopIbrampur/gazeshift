# Flow integration (ANO-8, ANO-10, ANO-11, ANO-15, ANO-20)

Branch `anoop/flow-and-ui`. Written on a Mac without Xcode, so **nothing here has been built for iOS or run on a device**.

## What was verified

- `GazeShiftFlow` (new local package, depends on `../GazeShiftCore` by path): 24 Swift Testing tests pass with `swift test` using the Command Line Tools. They use **synthetic fixtures only**, so they prove flow logic and not device calibration, air tracing or live-eye behavior.
- Two deliberately injected bugs (blur in normal Live; accepting a target with too few eye samples) were caught by the tests, then reverted.
- `GazeShift/Flow/*.swift` type-check against the macOS SDK together with `CaptureTypes.swift` and `DisplayGeometry.swift`. They have not been compiled against the iOS SDK.
- `CompositeShaders.metal` has **not been compiled at all**.

One change to Hussain's core: `GazeShiftCore/Sources/GazeShiftCore/Calibration.swift` gets explicit `[Double]` types on the design/target concatenation. Swift 6.2 (Command Line Tools) failed with "unable to type-check this expression in reasonable time". The values and order are unchanged.

## What's in it

| Ticket | Piece | Where |
|---|---|---|
| ANO-20 | `AirTracePairer`/`AirTraceFlow`: pairs each Vision hand result with the calibrated gaze **from the same ARFrame** (generation + ARKit frame timestamp) and feeds the reviewed `AirTraceSession`. A missing hand, missing same-frame gaze, blink or drift clears the whole stroke. | `GazeShiftFlow/Sources/GazeShiftFlow/AirTraceFlow.swift` |
| ANO-15 | `CalibrationRun`: 9 training targets (.15/.5/.85; 0.5 s settle + 1 s capture; ≥10 unique valid samples per target or explicit failure), `GazeCalibration.fit`, then the held-out protocol: 2 passes × (4 novel + 1 interleaved center), 20 scheduled 50 ms slots each through `HeldOutWindow`. Dropped ticks count as missing, never extended. Then an operator eye-only check → `HeldOutReport`. | `GazeShiftFlow/.../CalibrationRun.swift`, `GazeShift/Flow/CalibrationScreen.swift` |
| ANO-8 | Review screen: raw trace, min/max ellipse, fixation `+`, Accept (only when `candidateReady`) / Redo, explicit copy-offset nudges (no default offset). | `GazeShift/Flow/AirMapReviewScreen.swift` |
| ANO-10/11 | `CompositionPlanner`: Live = copy only; Original = nothing; Simulated blur = mask at gaze + region offset; Blur + copy = same ellipse for mask and copy. Lost gaze or rejected placement → original + status. The Metal compositor samples original pixels for the copy and applies the blur last. | `GazeShiftFlow/.../Composition.swift`, `GazeShift/Flow/ComparisonControls.swift`, `GazeShift/Flow/CompositeShaders.metal` |

## Integration steps (Hussain / integrator, in Xcode)

1. **Packages:** File → Add Package Dependencies → Add Local… → `GazeShiftFlow`. Link the `GazeShiftFlow` and `GazeShiftCore` libraries to the `GazeShift` target.
2. **Sources:** add `GazeShift/Flow/*.swift` to the `GazeShift` target.
3. **Shader:** add `GazeShift/Flow/CompositeShaders.metal` to Copy Bundle Resources **as text**, the same way as `CameraShaders.metal`, not as a compiled source. Load it with a second `device.makeLibrary(source:)` and build a separate pipeline with `compositeVertex` and `compositeFragment`. Keep the existing pipeline as a fallback until it's verified on the phone.
4. **Renderer inputs:** compute the plan each frame:
   ```swift
   let plan = CompositionPlanner.plan(mode: viewMode, region: rearRegion, gaze: liveGaze, geometry: rearGeometry,
                                      userOffset: airTrace.patchOffset ?? .init(x: .nan, y: .nan),
                                      liveMargin: LivePlacementMargin(p90ErrorPoints: rearReport.overallErrors?.p90Points ?? .nan,
                                                                     geometry: rearGeometry, validated: rearReport.passesCompleteGate),
                                      cameraSamplingBounds: ScreenRect(x: 0, y: 0, width: rearGeometry.width, height: rearGeometry.height))
   var gpu = CompositeUniformValues(plan: plan, geometry: rearGeometry).gpu
   encoder.setFragmentBytes(&gpu, length: MemoryLayout<CompositeUniformValues.GPU>.stride, index: 1)
   ```
   `liveGaze` must be `nil` unless `CaptureFreshness` reports tracking available, so it follows the three-fresh-sample recovery rule. A NaN offset is deliberately rejected as `invalidOffset`, so the original is shown until the user picks an offset. `cameraSamplingBounds` is the full viewport only while the ARKit display transform is aspect-fill. Otherwise, map the camera image extent into view points.
5. **Air-trace feed** (capture queue → main actor, preserving order so a frame's gaze is recorded before its hand):
   - For each front frame, after eyes are read: `airTrace.ingestEyes(eyes, identity: frameIdentity, calibration: frontCalibration)`
   - In `handFinished(item, result)`: `airTrace.ingestHand(observationOrNil, identity: item.identity, geometry: frontGeometry)`. Call it **also when no hand was found**, because that's what clears an in-progress stroke.
   - Call `airTrace.interrupt()` on mode switch, pause, layout change or a new generation.
6. **Calibration feed:** `calibrationController.latestObservation = { FlowAdapters.gazeObservation(snapshot.eyes, identity: snapshot.eyeIdentity!) }` (guard against nil identity), and `currentGeometry = { FlowAdapters.renderGeometry(...) }`. Run it once in Front setup (ANO-19) and again after switching to Rear + eyes (ANO-21). `ReviewedRegion.retainedForModeTransition(to:)` carries the region across.
7. Change `viewingSetupID` whenever the phone stand, distance or lighting changes. That invalidates calibrations and regions through geometry equality.

## Run the flow tests (no Xcode needed)

```bash
cd GazeShiftFlow
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F
```
With Xcode installed, a plain `swift test` (or ⌘U on the package) works.
