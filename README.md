# GazeShift

GazeShift is a working title for an experimental assistive-vision project: use eye tracking to move an image transformation with a person's gaze, exploring whether important visual content could eventually be shifted toward usable peripheral vision when central vision is impaired.

**Current status: documentation only. No prototype exists yet.** This private repository preserves the project idea and six-hour hackathon plan. On 2026-10-11, the GitHub connector successfully identified the private repository and read `PROJECT_CONTEXT.md`; a working demo and clinical benefit remain unverified.

## The first demo

On an iPhone 13, first use the front camera to track a finger tracing an outline in the air while the user fixates a stationary reference. Review a bounding ellipse as an explicit approximation of that outline. Then switch the same ARKit session to the rear scene plus face/eye tracking, recalibrate gaze, and copy the original-image rectangle covering the approximate region to one user-chosen offset. Preserve the region's offset from fixation; reject unavailable, overlapping or off-screen placements. The copy affects only the phone display and can cover existing destination content.

The immediate success condition is **actual camera-tracked air tracing followed by live eyes driving patch relocation**. Touchscreen tracing, head movement or a scripted marker cannot substitute for these inputs. Normal live assist adds no artificial blur; an optional observer simulation stays separate. Record the actual device as evidence. If rear-camera input falls back to prerecorded video, label it and retain live gaze. The added gesture and recalibration work makes the six-hour estimate optimistic.

The longer-term idea is glasses or a headset for people with residual vision and central vision loss, such as age-related macular degeneration. A phone experiment can test the interaction; it cannot establish a medical correction or prove patient benefit.

## Project documents

- [Project context and working instructions](PROJECT_CONTEXT.md): durable context for ChatGPT and future contributors.
- [Six-hour build plan](SIX_HOUR_PLAN.md): time budget, first-device go/no-go gate, tests, and demo evidence.
- [Incremental build prompts](BUILD_PROMPTS.md): copyable native ARKit prompts for setup and every six-hour phase, with acceptance checks and resource links; Vercel is an optional later companion site.
- [Private GitHub repository](https://github.com/Hussain-coder-eng/gazeshift).
- [ChatGPT project](https://chatgpt.com/g/g-p-6acbc5e009008191a0d00a958ec143d0/project).

## Evidence and boundaries

Gaze estimates and an air-drawn outline do not map a person's retina. Patient scotoma shape, offset, preferred retinal locus (PRL), clinical calibration, and bilateral viewing remain separate research problems. This controlled, healthy-user demo uses a user-drawn approximate region. Copied content moves with gaze and may move again when looked at; it is a peripheral-viewing experiment. It does not diagnose disease, restore normal sight, replace prescriptions or demonstrate a cure. Compare future user benefit against ordinary magnification before claiming improvement.

Apple documents [combined user face tracking and world tracking](https://developer.apple.com/documentation/arkit/combining-user-face-tracking-and-world-tracking) and the face-relative [`lookAtPoint`](https://developer.apple.com/documentation/arkit/arfaceanchor/lookatpoint) estimate. Research on [PRL and video calibration](https://pmc.ncbi.nlm.nih.gov/articles/PMC5714047/), [simulated image remapping](https://pmc.ncbi.nlm.nih.gov/articles/PMC5830989/), and [stability limits](https://pmc.ncbi.nlm.nih.gov/articles/PMC5381883/) informs the experiment; simulated results do not establish patient efficacy.
