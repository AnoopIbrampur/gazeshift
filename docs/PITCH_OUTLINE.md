# Pitch and demo outline (ANO-13)

Draft for the manual, screen-fixed demo. Replace brackets with what was actually shown on the phone. Don't claim anything the recording doesn't show.

## 60-second pitch

1. **Problem.** Central vision loss (for example macular degeneration) blocks the middle of what someone sees, which makes reading and recognizing things hard.
2. **Idea.** Mark the blind area, then show a copy of what's hidden there somewhere you can still see.
3. **What we built today.** An iPhone app (ARKit + Vision + Metal) where you:
   - **draw the blind area** with your index finger in the air (front camera) or directly on the rear camera image,
   - review it as an ellipse and accept it,
   - see it **blurred with a simulated blind spot**, and a **copy of what's under it** placed where you choose,
   - compare Original / Simulated blur / Simulated blur + copy, upright in portrait or landscape.
4. **What we learned.** We first tried driving the region with **eye tracking**. On this phone, front-camera gaze was off by ~85–160 pt (the limit was ~54 pt), so we pivoted to a screen-fixed region and kept the gaze work as diagnostics. [Mention only if asked or as a "what's next".]
5. **Honest limits.** A healthy-user experiment. The drawn shape is an approximation, not a retinal map. It stays fixed on screen, while a real blind spot moves with the eyes. The copy covers other content. Not a medical device.
6. **Next.** Better gaze or head-mounted hardware so the region can follow the eyes; clinical mapping; comparison against ordinary magnification.

## Demo shot list

1. Front setup: index finger → **Start drawing** → trace → **Finish shape** → review → **Accept region**.
2. Choose the copy offset with the arrows.
3. **Rear scene**: the blurred region and the copy on the real world. Optionally draw directly on the rear image instead.
4. Switch Original / Simulated blur / Simulated blur + copy, with the label visible.
5. Optional: turn the phone horizontal to show the upright landscape layout. Draw and demo in one orientation.
6. Play the recording back once to confirm it works.

## Wording rules

- Say "experiment", "healthy-user demo" and "simulated". Never say "cure", "restores sight" or "treatment".
- Label any prerecorded scene as recorded.
- Quote numbers only from the docs (gaze errors are in `docs/P2_*`).
