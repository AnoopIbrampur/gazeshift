# Flow integration (ANO-8, ANO-10, ANO-11, ANO-15, ANO-20)

Initially prepared on `anoop/flow-and-ui`, with review fixes on `feat-flow-integration`. The app now wires the air map, composition controls, optional compositor and deliberate same-display rear handoff through PRs #2, #5 and #9/#10. Physical air tracing, live gaze-driven composition and the compositor on the iPhone GPU remain **NOT TESTED**. Software wiring does not pass the failed physical P2 gate.

## Historical software verification (2026-10-11)

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

## App integration contract (current after PRs #5 and #9/#10)

1. **Packages:** File → Add Package Dependencies → Add Local… → `GazeShiftFlow`. Link the `GazeShiftFlow` and `GazeShiftCore` libraries to the `GazeShift` target.
2. **Sources:** add `FlowAdapters.swift`, `AirMapReviewScreen.swift` and `ComparisonControls.swift` to the target. Keep `GazeSession`/`GazeCalibrationControls` as the calibration owner; do not add `CalibrationScreen.swift` to the active flow.
3. **Shader:** add `GazeShift/Flow/CompositeShaders.metal` to Copy Bundle Resources **as text**, the same way as `CameraShaders.metal`, not as a compiled source. Load it with a second `device.makeLibrary(source:)` and build a separate pipeline with `compositeVertex` and `compositeFragment`. Keep the existing pipeline as a fallback until it's verified on the phone.
4. **Measured viewport:** put `AirMapOverlay(model: airTrace, geometry: measuredGeometry)` in the existing camera preview's `ZStack`. Supply the exact current full preview geometry used by capture and gaze calibration. Put `AirMapReviewControls(model: airTrace)` outside that viewport. The overlay has no controls or second `GeometryReader`; it renders nothing for a geometry mismatch. Preserve preview size **and origin** across phase/control changes. Do not scale old trace coordinates into a smaller panel.
5. **Renderer inputs:** recompute the plan each frame. Normal use requires a passed **rear-mode** report and the calibrated marker, as in this example. The explicit **Unvalidated gaze demo**, off by default, permits a provisional fit with its persistent orange warning; it does not change the report or formal gate. Both paths require fresh scene input and the current calibrated marker:
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
6. **Air-trace feed** (ordered capture events):
   - `CaptureController` emits `CaptureEvent.eyes` for **every** accepted source frame, including nil, blinking or untracked eyes, before submitting its Vision work. `CaptureModel` preserves serial capture ordering on the main queue, and `AirTraceModel.attach(events:gaze:)` reads the latest `GazeSession` rather than caching a fit. A bad eye-only event clears an active stroke even when Vision skips that frame.
   - Every current-generation Vision completion emits `CaptureEvent.hand` with its original identity and typed `Result`, before display freshness filtering. Nil, error and stale results clear an active stroke. Hand and gaze pair by generation plus ARKit timestamp, never with a newer snapshot's eyes. The bounded one-in-flight/newest-pending Vision pipeline is unchanged.
   - The existing UI timer calls `airTrace.tick(now:geometry:)` even while callbacks have stopped. It invokes the core expiry checks with original monotonic capture times and the provisional 250 ms limit. Fresh source events cannot conceal missing hand completions; callbacks also check expiry before accepting data.
   - Stop, Retry, front restart, capture reset/failure, or physical viewport frame/scale change clears accepted region and offset, including after Close. Only an explicit rear selection can retain unmodified front provenance, pending the rear capture reset and a fresh rear fit. `rearRegion(for:)` then converts it through core same-display validation for the current rear geometry. Any later capture reset clears it. Turning the demo OFF clears a region whose acceptance depended on the override, including pending/retained rear state; a region accepted with a passed front report is preserved through an otherwise valid handoff.
7. **Calibration feed and gates:** continue `GazeSession.receive(snapshot, now:)` with its raw-eye rejection metadata, target-presentation timing and periodic `tick(now:)`. Do not rebuild observations from filtered `snapshot.eyes`, which loses rejection reasons. Normal use requires the front complete gate before air mapping, explicit region acceptance, the deliberate same-session switch, then a fresh rear fit and complete rear held-out/eye-only report before composition. The provisional marker remains available for the eye-only check. The explicitly enabled unvalidated demo permits provisional mapping/composition under its warning; blur needs a fitted calibration, while copy also needs the measured held-out p90 for its placement gap. Neither path reuses the front fit in rear mode.
8. **Mode-transition adapter is wired:** `GazeSession.viewingSetupID` identifies the physical viewport origin, while size, scale and orientation remain separate geometry fields. Capture generation is checked separately and still invalidates calibration. `AirTraceModel.prepareForRearSelection()` plus the next rear reset enables `rearRegion(for:)`; `ContentView.currentRegion` consumes it. Core checks physical geometry when converting the accepted front provenance. Do not reuse the front calibration. Real geometry changes clear calibration and region; distance, stand or lighting changes require setup again.

