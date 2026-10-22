# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Added
- Eye shape logic in `Features/EyeShape`: `EyeLandmarks` (with the MediaPipe mesh index mapping), `EyeMeasurer` and
  `EyeMeasurementsSampler`, `EyeShapeClassifier` and `EyeShapeResult`, with 17 unit tests on synthetic eyes. No camera, detector or UI yet.
- MediaPipe Tasks Vision 1.1.1 as a Swift Package (`google-ai-edge/mediapipe`, pinned to the `v1.1.1` revision, recorded in `Package.resolved`),
  groundwork for the eye shape scan. No app code uses it yet. Decision record: `Docs/Decisions/0002-mediapipe-eye-scan.md`.
- `AGENTS.md` (shared brief for AI-assisted coding), `CLAUDE.md` (imports it) and this changelog.
- `FaceAnalysis` (`Features/FaceShape/FaceAnalysis.swift`): the single entry point for face shape analysis, covering
  the live scan screen, a headless scanner, photo classification and the saved result. Documented in
  `Docs/IntegrationContracts.md` ("Analisis bentuk wajah").

### Changed
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
