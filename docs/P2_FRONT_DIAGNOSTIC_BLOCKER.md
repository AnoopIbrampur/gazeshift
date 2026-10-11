# Front diagnostic run — physical gate not passed

Recorded 2026-10-11. **Evidence provenance: user-reported physical run, not agent-observed.** This preserves the latest diagnostic report under the unchanged [P2 contract](../BUILD_PROMPTS.md#p2--calibrate-and-validate-real-eye-movement). The [earlier front and rear reports](P2_REAR_GAZE_BLOCKER.md) remain separate historical evidence.

## Build and setup provenance

- Installed source from the verified installation context: `d19aa5cd1cf8af1b20ccf817766cfb6f800d83c8`; known installed build: `P2-0.1-1011.16.36`. The pasted report itself contains no build marker.
- Device from the supplied installation/user context: Anoop's iPhone 15 Pro Max, iOS 27.0. The report identifies `frontSetup`, portrait, viewport 398.0 × 360.0 pt, scale 3.0, and setup `capture-generation-7-origin-16.0-236.0`.
- Earlier distance: about 10 inches (approximately 25 cm), user-reported and not measured. The user subsequently confirmed that the phone was **held in hand**. Head stability was requested but was not independently observed or measured.
- Documentation baseline: combined main `8783b3e6e2afb5786fb17d6a29c208fb8ead8d62`, independently reviewed with 99 passing software tests and a successful build in the supplied verification context. The phone ran the isolated diagnostic source above, without the combined flow repair; those main-branch checks do not validate this physical run.
- No new phone test, install, Device Hub action, or agent-observed display recording accompanies this documentation.

## Human clarification and visibility limit

The user first said, “it showed up from the start this time,” then explicitly identified that dot as the **mint estimated-gaze dot**. The user also said, “i dont see a whit target ever”. These are user reports; white target visibility and fixation on displayed calibration/evaluation targets are **not established**. The first statement does not establish restored white-target visibility or resolve the report as a white-versus-mint misunderstanding.

The user later described the current heading as “evaluagted, complte gate not passws” (interpreted as **Evaluated · complete gate not passed**). That identifies the reported current screen as the results state, where the mint estimated-gaze dot is expected. It resolves the apparent current mint-versus-active-test-state contradiction; it does not verify historical white-target presentation or fixation during the recorded run.

A subsequent bounded same-fit target-visibility check could not start: the user reported, “ut says i hsce to calibrate again”. The user was instructed not to recalibrate. That UI check is **BLOCKED because recalibration was required**, not a target-visibility test PASS or FAIL. White-target visibility remains unverified; no cause of the recalibration requirement is established by this report.

The app's reported **protocol: PASS** records its structural/timing checks. It does not prove that the user saw or looked at the displayed targets. Accordingly, this run is not established as a controlled target-fixation accuracy trial. Preserve the failed computed scores, but do not use them to assign a sensor/model cause or assert measured accuracy under verified fixation.

## Computed result and ruling

**Numerical: NOT PASSED; complete: NOT PASSED; protocol: PASS as reported by the app. Eye-only response: not tested.** Formal eye-only evidence is separately absent; that missing response does not cause the computed numerical failure.

The viewport diagonal is approximately 536.66 pt. The unchanged limits are median ≤53.7 pt and p90 ≤107.3 pt, overall and for every novel window. The app reports novel median **178.4 pt (33.2%)** and p90 **221.6 pt (41.3%)**, both over their limits. All eight novel windows have 19/20 valid predictions (95%), totaling 152/160 valid, with eight `outsideWindow` rejections. All eight novel-window medians and p90 values exceed their respective limits. The two center controls also have 19/20 valid predictions and remain excluded from novel accuracy. Insufficient valid-slot coverage does not explain the computed failure; high coverage does not establish target visibility or fixation.

Relative to the app's recorded target coordinates, all ten reported signed median `dy` components are positive under the report's **+right/+down** convention. Each novel left-target window has positive median `dx`, while each novel right-target window has negative median `dx`, an inward horizontal bias at those recorded positions. These are descriptive component medians, not verified eye-motion directions or a root-cause diagnosis; combining component medians does not recreate the radial-error median. They do not prove head movement, a flipped axis, or a sensor/model defect.

Keep the existing features, fit, scoring, thresholds, timing and phase gates unchanged. Physical P2 remains unpassed in front and rear modes. The separately requested same-fit target-visibility check was blocked before starting; no additional accuracy result is recorded here. This record makes no gaze-dependent P3/P4 implementation, end-to-end demonstration, clinical mapping, or patient-benefit claim.

## Full verbatim front diagnostic user report

```text
GazeShift experimental display-gaze test
Mode: frontSetup; portrait; viewport 398.0 × 360.0 pt; scale 3.0
Setup: capture-generation-7-origin-16.0-236.0
Viewing distance/head stability: requested, not measured automatically
Training samples by target (9 required): [58, 58, 58, 57, 58, 56, 57, 55, 57]
Observational diagnostics only: signed errors and raw features do not change the fit, scoring or declared accuracy gates.
Features: face-relative eye-midpoint → lookAtPoint direction ratios → personal affine fit → view points
Normalized view = points / viewport; drawing pixels = points × scale. Camera-image UV transform is separate.
Timing: host monotonic capture estimates; UI target acknowledgement; no measured photon latency
Each window: 0.5s settle + exactly 1s; 20 slots / 50ms. Late/missing slots are rejected, never extended.
Gate: each novel window ≥80% valid and ≥10 distinct predictions; median ≤10%, p90 ≤20% diagonal, overall and per window; timed interleaved center controls plus eye-only pass.
Numerical: NOT PASSED; protocol: PASS; complete: NOT PASSED
Eye-only response (entered by user): not tested
Novel total: received 152, valid 152/160, rejected 8; median 178.4pt (33.2%), p90 221.6pt (41.3% diagonal)
Novel rejections: outsideWindow=8
Training target 1 (0.15, 0.15 normalized): raw h mean 0.0388845, population SD 0.00169174; v mean -0.014485, population SD 0.00304178
Training target 2 (0.5, 0.15 normalized): raw h mean 0.0397783, population SD 0.00126388; v mean -0.00471783, population SD 0.00152857
Training target 3 (0.85, 0.15 normalized): raw h mean 0.0392641, population SD 0.00682338; v mean -0.00966638, population SD 0.00352971
Training target 4 (0.15, 0.5 normalized): raw h mean 0.0542187, population SD 0.00347829; v mean -0.0187124, population SD 0.00216497
Training target 5 (0.5, 0.5 normalized): raw h mean 0.0625472, population SD 0.00393757; v mean -0.0264502, population SD 0.00184255
Training target 6 (0.85, 0.5 normalized): raw h mean 0.0525374, population SD 0.00373272; v mean -0.0304654, population SD 0.00166735
Training target 7 (0.15, 0.85 normalized): raw h mean 0.0264644, population SD 0.00225928; v mean -0.0446464, population SD 0.00140957
Training target 8 (0.5, 0.85 normalized): raw h mean 0.0186566, population SD 0.00562823; v mean -0.0454653, population SD 0.00460564
Training target 9 (0.85, 0.85 normalized): raw h mean 0.0326113, population SD 0.00119497; v mean -0.042286, population SD 0.00472639
Center controls are reported separately and excluded from novel accuracy:
pass 1 upperLeft: received 19, valid 19/20, rejected 1; median 227.9pt (42.5%), p90 282.5pt (52.6% diagonal); outsideWindow=1
  signed median dx 124.7pt, dy 189.2pt (+right/+down); raw h mean 0.069339, population SD 0.00369855; v mean -0.0400031, population SD 0.00451757
  presented 6651.900; capture window [6652.400, 6653.400) host seconds
pass 1 upperRight: received 19, valid 19/20, rejected 1; median 172.5pt (32.2%), p90 221.6pt (41.3% diagonal); outsideWindow=1
  signed median dx -78.2pt, dy 153.8pt (+right/+down); raw h mean 0.0652526, population SD 0.00372573; v mean -0.028268, population SD 0.0114433
  presented 6653.435; capture window [6653.935, 6654.935) host seconds
pass 1 centerControl: received 19, valid 19/20, rejected 1; median 103.3pt (19.2%), p90 141.0pt (26.3% diagonal); outsideWindow=1
  signed median dx 28.8pt, dy 98.8pt (+right/+down); raw h mean 0.0731731, population SD 0.00452479; v mean -0.038615, population SD 0.00415653
  presented 6654.962; capture window [6655.462, 6656.462) host seconds
pass 1 lowerLeft: received 19, valid 19/20, rejected 1; median 169.7pt (31.6%), p90 203.9pt (38.0% diagonal); outsideWindow=1
  signed median dx 135.8pt, dy 97.3pt (+right/+down); raw h mean 0.0703737, population SD 0.00389316; v mean -0.0543193, population SD 0.0036195
  presented 6656.479; capture window [6656.979, 6657.979) host seconds
pass 1 lowerRight: received 19, valid 19/20, rejected 1; median 162.9pt (30.4%), p90 171.5pt (32.0% diagonal); outsideWindow=1
  signed median dx -59.3pt, dy 151.6pt (+right/+down); raw h mean 0.0697101, population SD 0.00167454; v mean -0.0608135, population SD 0.0012544
  presented 6657.984; capture window [6658.484, 6659.484) host seconds
pass 2 upperLeft: received 19, valid 19/20, rejected 1; median 186.5pt (34.8%), p90 207.8pt (38.7% diagonal); outsideWindow=1
  signed median dx 120.0pt, dy 142.8pt (+right/+down); raw h mean 0.0641328, population SD 0.00234336; v mean -0.0334749, population SD 0.00176772
  presented 6659.514; capture window [6660.014, 6661.014) host seconds
pass 2 upperRight: received 19, valid 19/20, rejected 1; median 176.2pt (32.8%), p90 202.9pt (37.8% diagonal); outsideWindow=1
  signed median dx -70.5pt, dy 161.9pt (+right/+down); raw h mean 0.0730004, population SD 0.00271391; v mean -0.0306798, population SD 0.00844181
  presented 6661.030; capture window [6661.530, 6662.530) host seconds
pass 2 centerControl: received 19, valid 19/20, rejected 1; median 158.0pt (29.4%), p90 237.8pt (44.3% diagonal); outsideWindow=1
  signed median dx 29.0pt, dy 154.7pt (+right/+down); raw h mean 0.0634164, population SD 0.00912543; v mean -0.0499526, population SD 0.007196
  presented 6662.552; capture window [6663.052, 6664.052) host seconds
pass 2 lowerLeft: received 19, valid 19/20, rejected 1; median 177.8pt (33.1%), p90 209.0pt (38.9% diagonal); outsideWindow=1
  signed median dx 132.3pt, dy 117.6pt (+right/+down); raw h mean 0.0630459, population SD 0.00311731; v mean -0.0572488, population SD 0.00429324
  presented 6664.081; capture window [6664.581, 6665.581) host seconds
pass 2 lowerRight: received 19, valid 19/20, rejected 1; median 200.4pt (37.3%), p90 222.8pt (41.5% diagonal); outsideWindow=1
  signed median dx -56.9pt, dy 192.7pt (+right/+down); raw h mean 0.0687784, population SD 0.0026778; v mean -0.0643896, population SD 0.00618859
  presented 6665.598; capture window [6666.098, 6667.098) host seconds
Finite offscreen predictions remain in accuracy scores; the live dot rejects them. Missing features (including a failed finite-feature conversion) are missingQuality. Raw unavailable camera samples are missing.
Computed from app inputs; this report does not prove physical eye-only movement, clinical retinal mapping, patient benefit, or a playable device demonstration.
```
