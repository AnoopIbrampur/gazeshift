# Flow integration (current)

How the app's flow pieces fit together on `main` after the manual, no-eye-tracking pivot. History of earlier wiring (gaze-driven composition, unvalidated demo, blur checklist) is in [HISTORY.md](HISTORY.md).

## What the live app uses

| Piece | Where | Role now |
|---|---|---|
| `AirTraceSession` (index-only air trace or rear screen-touch, screen-fixed) | `GazeShiftCore/.../AirTrace.swift` | Validates the drawn stroke: Start drawing arms, Finish shape freezes a candidate, Accept region commits. Min/max bounding ellipse, fixed to the screen. |
| `AirTraceFlow` / pairer | `GazeShiftFlow/.../AirTraceFlow.swift` | Pairs each Vision index result with its own source frame (generation + ARKit timestamp); feeds the session. |
| `AirTraceModel`, `AirMapOverlay`, `AirMapControls` | `GazeShift/Flow/AirMapReviewScreen.swift` | Front air drawing and rear touchscreen drawing (`touchPoint`; the rear drag gesture lives in `ContentView`), review overlay (yellow trace, start dot, cyan ellipse), Start / Finish / Accept / Draw again, copy-offset arrows, front→rear region retention (`rearRegion(for:)`). |
| `CompositionPlanner`, `CompositeUniformValues` | `GazeShiftFlow/.../Composition.swift` | Per-frame plan for Live (copy only), Original, Simulated blur, Simulated blur + copy, using the screen-fixed region. Copy samples original pixels; blur is applied last. |
| `ComparisonControls` | `GazeShift/Flow/ComparisonControls.swift` | Mode picker plus the persistent "Simulated blur — demonstration only" label. |
| Compositor shader | `GazeShift/Flow/CompositeShaders.metal` (bundled as text) | Separate pipeline in `CameraView`; the original `cameraFragment` pipeline is the fallback if it fails to load. |
| Orientation | `CaptureController`, live `ContentView` | ARKit display transform and Vision orientation follow the real UI orientation (portrait, landscape left/right). A rotation is a layout change. |

`FlowAdapters.swift` converts capture types (frame identity, hand observations) into core and flow inputs.

## Legacy (kept, inactive)

- The pre-pivot gaze screen in `ContentView.swift` is compiled out with `#if false`. It contains the gaze-driven composition, the **Unvalidated gaze demo** toggle and the **blur checklist** (#11, #12, #14). `GazeSession` and calibration still build and are tested, but don't drive the live screen.
- `GazeSession` setup IDs name the physical viewport only (`viewport-origin-x-y`); the capture generation invalidates separately (#9/#10).

## Checks

- `GazeShiftCore`: `swift test` (XCTest; needs full Xcode).
- `GazeShiftFlow`: `swift test`. Without Xcode, add `-Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks`.
- App: `xcodebuild -scheme GazeShift -destination 'generic/platform=iOS Simulator' build-for-testing`. App tests need a simulator runtime or a device.
- Builds and fixture tests are **software-only** evidence; drawing, copying and blur need the phone (see [P5_CHALLENGE_MATRIX.md](P5_CHALLENGE_MATRIX.md)).
