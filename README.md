# GazeShift

GazeShift is a working title for an experimental assistive-vision project: use eye tracking to move an image transformation with a person's gaze, exploring whether important visual content could eventually be shifted toward usable peripheral vision when central vision is impaired.

**Current status: documentation only. No prototype exists yet.** This private repository preserves the project idea and six-hour hackathon plan. A working demo, clinical benefit, and a working ChatGPT–GitHub connector have not been verified.

## The first demo

On an iPhone 13, show the live rear-camera scene while using the front camera to estimate eye gaze. Calibrate those estimates to the physical screen, then apply one simple image warp around an adjustable, assumed or simulated blind-spot region that follows gaze in display coordinates. The transformation affects only the image shown on the phone.

The immediate success condition is **live eye movement driving a live image transformation**. Eye tracking is the priority; this is not a dwell-selection reading app. A recorded video of the actual device is the final demo evidence. If rear-camera input must fall back to prerecorded video, label it clearly and retain live gaze tracking. Head movement or a scripted marker cannot stand in for eye tracking.

The longer-term idea is glasses or a headset for people with residual vision and central vision loss, such as age-related macular degeneration. A phone experiment can test the interaction; it cannot establish a medical correction or prove patient benefit.

## Project documents

- [Project context and working instructions](PROJECT_CONTEXT.md): durable context for ChatGPT and future contributors.
- [Six-hour build plan](SIX_HOUR_PLAN.md): time budget, first-device go/no-go gate, tests, and demo evidence.
- [Private GitHub repository](https://github.com/Hussain-coder-eng/gazeshift).

## Evidence and boundaries

Gaze estimates do not map a person's retina. Patient scotoma shape, offset, preferred retinal locus (PRL), clinical calibration, and bilateral viewing remain separate research and validation problems. The first demo uses an explicitly assumed or simulated region, in a controlled seated setting. It does not diagnose disease, restore normal sight, replace prescriptions or inserts, or demonstrate a cure. Compare future user benefit against ordinary magnification before claiming improvement.

Apple documents [combined user face tracking and world tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) and the face-relative [`lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint) estimate. Research on [PRL and video calibration](https://pmc.ncbi.nlm.nih.gov/articles/PMC5714047/), [simulated image remapping](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/), and [stability limits](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/) informs the experiment; simulated results do not establish patient efficacy.
