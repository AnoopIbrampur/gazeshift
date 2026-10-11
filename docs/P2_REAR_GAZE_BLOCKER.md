# Front and rear gaze — physical gates not passed

Recorded 2026-10-11. **Evidence provenance: user-reported physical runs, not agent-observed.** This preserves the requested single supported rear repeat and subsequent fresh front comparison under the existing [P2 contract](../BUILD_PROMPTS.md#p2--calibrate-and-validate-real-eye-movement).

Later evidence: the [front diagnostic report on installed source d19aa5c](P2_FRONT_DIAGNOSTIC_BLOCKER.md) also has failed computed numerical/complete gates. For that later run, the user confirmed a handheld phone and the mint estimated-gaze dot, and reported seeing no white target. Its app-reported protocol PASS does not establish visible-target fixation. The two original reports below are preserved unchanged; both physical gates remain unpassed.

## Build and setup provenance

- Installed source: `4c789554200cf6e833aa4e2d0d52386ca15aa63b`; build marker: `P2-0.1-1011.15.59`.
- Device from verified install context: Anoop's iPhone 15 Pro Max, iOS 27.0. The pasted reports identify `rearLive` and `frontSetup`, both portrait, with their actual viewport/setup IDs.
- Earlier viewing-distance report: about 10 inches (approximately 25 cm), user-reported. Phone support and a still head were requested for this repeat; neither was independently observed or measured. The app does not measure them automatically.
- Device Hub was to remain closed by instruction. A live camera feed was previously user-confirmed; this report is not a new agent-observed camera or eye-motion recording.
- Documentation baseline: main `ef5cd47792417f36b8d2d4b31a898673710b60c8`. Its reviewed offline flow fixes, 62 passing software tests and successful build do not pass physical P2 or establish that those prepared flow components run on this installed build.

## Interpretation and ruling

**Both front and rear numerical gates: NOT PASSED. Both complete gates: NOT PASSED. Both protocols: PASS as reported by the app.** The shared viewport diagonal is approximately 536.66 pt, so the unchanged limits are median ≤53.7 pt and p90 ≤107.3 pt, overall and for every novel window.

| Mode | Novel valid | Novel median | Novel p90 | Numerical / complete |
| --- | --- | --- | --- | --- |
| Front setup | 152/160 (95%) | 85.3 pt (15.9%) | 103.8 pt (19.3%) | NOT PASSED / NOT PASSED |
| Rear live | 152/160 (95%) | 159.9 pt (29.8%) | 282.3 pt (52.6%) | NOT PASSED / NOT PASSED |

Every reported novel and center-control window in both modes has 19/20 valid predictions (95%). The reports mark the protocols passed; insufficient valid samples do not explain either numerical failure. Front aggregate errors are smaller than rear errors, but all eight front novel-window medians exceed 10% of the diagonal. The front pass-1 upper-right p90 is also over its limit at 129.7 pt (24.2%). Passing the front aggregate p90 alone cannot pass the gate.

Rear errors are not confined to lower targets: upper-left median rises from 50.4 pt to 292.4 pt between passes, and the separate center-control median rises from 70.2 pt to 180.2 pt. Front center-control median rises from 6.0 pt (1.1%) to 47.4 pt (8.8%), suggesting a change over that run. These radial error magnitudes alone cannot establish the direction of error, head drift, or a sensor/model cause.

The formal eye-only response is **not tested** in both reports; a passing response has not been entered. This independently leaves the complete gates unpassed and is not the cause of the numerical failures. The user qualitatively reported that up/down worked pretty well while left/right movement was insufficient. This is a subjective observation, not measured signed horizontal/vertical errors or a formal eye-only pass.

Following P2's instruction to repeat calibration once and then document a continuing failure, record the failed rear repeat and front comparison as blockers rather than expand the model. Keep the feature set, profiles and thresholds unchanged; do not reuse the rear fit in front mode, substitute fake gaze, or claim physical P3/P4 success. Offline flow preparation remains separate and uninstalled on the recorded device build; software checks do not authorize gaze-dependent air mapping or live composition.

The requested fresh **front Setup → Calibrate → Test** comparison has now been reported and failed. It is no longer pending. Both physical numerical gates remain unpassed; no additional phone test is requested in this record.

## Full verbatim rear user report

```text
GazeShift experimental display-gaze test
Mode: rearLive; portrait; viewport 398.0 × 360.0 pt; scale 3.0
Setup: capture-generation-10-origin-16.0-236.0
Viewing distance/head stability: requested, not measured automatically
Training samples by target (9 required): [59, 59, 59, 59, 59, 59, 59, 57, 58]
Features: face-relative eye-midpoint → lookAtPoint direction ratios → personal affine fit → view points
Normalized view = points / viewport; drawing pixels = points × scale. Camera-image UV transform is separate.
Timing: host monotonic capture estimates; UI target acknowledgement; no measured photon latency
Each window: 0.5s settle + exactly 1s; 20 slots / 50ms. Late/missing slots are rejected, never extended.
Gate: each novel window ≥80% valid and ≥10 distinct predictions; median ≤10%, p90 ≤20% diagonal, overall and per window; timed interleaved center controls plus eye-only pass.
Numerical: NOT PASSED; protocol: PASS; complete: NOT PASSED
Eye-only response (entered by user): not tested
Novel total: received 152, valid 152/160, rejected 8; median 159.9pt (29.8%), p90 282.3pt (52.6% diagonal)
Novel rejections: outsideWindow=8
Center controls are reported separately and excluded from novel accuracy:
pass 1 upperLeft: received 19, valid 19/20, rejected 1; median 50.4pt (9.4%), p90 305.4pt (56.9% diagonal); outsideWindow=1
  presented 4360.420; capture window [4360.920, 4361.920) host seconds
pass 1 upperRight: received 19, valid 19/20, rejected 1; median 174.2pt (32.5%), p90 179.9pt (33.5% diagonal); outsideWindow=1
  presented 4361.932; capture window [4362.432, 4363.432) host seconds
pass 1 centerControl: received 19, valid 19/20, rejected 1; median 70.2pt (13.1%), p90 81.2pt (15.1% diagonal); outsideWindow=1
  presented 4363.434; capture window [4363.934, 4364.934) host seconds
pass 1 lowerLeft: received 19, valid 19/20, rejected 1; median 63.4pt (11.8%), p90 86.5pt (16.1% diagonal); outsideWindow=1
  presented 4364.949; capture window [4365.449, 4366.449) host seconds
pass 1 lowerRight: received 19, valid 19/20, rejected 1; median 164.4pt (30.6%), p90 181.5pt (33.8% diagonal); outsideWindow=1
  presented 4366.468; capture window [4366.968, 4367.968) host seconds
pass 2 upperLeft: received 19, valid 19/20, rejected 1; median 292.4pt (54.5%), p90 307.4pt (57.3% diagonal); outsideWindow=1
  presented 4367.996; capture window [4368.496, 4369.496) host seconds
pass 2 upperRight: received 19, valid 19/20, rejected 1; median 227.0pt (42.3%), p90 261.6pt (48.7% diagonal); outsideWindow=1
  presented 4369.499; capture window [4369.999, 4370.999) host seconds
pass 2 centerControl: received 19, valid 19/20, rejected 1; median 180.2pt (33.6%), p90 204.1pt (38.0% diagonal); outsideWindow=1
  presented 4371.002; capture window [4371.502, 4372.502) host seconds
pass 2 lowerLeft: received 19, valid 19/20, rejected 1; median 146.2pt (27.2%), p90 162.7pt (30.3% diagonal); outsideWindow=1
  presented 4372.518; capture window [4373.018, 4374.018) host seconds
pass 2 lowerRight: received 19, valid 19/20, rejected 1; median 148.0pt (27.6%), p90 159.5pt (29.7% diagonal); outsideWindow=1
  presented 4374.033; capture window [4374.533, 4375.533) host seconds
Finite offscreen predictions remain in accuracy scores; the live dot rejects them. Missing features (including a failed finite-feature conversion) are missingQuality. Raw unavailable camera samples are missing.
Computed from app inputs; this report does not prove physical eye-only movement, clinical retinal mapping, patient benefit, or a playable device demonstration.
```

## Full verbatim front user report

```text
GazeShift experimental display-gaze test
Mode: frontSetup; portrait; viewport 398.0 × 360.0 pt; scale 3.0
Setup: capture-generation-16-origin-16.0-236.0
Viewing distance/head stability: requested, not measured automatically
Training samples by target (9 required): [57, 57, 57, 57, 58, 57, 57, 57, 57]
Features: face-relative eye-midpoint → lookAtPoint direction ratios → personal affine fit → view points
Normalized view = points / viewport; drawing pixels = points × scale. Camera-image UV transform is separate.
Timing: host monotonic capture estimates; UI target acknowledgement; no measured photon latency
Each window: 0.5s settle + exactly 1s; 20 slots / 50ms. Late/missing slots are rejected, never extended.
Gate: each novel window ≥80% valid and ≥10 distinct predictions; median ≤10%, p90 ≤20% diagonal, overall and per window; timed interleaved center controls plus eye-only pass.
Numerical: NOT PASSED; protocol: PASS; complete: NOT PASSED
Eye-only response (entered by user): not tested
Novel total: received 152, valid 152/160, rejected 8; median 85.3pt (15.9%), p90 103.8pt (19.3% diagonal)
Novel rejections: outsideWindow=8
Center controls are reported separately and excluded from novel accuracy:
pass 1 upperLeft: received 19, valid 19/20, rejected 1; median 99.0pt (18.4%), p90 106.8pt (19.9% diagonal); outsideWindow=1
  presented 4796.847; capture window [4797.347, 4798.347) host seconds
pass 1 upperRight: received 19, valid 19/20, rejected 1; median 104.1pt (19.4%), p90 129.7pt (24.2% diagonal); outsideWindow=1
  presented 4798.393; capture window [4798.893, 4799.893) host seconds
pass 1 centerControl: received 19, valid 19/20, rejected 1; median 6.0pt (1.1%), p90 24.9pt (4.6% diagonal); outsideWindow=1
  presented 4799.897; capture window [4800.397, 4801.397) host seconds
pass 1 lowerLeft: received 19, valid 19/20, rejected 1; median 92.7pt (17.3%), p90 102.5pt (19.1% diagonal); outsideWindow=1
  presented 4801.427; capture window [4801.927, 4802.927) host seconds
pass 1 lowerRight: received 19, valid 19/20, rejected 1; median 73.1pt (13.6%), p90 75.1pt (14.0% diagonal); outsideWindow=1
  presented 4802.944; capture window [4803.444, 4804.444) host seconds
pass 2 upperLeft: received 19, valid 19/20, rejected 1; median 81.6pt (15.2%), p90 82.9pt (15.4% diagonal); outsideWindow=1
  presented 4804.465; capture window [4804.965, 4805.965) host seconds
pass 2 upperRight: received 19, valid 19/20, rejected 1; median 77.0pt (14.3%), p90 88.9pt (16.6% diagonal); outsideWindow=1
  presented 4805.995; capture window [4806.495, 4807.495) host seconds
pass 2 centerControl: received 19, valid 19/20, rejected 1; median 47.4pt (8.8%), p90 65.0pt (12.1% diagonal); outsideWindow=1
  presented 4807.519; capture window [4808.019, 4809.019) host seconds
pass 2 lowerLeft: received 19, valid 19/20, rejected 1; median 95.7pt (17.8%), p90 101.7pt (18.9% diagonal); outsideWindow=1
  presented 4809.045; capture window [4809.545, 4810.545) host seconds
pass 2 lowerRight: received 19, valid 19/20, rejected 1; median 83.1pt (15.5%), p90 87.9pt (16.4% diagonal); outsideWindow=1
  presented 4810.562; capture window [4811.062, 4812.062) host seconds
Finite offscreen predictions remain in accuracy scores; the live dot rejects them. Missing features (including a failed finite-feature conversion) are missingQuality. Raw unavailable camera samples are missing.
Computed from app inputs; this report does not prove physical eye-only movement, clinical retinal mapping, patient benefit, or a playable device demonstration.
```
