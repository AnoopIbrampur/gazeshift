# P5 physical challenge matrix (ANO-22)

Preparation only: **no completed physical P5 run is recorded here**. Fill in during the actual run. Every row ends as **PASS**, **FAIL** or **NOT TESTED**, with evidence. Simulator and fixture results cannot close any row.

## Session record

| Field | Value |
|---|---|
| Date / time | NOT TESTED — record actual run |
| Device / iOS | NOT TESTED — record actual device and version |
| App build marker | NOT TESTED — record running binary |
| Git commit | NOT TESTED — record build's commit |
| Viewport origin / size (pt), scale / orientation | NOT TESTED — record actual measured viewport |
| `viewingSetupID` | NOT TESTED — record actual setup |
| Viewing distance (cm), stand / handheld | NOT TESTED — record actual arrangement |
| Lighting | NOT TESTED — record actual conditions |
| Operator (holds phone) / recorder | NOT TESTED — record actual participants |
| Evidence location (videos, logs) | NOT TESTED — record playable/inspectable evidence |

Provenance key: **A** = agent-observed (log or screen recording), **U** = user-reported, **X** = external camera recording.

## Calibration and drift

| # | Challenge | Expected | Result | Evidence / provenance | Repair |
|---|---|---|---|---|---|
| C1 | Front 9-target calibration + held-out | Report shows coverage, median/p90, per-window rejections; complete gate needs the eye-only pass | NOT TESTED | | |
| C2 | Rear (final-mode) recalibration + held-out | Fresh fit after the switch; old front fit not reused | NOT TESTED | | |
| C3 | Eye-only movement, head still | Marker / region / patch follow the eyes | NOT TESTED | | |
| C4 | Drift: repeat held-out after 5 min, no recalibration | Report new median/p90 next to C2 | NOT TESTED | | |
| C5 | Head moves / phone distance changes | Calibration invalidated, redo required (change `viewingSetupID`) | NOT TESTED | | |
| C6 | Look off-screen | Finite off-screen errors counted; live view drops to original | NOT TESTED | | |

## Air trace (front)

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| T1 | Pinch, trace closed outline, return, release, eyes on `+` | Candidate with raw trace + ellipse; Accept enabled | NOT TESTED | | |
| T2 | Eyes leave `+` mid-stroke | Whole stroke cleared ("eyes left the reference"); Redo | NOT TESTED | | |
| T3 | Blink on a source frame skipped by Vision | Stroke clears immediately without waiting for a matching hand result; later pairs/release cannot save it | NOT TESTED | | |
| T4 | Hand leaves frame / occluded, or hand results expire while camera frames continue | Stroke clears on missing result or watchdog expiry, even without another completion | NOT TESTED | | |
| T5 | Finger occludes eyes on a frame without a Vision completion | Stroke clears immediately, no invented gaze; explicit Redo required | NOT TESTED | | |
| T6 | Open stroke (no return) | Rejected "did not return to its start" | NOT TESTED | | |
| T7 | Tiny stroke (<20 points) | Rejected "too few points" | NOT TESTED | | |
| T8 | Accept → switch to rear | Region retained only through the reviewed same-display transition; live gaze needs new calibration | NOT TESTED | | |

## Live relocation and comparison (rear)

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| L1 | Normal Live | Copy only, **no blur** | NOT TESTED | | |
| L2 | Original / Simulated blur / Simulated blur + copy, same viewport | Identical size and origin; persistent "Simulated blur — demonstration only" label | NOT TESTED | | |
| L3 | Live eyes in Blur + copy | Mask and patch move together | NOT TESTED | | |
| L4 | Copy samples original pixels | Patch is sharp even though the source region is blurred | NOT TESTED | | |
| L5 | Destination overlaps region (+p90 gap) | "No valid placement — original view", no clamping | NOT TESTED | | |
| L6 | Source or destination at screen edge | Rejected, no shrinking | NOT TESTED | | |
| L7 | Gaze loss (blink, face out) | Copy and blur cleared immediately; "Tracking unavailable — original view" | NOT TESTED | | |
| L8 | Off-screen loss → in-view recovery | Layers return only after 3 distinct fresh calibrated in-view predictions, with the scene independently fresh | NOT TESTED | | |
| L9 | Actual stalled source: timestamps stop advancing | After expiry, stale scene and adaptive layers clear; "Scene unavailable", no frozen-live frame | NOT TESTED | | |
| L10 | Cover rear lens while timestamps continue advancing | Fresh dark/occluded frames are distinguished from a source stall; this cannot pass L9 | NOT TESTED | | |
| L11 | Background the app / session interruption | "Paused"; stale scene and adaptive layers clear | NOT TESTED | | |

## System

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| S1 | Camera permission denied → allow → Retry | Clear message, clean recovery | NOT TESTED | | |
| S2 | Interruption (Control Center, call, lock) | Stroke and copy cleared; generation advances on a new run | NOT TESTED | | |
| S3 | Stop / Retry / mode switches | No stale cursor, stroke, patch or blur | NOT TESTED | | |

## Rates (sample age is not end-to-end latency)

| Metric | Value | Method |
|---|---|---|
| ARKit frame rate (front / rear) | NOT TESTED | Record actual method |
| Vision hand result rate | NOT TESTED | Record actual method |
| Gaze update rate | NOT TESTED | Record actual method |
| Sample age p50 / p90 / max (ms) | NOT TESTED | Record actual method |
| Display latency (only with an independent visible reference) | NOT TESTED | Record actual method |
