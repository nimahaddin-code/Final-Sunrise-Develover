# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Fixed — Try On camera lag after merging eyeliner with blush/brow
- `FaceCameraState` no longer re-publishes unchanged values every 0.1 s (`update(_:_:)`), which re-rendered the camera card constantly.
- `LinerFrameRelay` drops frames at once while eyeliner is off, instead of hopping to the main thread 60 times a second.
- MediaPipe landmarks run at most 30 Hz and the hand-occlusion mask at most 15 Hz (`FrameThrottle`); the overlay still follows the head every frame.
- The face-mesh triangle list is copied once per face, not on every SceneKit frame.
- Not yet measured on a device: confirm on a Face ID iPhone, with eyeliner off and on. Tunables: `LinerOverlayModel.landmarkThrottle`/`occlusionThrottle`.

### Added — reference colours and palette picker -Nimah
- Blush presets: Pink, Peach, Winter Pink, Muted Mauve. Brows: Bistre, Brown, Chocolate, Tan, Soft black.
  RGB values approximate the supplied photos; they are not measured brand shade matches.
- Enable the home eyedropper: manual colour picker, Photos import or rear-camera palette capture, then tap a colour.
  Downsample and orient images off the UI thread; sample only inside the displayed photo. Cancel leaves the shade unchanged.
- Pause/dismantle face tracking while the picker uses the camera; keep photos in memory, without uploads/library writes.
- Add explicit Before/After and carry shade/intensity from try-on directly into the recommended eyebrow/blush tutorial.


### Fixed — scan-assigned makeup results -Nimah
- Eyebrow/blush now expose one stable local-catalog assignment from the saved face scan, with provenance; remove
  style/source exploration and block unsupported defaults. Eyeliner exposes only the personal eye-scan result.
- Refresh home assignments after a rescan and clear stale layers for absent data. Keep shades/intensity/comparison.
- Connect the home tutorial arrow and profile scan/results routes; cancel late camera startup off-screen.
- Integrate latest remote Eyeliner-Hanum (431a9e5). Other available team branch heads are already ancestors.
- Reference coverage is incomplete for pear/rectangle; no recommendation is invented. Real-device validation pending.


### Changed — eyeliner realism (grain and skin tint)
- On top of the multiply blend and bleed halo: the pigment picks up 12% of the skin tone read from a few camera pixels around
  the eyes every 8 frames, and a fixed speckle (`LinerInk`) lifts the ink unevenly so skin texture shows through; the speckle
  is anchored to the eye's inner corner so it moves with the face. Live canvas and photos match. Not yet checked on a real face.

### Changed — Try On home redesign
- New single home screen `Features/TryOnHome/TryOnHomeView`: header (profile, wordmark, arrow), rounded live camera card, three
  tool tiles (blush, eyeliner, eyebrow), a shade row (none, swatches, "+" disabled for now) and an intensity bar. Palette tokens
  `AppColors.wine/cocoa/flamingo/snow` (#660033, #5F2C30, #F5477D, #FFFFFF).
- The tab bar is gone: after onboarding the app opens on this screen. `AppRoute.profile` and `.tutorial` open blank placeholder pages
  (`BlankPageView`) until the design team's screens exist. Discover and My Looks are no longer reachable.
- Each tool swaps the engine inside the card (blush/eyebrow: `EyebrowViewModel` + `LiveGuideView`; eyeliner: `MakeupTryOnViewModel`);
  only the selected engine runs. `TryOnHomeModel` owns them.
- `EyebrowConfiguration.shadeTint` lets the blush/eyebrow preview use the chosen shade (`FaceRegionPreviewRenderer`).
- One shared camera: the home screen runs a single ARKit session (`LiveGuideView`) and the eyeliner overlay (`LinerOverlayModel`) is fed
  the same frames (`LiveGuideView.onFrame`, `LinerFrameRelay`). Switching tools no longer swaps cameras; each tool has its own on/off,
  shade and intensity, and blush, eyebrow and eyeliner can show together (`EyebrowConfiguration.layered`, `PreviewLayer`, a second
  preview renderer for blush). `MakeupTryOnViewModel` is no longer used by the home screen.
- Logo asset `logo-burgundy` replaces the text wordmark; the intensity bar has a draggable thumb.
- Face/eye rescan cards and the eyeliner "Take photo" / "Place again" buttons are not on the new screen yet. Not checked on a TrueDepth iPhone.

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
