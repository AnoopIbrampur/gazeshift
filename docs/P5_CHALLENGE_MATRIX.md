# P5 physical challenge matrix (ANO-22)

Checklist for the **current manual, screen-fixed flow** (no eye tracking). Every row ends as **PASS**, **FAIL** or **NOT TESTED**, with evidence. Simulator and fixture results can't close any row. The earlier gaze rows were removed with the pivot; gaze results are preserved in `docs/P2_*` and [HISTORY.md](HISTORY.md).

## Session record

| Field | Value |
|---|---|
| Date / time | NOT TESTED |
| Device / iOS | iPhone 15 Pro Max / iOS 27.0 (confirm) |
| App build marker / git commit | NOT TESTED |
| Orientation used for the run | NOT TESTED |
| Viewport (pt) / scale | NOT TESTED |
| Viewing distance, stand / handheld, lighting | NOT TESTED |
| Operator / recorder | NOT TESTED |
| Evidence location (videos) | NOT TESTED |

Provenance: **A** = agent-observed (log or screen recording), **U** = user-reported, **X** = external camera recording.

## Front air drawing (index finger)

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| F1 | Index visible → Start drawing → trace a closed loop → Finish shape | Yellow line, start dot, cyan ellipse; Accept enabled | NOT TESTED | | |
| F2 | Move the finger before Start | Nothing is drawn | NOT TESTED | | |
| F3 | Hand leaves the frame or loses tracking mid-stroke | Stroke clears with a message; Draw again works (behavior changes if #17 merges: brief dropouts are skipped) | NOT TESTED | | |
| F4 | Open shape / tiny shape | Rejected with a reason | NOT TESTED | | |
| F5 | Accept region → copy-offset arrows | Region fixed on screen; offset moves | NOT TESTED | | |

## Rear scene

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| R1 | Accepted front region → Rear scene | Same screen-fixed region shown on the rear image | NOT TESTED | | |
| R2 | Rear touchscreen drawing: Start → draw on the image → lift or Finish → Accept | Region created directly on the rear view | NOT TESTED | | |
| R3 | Normal Live | Copy only, **no blur** | NOT TESTED | | |
| R4 | Original / Simulated blur / Simulated blur + copy | Same viewport; persistent "Simulated blur — demonstration only" label | NOT TESTED | | |
| R5 | Copy samples original pixels | Copy is sharp while its source is blurred | NOT TESTED | | |
| R6 | Destination overlaps the region or leaves the view | "No valid placement — original view", no clamping | NOT TESTED | | |
| R7 | Camera stall (cover the lens vs. background the app) | Stall → "Scene unavailable"/"Paused"; a covered lens with fresh frames is not a stall | NOT TESTED | | |

## Orientation

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| O1 | Portrait | Same layout as before #18 | NOT TESTED | | |
| O2 | Landscape left and right, front and rear | Image upright; fingertip dot on the finger; 4:3 camera on the left | NOT TESTED | | |
| O3 | Rotate mid-stroke or after Accept | Treated as a layout change (stroke or region resets) | NOT TESTED | | |

## System

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| S1 | Camera permission denied → allow → Retry | Clear message, clean recovery | NOT TESTED | | |
| S2 | Interruption (Control Center, call, lock) | No stale stroke, copy or blur | NOT TESTED | | |
| S3 | Stop / Retry / mode switches | No stale cursor, stroke, patch or blur | NOT TESTED | | |
| S4 | Device Hub / mirroring open | Expect a black preview; close it (known cause) | NOT TESTED | | |
