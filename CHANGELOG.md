## Blush camera parity — -Nimah (2026-10-27)

Removed the extra horizontal reflection from both Metal camera sampling and mesh projection.
Blush now uses ARFrame displayTransform/projection directly to match the existing ARSCNView categories.
Keep camera and mesh transforms paired; do not introduce category-specific mirroring. Device acceptance pending.

## Native UV Metal blush — -Nimah (2026-10-27)

Primary blush engine is ARKit + Metal via BeautyBlushARView/BeautyBlushEngine, sharing the existing ARSession.
Shader source runtime-compiles once off-main from BeautyBlush.metal.txt. Author mask: blush-wash-mask.png;
separate validated render/tracking configuration: blush-rendering.json. Native UV atlas, native mesh depth
prepass, synchronized camera/pose, linear matte absorption/tint, local One Euro residual smoothing, pose/stretch
gating, and face-skin-only visibility from the existing MediaPipe multiclass segmenter. No second face tracker.
The old CPU grid remains only if Metal setup is unavailable (surfaced status); it is not the active blush path.
Camera/frame/mesh remain transient. Local metrics are scalar timing/state only. Screen pose is not double-smoothed.
Legacy Hanum segmenter default remains body-skin; faceSkinOnly is opt-in for blush. No paid SDK is installed.
See Docs/Decisions/0010-metal-blush.md for verified SDK comparison, dependencies and known occlusion limits.
Do not claim TikTok equivalence, 60 FPS, thin-brush occlusion or sustained performance without device evidence.

## Blush v0.2.1 device-feedback calibration — -Nimah (2026-10-27)

User confirmed v0.2.0 visible but requested wider/softer. Six active radii expand to 0.185–0.225 W by
0.120–0.135 W. Numeric upper range extended explicitly for major radius (0.24 W); no hidden multiplier.
JSON falloff_smoothstep_mix=1 smooths radial alpha; independent inward-safe mask transitions use 0.022 W.
Blush sampling grid increases to 48x32, cached on placement change. User shade/intensity and existing
brow/eyeliner settings remain unchanged. No extra try-on scan. Device acceptance of this revision pending.

## Blush JSON v0.2.0 integration — -Nimah (2026-10-27)

User preference: implement requested JSON revisions into the consuming app in the same task, including renderer
support, checks and build; do not leave an external JSON file disconnected. No automatic staging/main merge.
Bundled full database now merges the six wide-wash blush presets by stable ID. Preserve eyebrow v0.1.1 and all
Hanum eyeliner/scan/profile rules. Blush has wider radii, radial exponent 1.10–1.15, max alpha 0.44–0.48,
default intensity 0.72. Inward smooth mask feather is 0.012 of full face width, decoded and used in coverage.
One field per cheek; do not shrink its radii or use tutorial shapes as pigment. Existing skin bindings and
color-only update caching remain. Saved analysis is reused with no compulsory Retake. The visual target is
art-directed, not pixel-exact or device calibrated; existing lower-lid/hand/hair adapter limits remain.

## Brow size calibration v0.1.1 — -Nimah

Following user feedback, integration JSON increases brow design half-thickness from 3.5% to 6.5% of observed
brow width. Preserve measured head/tail and bounded arch adjustment; no guessed extension. This is an explicit
calibration revision to the bundled copy; the original research artifact remains unchanged. Device visual
acceptance pending. Hand/hair occlusion masking for brow/blush is still not implemented.

## Pigment visibility regression — -Nimah

Separate front-skin cosmetic compositing from native mesh depth occlusion. Keep partial valid brow strips and
independent blush pigment fields when peripheral guide samples fail. Add depth-occluder pixel regression and
local state-only rendering diagnostics. No new face scan or eyeliner formula change.

## JSON makeup integration — -Nimah (2026-10-26)

Integration previews consume bundled `Resources/makeup-reference.database.json` through `MakeupRuleDatabase`.
JSON assignments supersede historical A defaults: oval natural/cheekbone; round high arch/high cheekbone;
square rounded/apple; oblong straight/horizontal; heart low arch/center cheek; diamond soft arch/temple.
Uncovered rectangle/pear stay unavailable. Research draft is explicitly enabled for integration calibration only.
Brow local displacement, two cubic segments, taper, head fade, feather and pigment alpha use rule parameters.
Blush uses full face width, measured per-side eye centers and exact rotated elliptical alpha fields, without
bbox enlargement or tutorial V/dot silhouettes. Palette and initial strength use JSON; custom sampling remains.
No classification or Hanum eyeliner formulas change. No extra try-on scan. Existing saved fit remains usable.
Current adapter uses native ARKit face-local axes and conservative eye-center exclusion where eyelid contours
are absent. Hair/hand occlusion and measured lower-lid masks are not implemented for brow/blush; no production
calibration, product color accuracy or TikTok-equivalent quality is claimed. Device visual acceptance pending.

# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Fixed — Retake presentation from Profile -Nimah
- Present the complete face/eye enrollment flow above Profile using a full-screen cover, rather than pushing another NavigationStack.
- Cancel retains Profile; only successful completion returns to the try-on root.
- Navigation regression tests passed; physical-device routing and fitting acceptance remain pending.


### Fixed — Profile Retake fitting handoff -Nimah
- Confirmed on device that saved classifications existed but fitting descriptors were absent.
- Try portrait sensor orientations during enrollment and accept only anatomically validated projected brow contours.
- Prepare retakes in a separate candidate; persist/replace fitting only after success, retaining prior fit on failure/cancellation.
- Refresh fitting availability when returning to home even when classifications did not change.
- Device Retake and reopen verification pending; no silent removal of unavailable states.


### Changed — reuse completed analysis -Nimah
- Reopen directly into try-on when face and eye outputs are saved. Explicit Profile Retake updates them.
- Persist sparse fitting descriptors and restore against the live face; keep full meshes/frames in memory only.
- Make unavailable fitting on older installs explicit, with a Profile action rather than a forced repeat scan.
- Integrate Khalish scan progress/done feedback through b2d8ae0. Keep Hanum eyeliner branch and Profile integration.


### Fixed — cheek placement and soft pigment -Nimah
- Use a common face-local eye/nose reference for left/right cheek height and width; avoid independent noisy landmark offsets.
- Combine placement-dot guides into one filled pigment patch per cheek. Preserve tutorial shapes separately.
- Use continuous radial pigment falloff instead of an opaque center with only a feathered rim; soften brow pigment edges.
- Optional brow formula annotations no longer invalidate a valid observed brow fit.
- 47 relevant simulator tests passed. Real-face appearance and smoothness remain awaiting device verification.


### Fixed — category detector lifecycle -Nimah
- Keep the loaded eyeliner/hand models while switching categories; nil style hides output and prevents frame submission.
- Finish an in-flight warm-up when the category changes, avoiding a retained startup task that blocks returning to eyeliner.
- Stop and release detectors when leaving the screen. Hidden home/tutorial updates cannot start a second detector.
- Model formulas are unchanged. Physical-device transition latency still needs acceptance.


### Fixed — Xcode project loading -Nimah
- Remove duplicate project objects and group/source entries introduced by integration. Reopen the workspace to recover the editor.
- Keep the local app signing team for Nimah device builds. No makeup or scan formulas changed.


### Integrated — latest team work -Nimah
- Merge Hanum profile/eyelid details and eyeliner/tutorial updates; retain original source commits.
- Merge Khalish scan overlays, debug/export tools and Mac correction editor. Adapt shared routes and scan landmark naming.
- Keep launch-only makeup fitting, exclusive category visibility and local soft blush pigment changes.
- Device acceptance is pending; automated test results are recorded separately.


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
- Scan "done" confirmation out of the Dynamic Island (`DynamicIslandConfirmation`), mimicking the App Store / Apple Pay confirmation: a black shape over
  the hardware island grows into a rounded square, a green check draws itself (with the done sound and a success haptic), then it shrinks back. Drawn by
  the app in a window above the status bar, because iOS hides an app's own Live Activity from the island while the app is open and the system animation
  is not available to apps. The island position is estimated from the top safe area. iPhones without an island show `ScanDoneBadge` on the camera
  instead. The Live Activity now only covers leaving the app mid-scan and ends as soon as the scan finishes. Checked in the iOS 26.2 Simulator
  (iPhone 17 Pro) through a temporary launch hook; not yet on a device.
- Dynamic Island and done sound for the face and eye scans. New app extension target `SunriseLiveActivity` (bundle id `com.sunrise.foundation.LiveActivity`)
  shows the scan as a Live Activity: a progress ring while scanning, a green checkmark when done. `ScanActivityAttributes` is compiled into both
  targets, `ScanFeedback` (`.scanFeedback(title:progress:isDone:)`) starts, updates and ends it, and `ScanDoneSound` plays an original two-note chime
  (or `scan_done.caf` / `.wav` if one is added to the app). The done sound is the system's `payment_success.caf` when it exists, with the chime as fallback.. `NSSupportsLiveActivities` is set in `Info.plist`. Not checked on a device; the extension's
  text is English only.
- Scan done badge (`ScanDoneBadge`): when the face or eye scan finishes, a black rounded square with a green checkmark pops up over the camera with a
  success haptic, and the result sheet follows about 1.1 s later. The ring no longer plays the success haptic itself. Not checked on a device.
- Scan progress ring (`ScanProgressRing`) on the face and eye scan cards, replacing the linear bar: App Store-style ring with the percentage inside,
  a checkmark when done, a light haptic tick every 10% and a success haptic at the end. Applies to onboarding and Scan Debug too.
  Haptics and the look have not been checked on a device.
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