Formal phase gate: passed front report → actual air trace and explicit review → permitted same-session transition → fresh rear fit and complete report → explicit offset → composition. The current app also exposes the explicitly labeled unvalidated demo described above. That override never counts as passed P2/P3/P4 evidence, and the failed physical P2 checkpoint remains open.

## Run the flow tests (no Xcode needed)

```bash
cd GazeShiftFlow
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test -Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F
```
With Xcode installed, a plain `swift test` (or ⌘U on the package) works.

## Current app wiring and remaining gate

- `ContentView` hosts `AirMapOverlay(model:geometry:)` in the same measured preview and controls outside it. Start requires Front + `.ready` + a fitted calibration and either the complete front report or the explicit unvalidated demo. Active callbacks, Redo, Accept and the timer recheck current eligibility, including fit/current geometry. Recalibration or a new held-out test clears eligibility; eye-only revocation clears a normal-mode attempt. A closed accepted front review also clears when its eligibility is revoked. Demo-dependent accepted provenance clears immediately when the override is disabled, including after rear handoff.
- The ordered event feed in step 6 replaces the interim snapshot subscription. Display snapshots retain their existing freshness filtering and calibration feed.
- Duplicate `CalibrationRun`/`CalibrationScreen` are removed from this branch; `GazeSession` is the only calibrator.
- The mode-transition adapter in step 8 and rear renderer consumer are wired. Only the deliberate transition retains the front region, with the original acceptance provenance and current physical geometry checked. A new rear fit/report is independent of that front provenance. Physical P3/P4 evidence remains unfinished; synthetic app/package tests and an iOS build do not pass the failed physical P2 gate.

## ANO-11 green-outline simulated blur (branch `anoop/ano-11-green-blur`)

- `CameraView` gets an optional `composite` uniform and a **separate** `compositeVertex`/`compositeFragment` pipeline built from the bundled `CompositeShaders.metal`, which is now in Copy Bundle Resources. With no layers, or if that shader fails, it draws the unchanged `cameraFragment` and reports the failure through `onCompositeFailure`.
- `ContentView` recomputes `CompositionPlanner.plan` every frame once a region is accepted. Live gaze is `gaze.marker(at:)` only when the scene is fresh and either `gaze.report?.passesCompleteGate` or the explicit unvalidated demo is enabled. Copy uses the available report's measured p90; without that report only simulated blur is available.
- The viewport overlay draws a **green ellipse outline** around the simulated blind region (and a dashed white box for a copy destination). It's drawn only when the plan has those layers, so the outline and blur appear and clear together.
- `ComparisonControls` appears under AIR MAP after Accept. It shows the label, the context text ("Approximates a central blind spot … Not a medical simulation …") and orange notes explaining why the view is still original (no passed report, region not usable in this camera mode, no offset, shader unavailable).
- Historical PR5 verification (2026-10-11): iOS Simulator `build-for-testing` succeeded with Xcode 27; `CompositeShaders.metal` is in the built `.app` and compiles into a render pipeline on the Mac's Apple M4 GPU (not an iPhone GPU); Flow 24/24. **Not run on the phone.** Failed P2 gates keep normal-mode effects off; explicitly enabling the unvalidated demo permits the warned demonstration.
- **Unvalidated gaze demo (team-approved override, off by default):** a toggle above AIR MAP. When on, the air map and simulation use the provisional calibration even though the P2 gate hasn't passed. The viewport shows a persistent orange "UNVALIDATED GAZE — accuracy not verified" banner. Blur needs only a fitted calibration. Copy modes still need a held-out run, because the copy safety gap uses that report's **measured** p90. Nothing recorded with this on counts as P2/P3/P4 evidence.

## Rear-region handoff (branch `anoop/rear-region-transition`, stacked on PR #5)

- `GazeSession` setup ID is now `viewport-origin-<x>-<y>`, the **physical** placement only. A new capture generation still invalidates calibration through its existing `generation != self.generation` guard; the generation just isn't part of the geometry identity anymore.
- `AirTraceModel.rearRegion(for:)` returns the accepted front region converted through core `retainedForModeTransition(to:)`, but **only** after the explicit Front → Rear + eyes switch of the same session (`retainedInRear`), for rear geometry. Any later reset, viewport move, scale or setup change clears it. `ContentView.currentRegion` uses it.
- The rear mode still needs its own fresh calibration (or the Unvalidated gaze demo). The front fit is never reused.
- Historical PR9 verification (2026-10-11): iOS Simulator `build-for-testing` OK. The app's GazeSession/AirTraceModel XCTests (28, including 2 new rear-handoff tests) were run on **macOS** through a scratch package that compiles the same source files. They weren't run in an iOS simulator. Restoring the old generation-based ID makes them fail (4 failures).
