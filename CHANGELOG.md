# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Integrated — -Nimah
- Saved face/eye results now drive recommendations: Nimah eyebrow/blush open preview and tutorial without a repeat
  scan step; Hanum eyeliner consumes the newer separate eye result. Live alignment remains automatic.
- Preserve off-UI-thread model startup for Hanum's newly merged optional hand-occlusion model.
- Merge latest Hanum eyeliner/lid-flow/hand occlusion and Khalish separate eye-scan/onboarding updates.
- Preserve Nimah-only eyebrow/blush routing and asynchronous eyeliner model lifecycle.
- Resolve scan/liner landmark type and output-file collisions with scan-specific naming; retain both test suites.

### Added
- Eye shape scan screen (`EyeScanView`, `EyeScanViewModel`, `EyeScanGuide`, `EyeShapeResultView`, `CameraPreviewView`, entry point
  `EyeAnalysis`). Onboarding is now welcome, face scan, eye scan, home. The face scan result's button reads "Next: scan your eyes" there. The
  Try On home has an eye card, and `AppRoute.eyeScan` rescans. The person picks their eyelid after the scan. `FaceShapeStore.eyes` keeps the
  latest result. Not yet checked on a real face; eye shape does not change recommendations yet.
- Eye scan plumbing: `MediaPipeEyeDetector` (Face Landmarker, video mode), `EyeCameraSession` (front camera, upright BGRA frames),
  the bundled `face_landmarker.task` model (3.76 MB, Google's float16 v1), and `EyeLandmarks.headTurn`. Tests load the model and run
  MediaPipe in the Simulator on a blank frame, and check the eye indices against MediaPipe's own tables.
- Eye shape logic in `Features/EyeShape`: `EyeLandmarks` (with the MediaPipe mesh index mapping), `EyeMeasurer` and
  `EyeMeasurementsSampler`, `EyeShapeClassifier` and `EyeShapeResult`, with 17 unit tests on synthetic eyes. No camera, detector or UI yet.
- MediaPipe Tasks Vision 1.1.1 as a Swift Package (`google-ai-edge/mediapipe`, pinned to the `v1.1.1` revision, recorded in `Package.resolved`),
  groundwork for the eye shape scan. No app code uses it yet. Decision record: `Docs/Decisions/0002-mediapipe-eye-scan.md`.
- `AGENTS.md` (shared brief for AI-assisted coding), `CLAUDE.md` (imports it) and this changelog.
- `FaceAnalysis` (`Features/FaceShape/FaceAnalysis.swift`): the single entry point for face shape analysis, covering
  the live scan screen, a headless scanner, photo classification and the saved result. Documented in
  `Docs/IntegrationContracts.md` ("Analisis bentuk wajah").

### Changed
- Simulator builds exclude x86_64 (MediaPipe ships no Intel-Simulator slice).
- Camera usage text mentions eye shape.
- Docs (`README.md`, `Architecture.md`, `Testing.md`) no longer say there are no external dependencies.
- `AppRootView` and `OnboardingView` use `FaceAnalysis` instead of `FaceShapeView` / `FaceShapeStore` directly.

## 2026-10-21 — Face shape scan and live makeup try-on (`aee8264`)

### Added
- Face shape scan: ARKit face tracking with head-pose gating, mesh proportions corrected by Vision's face outline,
  and a prototype classifier across 7 shapes. Single-photo path via Vision landmarks. The latest result is kept in
  `UserDefaults` (no images or meshes).
- Makeup try-on: eyebrow, blush and eyeliner recommendations per face shape, personalised "Made for you" styles, and
  a live AR try-on with shades, intensity and photo capture/share.
- Try On tab (home) with `makeupTryOn` and `faceScan` routes.
- Camera and photo-library-add usage descriptions in `Info.plist`.
- Unit tests for the classifier, measurers, head pose, recommender, personalization and texture geometry, plus an
  opt-in dataset accuracy eval.

### Changed
- Onboarding: the welcome screen leads into the face scan, and completion is persisted (shown once).

## 2026-10-14 — Project foundation

### Added
- SwiftUI scaffold: Discover and My Looks tabs, typed navigation with per-tab paths, mock services, design system,
  string catalog, unit tests, CI workflow and team docs (`Docs/`).
