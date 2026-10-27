# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Added — photo step after the tutorial
- The last tutorial step's button is now a camera: it opens the photo screen in the same `TutorialScreen` (`GuidedTutorialModel.photoMode`,
  shared camera session, no restart). The camera shows brow, blush and eyeliner in the Try On shades, with no guide dots and no zoom.
  The palette button (bottom left) cycles the frame pink / blue / white; the bolt toggles a white screen flash. Shutter takes the AR view
  snapshot with the liner composed on it and shows it as a polaroid (`Features/Tutorial/PhotoCaptureViews.swift`): retake, share (ShareLink,
  the polaroid image) and done. Photos stay in memory. Not yet checked on a real device (build only).

### Changed — eyeliner tutorial: key points, one step, zoom
- The eyeliner tutorial draws only key points on each eye (line start, line end at the outer corner and, for the winged look, the wing
  tip) instead of an outline. They follow a pulled lid (`LinerOverlayModel.followsPulledLid`: lid tracking and quicker smoothing).
  The tutorial has one step, "Follow the dots", and uses the look chosen on Try On (`TutorialHandoff.linerLook`).
- Try On and the tutorial camera card can be zoomed (pinch or the zoom chip, 1x-3x); overlays scale with the picture.
- Fixes: a mask hid the left eye's guide; Try On kept taking the shared face session back from the tutorial; brow/blush work ran per frame
  without a launch fit (lag); the old blush surface renderer ran when no brow configuration was passed.
- Debug builds skip the launch scan (`AppNavigator.debugSkipsLaunchScan`). Not checked on a real device.

### Added — eyeliner looks: line only or with wing
- Try On eyeliner has "Liner only" (no wing) and "With wing" (default); the no-sign button is the third state. `LinerLook` and
  `EyelinerPlanner.style(_:look:)` choose the style: winged runs sideways from the outer corner (horizontal base, 6-10 deg lift) and always
  has at least the classic cat-eye wing length. Per-shape wing lengths/angles follow the reference sheet.
- Wing elevation limit 80 -> 24 deg and wing skin-anchor reach 0.8 -> 0.1 so the wing no longer points steeply up.
- Liner ink is darker and less see-through (`maxOpacity` 1.0, `inkReflectance` 0.05, `skinBleed` 0.04). Not checked on a real device.

### Changed — colour sheet follows the design
- The shade row's last button is a "+" again. It opens `PaletteColorPicker` as the design's two steps: "Snap Your Product" (live back camera,
  `ProductCamera`, shutter) then "Pick Your Colour" (drag the pin, retake, colour preview, confirm). A picked colour shows as an extra
  swatch. Photos stay in memory. When the camera is denied or missing, the sheet offers "Choose from Photos". The sampler (`PalettePhoto`)
  is unchanged. Not checked on a real device.
### Changed — tutorial screen follows the design
- `AppRoute.recommendedTutorial(TutorialHandoff)` now opens `Features/Tutorial/GuidedTutorialView`: the face camera in a rounded card, back
  and next arrows, the logo, the step wording in a card at the bottom of the camera, and Brows / Eyeliner / Blush tabs. Back/next move
  between steps and leave the tutorial at either end. There are no settings here: shade and strength come from Try On through
  `TutorialHandoff` (all tools), so changing them means going back. The brow mapping lines are on for Brows.
- Eyeliner now has a tutorial (steps follow the fitted `LinerStyle`; dotted outline drawn from `LinerOverlayRenderer`). Not checked on a real device.
- The Try On arrow passes a `TutorialHandoff`; an eyeliner without an eye scan still goes to the eye scan first.
- Tutorial wording that mentioned the removed refit / Before / hide-guide controls was reworded.

### Changed — eyeliner without a clear eye scan
- Home keeps the thin natural liner available (colour row and intensity enabled) when the eye scan is missing or unclear; it says "Natural line" instead of a fitted style. Brow and blush still need a saved face scan.

### Fixed — Try On camera lag after merging eyeliner with blush/brow
- `FaceCameraState` no longer re-publishes unchanged values every 0.1 s (`update(_:_:)`), which re-rendered the camera card constantly.
- `LinerFrameRelay` drops frames at once while eyeliner is off, instead of hopping to the main thread 60 times a second.
- MediaPipe landmarks run at most 30 Hz and the hand-occlusion mask at most 15 Hz (`FrameThrottle`); the overlay still follows the head every frame.
- The face-mesh triangle list is copied once per face, not on every SceneKit frame.
- Not yet measured on a device: confirm on a Face ID iPhone, with eyeliner off and on. Tunables: `LinerOverlayModel.landmarkThrottle`/`occlusionThrottle`.

### Performance — reduce try-on stalls -Nimah
- Ignore identical replayed analysis outputs before republishing state; preserve user on/off choices.
- Recolour cached pigment materials without rebinding mesh attachments. Use a triangle spatial index for first binding.
- Skip hidden guide node creation/animation and avoid intermediate per-frame position/index arrays.
- Budget shared-camera eyeliner delivery to 30 Hz; brow/blush controls no longer republish unchanged eyeliner settings.
- Signed Release build provided for device testing; no live FPS/transition-latency improvement measured yet.


### Fixed — startup preparation failure -Nimah
- Collect bounded fitting attempts throughout the initial scan instead of trusting one final frame; keep valid fits across later rejected frames.
- Fit actual brow contours when optional pupil/nose formula landmarks are unavailable; retain strict legacy formula behavior.
- Stop treating neutral eyeliner as an overall preparation failure. Preserve existing results and allow partial continuation if fitting fails.
- Mark unfitted pigment unavailable instead of silently enabling layers that cannot render. No extra scan is added to try-on.


### Fixed — scan only at launch -Nimah
- Require fresh face/eye analysis on every cold launch; keep only the welcome-completed preference across launches.
- Build transient brow/cheek fitting from the initial face scan and transfer it into try-on and tutorials, including
  recreated AR sessions. No per-feature Vision scan, hold-still gate, or scan instructions in that path.
- Enable all assigned makeup layers on entry. Disable launch Skip and keep unusable preparation at startup.
- Remove try-on rescan controls/profile rescan actions and skip the legacy eyeliner Vision placement phase.
- Core face/eye classification and Hanum liner mathematics are unchanged; live camera tracking remains necessary.


### Fixed — visible brow and blush pigment -Nimah
- Keep the brow input in the layered snapshot when blush is enabled; a ready status could previously coexist with no brow rendering.
- Increase pigment core alpha/default strength, narrow the feather and raise patches above the depth mesh to reduce clipping.
- Preserve recommendations, chosen RGB, comparison and user intensity controls. Device visual acceptance still required.

### Added — Profile page
- `ProfileView` (profile button): face shape, eye shape and signature look, with the face portrait and eye strip taken from the scans.
- `ScanSnapshots` keeps one small JPEG per scan on device (not backed up, never uploaded); privacy copy and `AGENTS.md` updated.
- `AppRoute.fullScan` / `FullScanFlow`: the retake button runs the face scan then the eye scan in one go.

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
