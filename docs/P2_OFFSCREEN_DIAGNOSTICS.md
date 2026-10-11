# White-target offscreen failure and observational diagnostics

2026-10-11. Evidence is user-reported, not an agent-observed physical run. The user confirmed following the moving **white circle during both nine-target calibration and ten-window evaluation**, with the phone held in hand throughout the first run below. This is separate from the earlier [target-visibility-limited report](P2_FRONT_DIAGNOSTIC_BLOCKER.md); that historical record remains unchanged.

Both subsequent reports identify frontSetup, portrait, 398 × 360 pt, scale 3. The session's installation context identifies the current 17.29 app; the pasted reports themselves do not contain a build marker.

| User-reported condition | Training samples by target | Novel valid slots | Median / p90 | Computed protocol / numerical / complete |
| --- | --- | --- | --- | --- |
| Handheld; white circle followed | 21, 21, 20, 20, 20, 20, 20, 21, 20 | 133/160 (83.1%) | 487.6 pt (90.9%) / 560.3 pt (104.4%) | NOT PASSED / NOT PASSED / NOT PASSED |
| Subsequent comparison following instructions to prop phone upright on a stable object/table, about 25 cm away, keep head position, follow white circle | 21, 21, 20, 21, 19, 20, 20, 19, 19 | 130/160 (81.25%) | 153.7 pt (28.6%) / 234.0 pt (43.6%) | PASS / NOT PASSED / NOT PASSED |

Eye-only response remained not tested in both. The handheld novel rejections were missedSchedule=21 and outsideWindow=6; the comparison had missedSchedule=20 and outsideWindow=10. Late ticks establish missed scheduled slots, not low camera FPS. Supporting the phone changed a reported condition; it did not measure pose or establish a cause for the difference.

The handheld evaluation vertical-feature means all lay outside the calibration target means. The comparison also showed center-feature shifts and poorer second-pass results. These describe captured inputs, not proof of a flipped axis, phone motion, retinal mapping, or a particular sensor/model defect. Shared eye-feature conversion, fit, point geometry and held-out thresholds remain unchanged.

The diagnostic build adds optional same-frame camera-relative AR face transform, anchor identity, configured AR video FPS, thermal state, and source/main/consumer delivery summaries to the existing report. Each existing training target and evaluation window has a bounded summary; no images or raw frame history are saved. Counter spans cover first-to-last available observations and explicitly cannot recover exact window-boundary totals. Configured FPS is not a measured frame rate; estimated capture-to-main age is not end-to-end display latency. AR camera-relative pose is not calibrated physical-screen or retinal registration.

The first verbatim report is retained in ignored local evidence with SHA256 `7b3db4152790cc1c8ee15cd077fedf62975162b496c7bf2cedd456bb50747730`. No accuracy correction, automatic movement gate, new target sequence, or clinical claim is introduced. The diagnostic source still requires independent review, a physical-device run, and an actual working demonstration before those outcomes can be claimed.
