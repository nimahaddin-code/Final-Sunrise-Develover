# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Added
- Scan Debug bulk export: the tab keeps every scan taken this session in memory (a newer scan of the same outline no longer replaces the older one in the
  list), with "Export all N for Mac" that shares all of them as `.sunrisescan` files, per-scan Edit / share / remove, and "Share all saved files" for the
  raw and corrected JSON files. The single "Export for Mac" button stays. Scans are not kept after the app closes.
- Scan Debug **Export for Mac**: a share button that sends the scan picture, the raw points and the corrected points so far as one `.sunrisescan` file
  (`ScanDebugExportFile`, JPEG inside the JSON; AirDrop works). Debug-only exception to the no-pictures rule: it happens only on that tap, through the
  system share sheet. New exported type `com.sunrise.scan-debug` in `Info.plist`. `ScanDebugStore.use(directory:)` added for the Mac editor.
- `SunriseDebugMac/`: a separate macOS Xcode project (Sunrise Scan Editor) with no scanning. It opens exported scans (file, folder, drop or double-click),
  lets you drag or arrow-key nudge the points with zoom, undo, reset and revert, and saves `<kind>-<name>.raw.json` and `.corrected.json` to a chosen folder.
  It builds and launches with a sample file; the editor screen and a real AirDrop hand-off have not been checked.
- Scan Debug: Undo (one step per drag, also after Reset) and Cancel (full screen: drops everything moved since opening it) for both face and eyes. The
  eye correction screen turns landscape while open. This needed landscape in `Info.plist` and an app delegate (`AppOrientationDelegate`, wired in
  `SunriseApp`) that keeps every other screen portrait. Not yet run on a device.
- Scan Debug: an expand button on the contour preview opens it full screen for correcting, with pinch or +/- zoom (1x to 8x), scrolling when zoomed, a Raw / Corrected switch and Reset. Points keep their size at every zoom.
- Eyelid picker explains each choice (`EyeLid.detail`): what you see in the mirror for visible crease, hooded and monolid, plus a mirror tip.
- Scan Debug tab (`Features/ScanDebug`, `AppTab.scanDebug`, one `NavigationStack` in `AppRootView`): runs the same face scan and eye scan screens
  as onboarding. When a scan finishes, "Use this scan" turns the points that scan drew (`ScanSnapshot` overlay, read by
  `ScanDebugSnapshotReader`) into raw points: 10 for the face, 14 for the eyes. Drag them to correct, then review Raw / Corrected / Final
  measurements and the classification from the app's own classifiers. Confirm saves two separate JSON files,
  `<face|eyes>-<name>.raw.json` and `<face|eyes>-<name>.corrected.json`, in Application Support/ScanDebug (never overwritten; shareable and
  deletable from the tab). Only point coordinates are saved, never the picture. Main-flow change: `FaceShapeView` and `EyeScanView` gained an
  optional `onResult` callback (default no-op) that passes the scan picture out; the debug tab scans into a throwaway `FaceShapeStore`, so the
  real results are untouched. The scan screens need a TrueDepth iPhone (face) or a front camera (eyes), so this has not been run on a device.
- Debug-only log of the face outline correction (`ContourCorrection.report`, logged from `FaceShapeViewModel` when a scan finishes, category
  `FaceContour`): per band the outline count, median, min, max and spread of the ratios, plus the proportions with and without the correction.
  Debug builds only; numbers only.
- Scan result pictures with the measured lines drawn on them, so the person can check the scan. The face result shows the camera picture
  with the face outline and the forehead, cheekbone and jaw widths and the length (`FaceGuide`, `FaceSnapshotter`, widths scaled by Vision's
  outline correction like the classifier does). The eye result shows a crop around the eyes with each eye's outline, corner line, opening,
  iris, brow and the gap between the eyes (`EyeOverlay`, `EyeFrameSnapshot`). Shared types: `ScanOverlay`, `ScanSnapshot`, `ScanOverlayView`.
  The pictures live in memory for the result screen only and are never saved. Geometry and cropping are unit tested; the live capture
  (`ARSCNView.snapshot` for the face, the camera frame for the eyes) has not been run on a device.
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
