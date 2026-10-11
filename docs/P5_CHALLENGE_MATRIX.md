# P5 physical challenge matrix (ANO-22)

Fill in during the physical run. Every row ends as **PASS**, **FAIL** or **NOT TESTED**, with evidence. Simulator and fixture results cannot close any row.

## Session record

| Field | Value |
|---|---|
| Date / time | |
| Device / iOS | iPhone 15 Pro Max / iOS 27.x |
| App build marker | |
| Git commit | |
| Viewport (pt) / scale / orientation | / 3× / portrait |
| `viewingSetupID` | |
| Viewing distance (cm), stand / handheld | |
| Lighting | |
| Operator (holds phone) / recorder | Hussain / Anoop |
| Evidence location (videos, logs) | |

Provenance key: **A** = agent-observed (log or screen recording), **U** = user-reported, **X** = external camera recording.

## Calibration and drift

| # | Challenge | Expected | Result | Evidence / provenance | Repair |
|---|---|---|---|---|---|
| C1 | Front 9-target calibration + held-out | Report shows coverage, median/p90, per-window rejections; complete gate needs the eye-only pass | | | |
| C2 | Rear (final-mode) recalibration + held-out | Fresh fit after the switch; old front fit not reused | | | |
| C3 | Eye-only movement, head still | Marker / region / patch follow the eyes | | | |
| C4 | Drift: repeat held-out after 5 min, no recalibration | Report new median/p90 next to C2 | | | |
| C5 | Head moves / phone distance changes | Calibration invalidated, redo required (change `viewingSetupID`) | | | |
| C6 | Look off-screen | Finite off-screen errors counted; live view drops to original | | | |

## Air trace (front)

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| T1 | Pinch, trace closed outline, return, release, eyes on `+` | Candidate with raw trace + ellipse; Accept enabled | | | |
| T2 | Eyes leave `+` mid-stroke | Whole stroke cleared ("eyes left the reference"); Redo | | | |
| T3 | Blink mid-stroke | Stroke cleared | | | |
| T4 | Hand leaves frame / occluded mid-stroke | Stroke cleared | | | |
| T5 | Finger occludes eyes | Stroke cleared, no invented gaze | | | |
| T6 | Open stroke (no return) | Rejected "did not return to its start" | | | |
| T7 | Tiny stroke (<20 points) | Rejected "too few points" | | | |
| T8 | Accept → switch to rear | Region kept (same display), live gaze needs new calibration | | | |

## Live relocation and comparison (rear)

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| L1 | Normal Live | Copy only, **no blur** | | | |
| L2 | Original / Simulated blur / Simulated blur + copy, same viewport | Identical geometry; persistent "Simulated blur — demonstration only" label | | | |
| L3 | Live eyes in Blur + copy | Mask and patch move together | | | |
| L4 | Copy samples original pixels | Patch is sharp even though the source region is blurred | | | |
| L5 | Destination overlaps region (+p90 gap) | "No valid placement — original view", no clamping | | | |
| L6 | Source or destination at screen edge | Rejected, no shrinking | | | |
| L7 | Gaze loss (blink, face out) | Copy and blur cleared immediately; "Tracking unavailable — original view" | | | |
| L8 | Recovery | Layers return only after 3 distinct fresh valid samples | | | |
| L9 | Camera stall (cover lens / background the app) | "Scene unavailable" / "Paused", no frozen-live frame | | | |

## System

| # | Challenge | Expected | Result | Evidence | Repair |
|---|---|---|---|---|---|
| S1 | Camera permission denied → allow → Retry | Clear message, clean recovery | | | |
| S2 | Interruption (Control Center, call, lock) | Stroke and copy cleared; generation advances | | | |
| S3 | Stop / Retry / mode switches | No stale cursor, stroke, patch or blur | | | |

## Rates (sample age is not end-to-end latency)

| Metric | Value | Method |
|---|---|---|
| ARKit frame rate (front / rear) | | |
| Vision hand result rate | | |
| Gaze update rate | | |
| Sample age p50 / p90 / max (ms) | | |
| Display latency (only with an independent visible reference) | | |
