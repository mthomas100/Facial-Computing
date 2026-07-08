# Facial Computing
Facial Gesture Analysis combining your persona and the computer [Vision Framework](https://developer.apple.com/documentation/vision) — including a real-time **emotion recognition engine** that names the emotion on your face.

https://github.com/user-attachments/assets/de45b118-8e11-429f-bce3-0d1883500a2b

## Emotion Recognition

The **Emotion** tab (default) runs a multi-expert pipeline over the Persona camera feed and announces one of eight emotions — Neutral, Happy, Sad, Surprised, Afraid, Angry, Disgusted, Contempt — with a live confidence ring, per-class probability bars, a valence/arousal circumplex pad, and a FACS "science" panel.

Pipeline (per frame, ~12–15 Hz):

1. **Vision landmarks** → roll-corrected, interocular-distance-normalized facial metrics (`FaceGeometry`), so measurements are invariant to head tilt, distance, and framing.
2. **FACS Action Units** — 14 AU intensities (AU1/2/4/5/6/7/9/12/15/20/23/25/26 + unilateral smirk) computed as deltas from *your* calibrated neutral baseline (`ActionUnits`).
3. **EMFACS classifier** — Ekman-style AU prototypes with inhibitor penalties and evidence gates, softmaxed into a probability distribution (`EmotionClassifier`).
4. **Neural expert** — a bundled **FER+** classifier (`Emotion/FERPlus.mlpackage` — Microsoft FERPlus, MIT license, 17 MB fp16, ~85% on the FER+ test set) scores an expanded face crop via `VNCoreMLRequest` and is fused log-linearly with the geometric expert (`MLEmotionScorer`). Labels are embedded in the model, so class order is irrelevant. Converted from the verified ONNX zoo release with `tools/convert_ferplus.py`; delete the model and the app gracefully runs geometry-only, or swap in any classifier named `EmotionAppearance`, `FERPlus`, `EmotionClassifier`, or `CNNEmotions`.
5. **Temporal layer** — EMA smoothing plus label hysteresis so the readout is stable, and probability-weighted valence/arousal on the circumplex (`TemporalSmoother`).

**Why it's accurate:** the engine auto-calibrates a neutral baseline from your first seconds on camera (re-run anytime with *Calibrate Neutral*, persisted across launches), gates evidence by landmark confidence and head pose, and slowly re-tracks the baseline while you're verifiably neutral. All expression evidence is therefore measured relative to your own face, not a population average.

The immersive space also carries an **emotion aura** — an inward-facing sphere tinted by the detected emotion, its intensity following confidence.

Debug builds run `EmotionSelfTests` at launch, asserting the classifier prototypes, hysteresis behavior, and distribution math.

Concise overview of the repository, with each project file and its responsibility.

## File Overview

- `README.md`: Project overview and file responsibilities (this document).
- `.gitignore`: Standard Swift/Xcode ignores (DerivedData, .build, etc.).
- `.DS_Store`: macOS Finder metadata (ignored by Git).
- `.git/`: Git metadata for version control.
- `Facial Computing.xcodeproj/`: Xcode project for building and running the app.
- `Packages/`: Swift Package Manager dependencies and resources.
  - `RealityKitContent/`: Local SPM package that provides RealityKit assets and a convenience bundle constant.
    - `Package.swift`: SPM manifest for the `RealityKitContent` package.
    - `Sources/RealityKitContent/RealityKitContent.swift`: Exposes `realityKitContentBundle` for loading assets.
    - `Sources/RealityKitContent/RealityKitContent.rkassets/SkyDome.usdz`: Sky dome model used by the immersive scene.
    - `Sources/RealityKitContent/RealityKitContent.rkassets/Immersive.usda`: Scene description used by Reality Composer Pro.
    - `Package.realitycomposerpro/`: Reality Composer Pro project data.

### App Target: Facial Computing

- `Facial Computing/Info.plist`: App configuration; declares immersive space scene role and camera usage descriptions.
- `Facial Computing/Facial_ComputingApp.swift`: App entry point. Creates the `ImmersiveSpace` scene and manages its lifecycle and immersion style.
- `Facial Computing/AppModel.swift`: App-wide observable state, including the immersive space identifier and open/closed state machine.
- `Facial Computing/ToggleImmersiveSpaceButton.swift`: SwiftUI button to open/dismiss the immersive space via environment actions.
- `Facial Computing/Permissions.swift`: Centralized camera permission helpers using AVFoundation.

#### Controllers

- `Facial Computing/Controllers/PersonaCaptureController.swift`: Manages AVFoundation capture from the front camera; exposes latest `CVPixelBuffer`, start/stop, per-frame callbacks, and an `AsyncStream` of frames.
- `Facial Computing/Controllers/VisionExpressionController.swift`: Uses Vision face landmarks to infer facial expressions (e.g., blinks, smiles); provides a simple detection model with confidence scores.

#### Emotion Engine

- `Facial Computing/Emotion/EmotionTypes.swift`: `Emotion` classes with display metadata and circumplex anchors; `EmotionDistribution`, `EmotionReading`, history samples.
- `Facial Computing/Emotion/FaceGeometry.swift`: Landmarks → roll-corrected, IOD-normalized `FacialMetrics` + overlay geometry.
- `Facial Computing/Emotion/ActionUnits.swift`: FACS AU intensity estimation vs. the calibrated `NeutralBaseline` (persisted).
- `Facial Computing/Emotion/EmotionClassifier.swift`: EMFACS AU-prototype scoring → softmax distribution.
- `Facial Computing/Emotion/TemporalSmoother.swift`: EMA + hysteresis label stabilization.
- `Facial Computing/Emotion/FaceAnalyzer.swift`: Actor running Vision landmark requests off the main actor.
- `Facial Computing/Emotion/MLEmotionScorer.swift`: Optional bundled Core ML appearance expert, fused when present.
- `Facial Computing/Emotion/EmotionEngine.swift`: Orchestrator — throttling, calibration, fusion, quality gating, published readings.
- `Facial Computing/Emotion/EmotionSelfTests.swift`: Debug-launch assertions for the pure emotion math.
- `Facial Computing/Emotion/FERPlus.mlpackage`: Bundled FER+ appearance model (Microsoft FERPlus, MIT; 64×64 grayscale in, 8 labeled probabilities out).
- `tools/convert_ferplus.py`: Reproducible ONNX→Core ML conversion (auto-pad materialization, opset upgrade, softmax + label embedding, fidelity notes).

#### Views

- `Facial Computing/Views/ContentView.swift`: Primary window UI; currently hosts the immersive space toggle button.
- `Facial Computing/Views/ImmersiveView.swift`: RealityKit `RealityView` for the immersive experience; loads `SkyDome`, hosts the emotion aura sphere, and attaches a floating controls panel.
- `Facial Computing/Views/ImmersiveControlsView.swift`: Floating SwiftUI controls surface shown inside space via `ViewAttachmentComponent`; hosts the Emotion dashboard plus the Persona/Vision/Frame demos.
- `Facial Computing/Views/PixelBufferView.swift`: Efficiently converts and previews `CVPixelBuffer` frames as images with throttling.
- `Facial Computing/Views/Emotion/EmotionDashboardView.swift`: The emotion tab — preview + overlay + calibration on the left, readouts on the right.
- `Facial Computing/Views/Emotion/EmotionHeroView.swift`: Big emoji, emotion name, animated confidence ring, FACS hint.
- `Facial Computing/Views/Emotion/EmotionBarsView.swift`: Animated probability bars for all classes.
- `Facial Computing/Views/Emotion/ValenceArousalPadView.swift`: Circumplex pad with a fading trail of recent readings.
- `Facial Computing/Views/Emotion/AUMetersView.swift`: Live FACS Action Unit meters ("Science" toggle).
- `Facial Computing/Views/Emotion/EmotionTimelineView.swift`: 45-second emotion record strip.
- `Facial Computing/Views/Emotion/FaceLandmarkOverlay.swift`: Face box + landmark constellation over the aspect-fitted preview.

#### Assets

- `Facial Computing/Assets.xcassets/`: App image and color assets managed by Xcode.

## Build & Run

Open `Facial Computing.xcodeproj` in Xcode (visionOS 26 SDK). Select the Apple Vision Pro simulator or device and run.

## Notes

- The immersive scene uses `RealityView` (visionOS-appropriate) and loads assets from the local `RealityKitContent` package.
- Camera access is requested at runtime; see `Info.plist` usage descriptions and `Permissions.swift` for logic.
