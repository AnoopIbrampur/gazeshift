# Pitch and demo outline (ANO-13 prep)

Draft. Replace every bracket with measured results from P5 (docs/P5_CHALLENGE_MATRIX.md). Don't fill in a claim the evidence doesn't support.

## 60-second pitch

1. **Problem.** Central vision loss (for example AMD) leaves people relying on peripheral vision, which makes reading and recognising things hard.
2. **Idea.** Use eye tracking to find where someone is looking, take the part of the scene that would fall in their blind area, and show a copy of it where their vision still works.
3. **What we built today.** An iPhone app (ARKit + Vision) that:
   - calibrates gaze to the screen ([median / p90 error] on held-out targets),
   - lets you trace your approximate blind area **in the air with your finger** while fixating a reference point,
   - copies that part of the live rear-camera scene to an offset you choose, moving with your eyes,
   - shows Original / Simulated blur / Simulated blur + copy in the same view for comparison.
4. **Honest limits.** This is a healthy-user experiment. An air-drawn ellipse isn't a retinal map. The copy duplicates and covers other content. Content can move when you look at it (gaze chasing). [Rates / failure modes from P5.]
5. **Next.** Clinical scotoma/PRL mapping with professionals, wearable hardware, and a comparison against ordinary magnification before claiming any benefit.

## Demo recording shot list

1. Front setup: calibration dots + results screen (show the numbers).
2. Air trace: external camera of the hand drawing + phone screen showing trace → ellipse → Accept.
3. Switch to rear + recalibration.
4. Live: eyes move (head still) and the patch follows. External camera on the eyes if possible.
5. Demo comparison: Original → Simulated blur → Simulated blur + copy, with the label visible.
6. Failure / recovery: blink or look away → "Tracking unavailable — original view" → recovery.
7. Play the saved recording back once to confirm it works.

## Wording rules

- Say "experiment", "healthy-user demo" and "simulated". Never say "cure", "restores sight" or "treatment".
- Label any recorded (non-live) scene as recorded.
- Quote numbers only from the evidence log.
