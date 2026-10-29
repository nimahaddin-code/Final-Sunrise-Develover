## ARKit pose for the brow, and the 3D hair brow — Khalish (2026-10-28)

Details in `Docs/Decisions/0015-arkit-brow-pose.md`. `BrowFaceStabilizer` lifts MediaPipe's brow landmarks onto ARKit's face
mesh (same frame's anchor), smooths them in face-local metres and projects them back (fallback: the image-space smoother when
ARKit has no face or disagrees). "Brow 3D" (`BrowOverlay.is3D`) draws `brow-hair-3d.obj` ribbons on ARKit's pose with a depth-only
face mesh pass, 1.5 px minimum hair width, ambient-light shading and the hand mask; it falls back to its picture without a tracked
face. New shader code is only checked at runtime: compile `BeautyBlush.metal.txt` with `MTLDevice.makeLibrary(source:)` (a build
does not) and run the tests, which fail every engine test if it does not compile. Device check pending.

## Brow overlay pictures — Khalish (2026-10-28)

The eyebrow tool draws a chosen PNG brow (`BrowOverlay.all`, image sets `brow-overlay-N` in `Assets.xcassets`, head left,
tail right, alpha) over the hidden natural brow. `BrowOverlayPicker` lists them horizontally under the tool strip, after a "no overlay" tile (`browOverlay == nil`: no picture, natural-brow hiding unchanged). Try On
now starts with "Landmarks" off and "Natural brow" off (hidden); both toggles stay as test switches. `BrowSpriteBaker` bakes
a picture off the render queue into the existing brow-space texture (u 0...1 = its head-to-tail span, one picture width =
one brow width, drawn in chord space: `BrowGeometry.chordOffset` adds the user's own brow rise when the strip samples it, so the
picture keeps its own arch; strands stay visible through the shade via the texture's alpha channel = relative luminance).
`EyebrowConfiguration.browOverlay` (nil in the tutorial, which still shows tracking only) turns on the shape pass
(`browPigment` is gone; it follows the overlay). Initial eyebrow intensity is 0.9. To add a brow: add an image set and a
`BrowOverlay` entry. The older `BrowStylePicker`/`BrowDesign` shapes stay, unused while `showsBrowTracking` is on.
Simulator tests only; device look pending.

## Black screen background — Khalish (2026-10-28)

`AppColors.screen` (black) is the full-screen background of Try On, the tutorial, the palette sheet and placeholder
pages; `AppColors.wine` stays for pills and accents.

## Brow tracking view — Khalish (2026-10-27)

`EyebrowConfiguration.showsBrowTracking` (currently `true`) hides the brow shapes and the shape picker; the eyebrow
tool and the tutorial Brows tab show MediaPipe's tracking instead. The Metal engine draws, on the same frame as the
landmarks: all 478 face points (dim white), raw brow points before smoothing (grey), smoothed upper (red) and lower
(orange) brow contours, the fitted centerline (yellow), the brow frame where a shape would be drawn (cyan, green ticks
at head/middle/tail) and eye corners, iris, alae and nose bridge. `BrowTrackingOverlayView` labels each point with
its MediaPipe index and shows yaw/pitch/roll, landmark latency and rate (English-only developer view, fed by
`FaceCameraState.browTracking`). Set the flag to `false` to bring the shapes and picker back. Device check pending.
Test toggles under the eyebrow tool (`TryOnHomeModel.browLandmarksVisible` / `naturalBrowVisible`): "Landmarks"
shows/hides the whole tracking overlay (points, contours, lines, labels, readout). "Natural brow" off hides the user's
own eyebrow (`EyebrowConfiguration.hideNaturalBrow`) through `BrowEraser` (ADR 0014): each brow is unwrapped into a
brow-space texture array (`browUnwrapFragment`), a blurred skin estimate is pulled from mip level 4 up, pixels around
the brow clearly darker than it are the real brow edge (`browHairFragment`, beyond MediaPipe's rows, never past the
eyelid bound) and join the hide mask, then the brow is filled by push-pull without them, given full-resolution
forehead texture (`browFillFragment`, always on), blended frame to frame, and laid back by the brow strip. `BrowInpainter` adds MI-GAN (Core ML, bundled `Resources/MIGANFace256.mlpackage`, MIT, notice in
`Resources/MI-GAN-LICENSE.txt`, reproduce with `Tools/MIGAN/convert_migan_coreml.py`) on an upright face crop every
0.12 s, cached in brow space and faded over the push-pull fill. Area: `concealUpper` /
`concealLower` (lower end ≤85% of the way to the eyelid row `BrowEyeMarks.lid`), long head/tail fades. Hands stay in
front (face-skin mask). This is the only place the
natural brow is erased, and only while that toggle is off; it is a test, not checked on a device. The readout's yaw/pitch/roll are turned to
the screen (`BeautyBlushEngine.screenPose`): MediaPipe's matrix follows the sensor, which read roll near -90° in portrait.

## New brow shape list — Khalish (2026-10-27)

The old eight brow presets (natural, soft/high/low arch, angular, rounded, straight, lifted) and the thin/feathered
modifiers are gone. `EyebrowStyle` is now nine shapes in picker order, following the user's TikTok effect screenshot
(shape categories only, no assets copied): boldArch, slimArch, softNatural, flatStraight, curvedArch, peakedAngle,
slimStraight, fullArch, boldStraight, each a `brow.*` preset in makeup-reference.database.json (source `brow_D`).
Default/oval look is softNatural. Face-shape assignments map to the nearest new shape (round bold arch, square curved
arch, oblong flat straight, heart slim straight, diamond slim arch). Picker thumbnails draw the real `BrowDesign`.
Parameters are engineering proposals; device look acceptance pending.

## Eyebrow on MediaPipe — Khalish (2026-10-27)

The eyebrow try-on/tutorial no longer uses the ARKit mesh or Vision. `MediaPipeBrowTracker` (Face Landmarker, live
stream, transformation matrix on) runs on the shared ARKit camera frames; `BeautyBlushEngine` draws each frame with
its own landmarks (`submitBrow`/`renderBrow`). `BrowObservation` holds brow contours, eye/nose points and
`BrowHeadPose`; `BrowObservationSmoother` filters them; `BrowGeometry` lays a brow-local strip over each brow;
`BrowDesign` turns the style's rule fields into a brow-space curve, baked into a mipmapped texture. Overlay only, same
face-skin occlusion. Original brow pixels are segmented in the shader ("Original brow mask" debug view), not erased.
Tutorial guide outline and nose-eye mapping lines are drawn in Metal; the SceneKit brow guide is only the fallback.
Blush is unchanged (ARKit mesh + Vision fit). `MediaPipeBrowTracker.swift` is a fourth file importing MediaPipe.
See `Docs/Decisions/0013-mediapipe-eyebrow.md`. Simulator tests only; device QA pending. Sections below that
describe the brow on the ARKit mesh, `BeautyBrowStabilizer` or the brow UV atlas predate this.

## Eyebrow switching and tutorial comparison — 2026-10-27

Style changes retain the last committed brow atlas while the new native UV bake is prepared. Failed bind attempts are throttled, while a new requested style resets that throttle and is attempted on the next frame. In the tutorial Brows split comparison, hide placement and mapping outlines so the filtered half compares pigment with the real brow cleanly; the full-filter tutorial still exposes its guide.

## Brow overlay only, anti-blink, debug views — Khalish (2026-10-27)

Per `eyebrow_filter_rendering_fix.md` (Option B): the brow is an overlay, the natural brow is NOT erased. The earlier erase/inpaint
(vertical skin bridge) made horizontal bands and a soft rectangular patch over the brow area and was removed. Composite is straight
alpha, `result = mix(camera, hair, browAlpha)`; browAlpha is zero outside the baked brow, so other pixels are the camera pixel
(fixture test checks this). Strand density floor .35 so skin shows between strands. Each brow is fitted per side from its own
Vision points (`EyebrowGuideGenerator`); camera/mesh mirroring is the existing paired displayTransform/projection.
Anti-blink: brow keeps the last face-skin mask for up to `browMaskGraceSeconds` (0.3 s) instead of dropping out at 150 ms;
brow pixels count as occluded only when skin 9 mm above or below is too (the segmenter often rejects brow hair). Blush unchanged.
Debug: with developer tools on (long-press the logo) and eyebrow selected, a ladybug menu on the camera card picks
`BrowDebugView` (`beautyBrow.debugView`): final, original, landmarks (brow points + eye centers), fit contours (design edge cyan,
observed centerline yellow), alpha mask (white on black), texture only (on grey). English-only, like Scan Debug. Device QA pending.

## Brow style picker — Khalish (2026-10-27)

With the eyebrow tool selected, `TryOnHomeView` shows `BrowStylePicker`: all 8 database brow styles (`EyebrowViewModel.browStyleChoices`,
database order) in one horizontal row under the tool strip. `chooseBrowStyle` sets `configuration.style`, which the live pipeline already
re-fits and re-bakes. Default stays natural. Not carried into the tutorial handoff. Checked on Simulator UI only; live render needs a device.

## Face/eye scan removed from the flow — Khalish (2026-10-27)

The app opens straight on `TryOnHomeView`: no welcome, onboarding, face scan, eye scan, Profile, Retake or
Scan Debug tab. Routes `faceScan`, `eyeScan`, `fullScan`, `profile`, `scanDebug` and `AppTab.scanDebug` are gone,
as are `AppNavigator` onboarding/launch-scan/retake state. No face or eye shape is shown anywhere. Everyone gets
`FaceShapeAssessment.standardLook` (oval assignment: natural brow, cheekbone blush) and the natural eyeliner.
Brow/blush attachments are fitted from live try-on/tutorial frames (`LaunchMakeupFit.fitLive`, one Vision
attempt at most every 0.4 s, frontal and relaxed face) and then followed by ARKit; `LaunchMakeupFit.shared` is
memory-only, cleared on each camera session start, and deletes the old `savedMakeupAttachments.v1` key.
FaceShape/EyeShape/Onboarding/ProfileView/ScanDebug code stays in the repo, unreferenced, so it can return.
Sections below that describe the launch scan, saved fit or Profile predate this. Not yet checked on a device.

## Brow stability — -Nimah (2026-10-27)

User reports eyebrow jitter after availability recovery. Native brow residuals now use metre-space 2 Hz /
80 Hz-per-metre-second One Euro filtering plus 0.12 mm output hold; gaps >150 ms reset. Rigid face/camera pose
remains unsmoothed. Brow-only UV atlas gets mipmaps and anisotropic trilinear sampling to reduce strand
minification shimmer. Blush keeps its prior filter and non-mipmapped atlas. Physical acceptance pending.

## Makeup visibility recovery — -Nimah (2026-10-27)

Device scalar metrics showed segmentation_unavailable: CancellationError() despite segmenter_available=true;
mask age 223 ms exceeded the 150 ms freshness guard. Native beauty engine now owns/cancels preparation task,
ignores expected navigation cancellation, clears recovered segmentation/fitting errors and resets status on
pause. Opt-in faceSkinOnly preprocessing uses 256 long side for the bundled 256 model; Hanum default stays512.
Do not remove stale-mask occlusion protection or claim all visibility delays are fixed without device checks.

## Personal blush v0.4.0 — -Nimah (2026-10-27)

Face shape picks artistic style; per-side cheek corridor and observed mouth/nose-to-eye spacing adapt
center and radii. Uses stored native geometry, independent sides, explicit bounded JSON controls and
conservative exclusions; no second scan/tracker or semantic cheekbone claim. Shared native mouth-boundary
helper now lives in BlushPlacementGenerator. Keep Metal and tutorial using the same fields. Preserve all
pending eyebrow edits and existing eyeliner. See Docs/Decisions/0012-personal-cheek-placement.md.

## Native UV strand eyebrow — -Nimah (2026-10-27)

Eyebrow After uses the shared BeautyBlushEngine ARKit/Metal pipeline, one selected category at a time.
A native UV atlas bakes 80 measured/JSON-shaped centerline segments (40 per side); procedural stable strands,
head fade, taper, feather and max alpha. Brow fragment uses separate hair pigment shading, not blush tint.
Preserve observed head/tail, existing face-shape assignments and saved scan flow. No extra scan or tracker.
Category mode is part of atlas cache identity; hide old layer and epoch-guard GPU completions on switching.
SceneKit pigment disabled when Metal owns that category; guides/fallback retained. Metrics beautyBrow.metrics.
Natural hair is not erased: a lighter shade cannot bleach dark brows. Face-skin segmenter is shared, not a
specialized eyebrow/hair matting model. Physical device quality and segmentation need acceptance.

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

## Pigment depth compositing — -Nimah

FaceRegionPreviewRenderer cosmetic materials composite over camera video without reading the coarse native
face depth buffer. Their placement still uses measured front-skin barycentric attachments, not screen offsets.
Guide/eyeliner depth policies remain unchanged. Render tests must include a colorless depth-writing occluder;
a blank SceneKit scene cannot detect self-occlusion. Device visual confirmation is still required.

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

# AGENTS.md — read this first

## Camera guidance — shared by every tool

`Features/CameraGuidance/` holds what Try On and the tutorial share, for brows, blush and eyeliner alike: `CameraAdvisor(context:)` publishes
the one `CameraMessage` to show (priority, delays and hysteresis live in `CameraMessageEngine`, thresholds in `CameraMessageEngine.Limits`);
`CameraGuidanceCaption` draws it (or a tutorial step) as the spec's caption pill; `ScreenLight` + `ScreenLightGlow` + `ScreenLightButton`
are the screen light. Screens start/stop the advisor and suspend/resume the light with their own lifecycle. The advisor reads
`ARSession.currentFrame` only. While `advisor.message != nil` the preview/guide dims and `advisor.pausesAnimation` holds the step
animation; `reducesLoad` and `pausesSession` follow the thermal state. Eyeliner steps: `LinerTutorialStep` and `LinerStepGuide`
(`Features/Tutorial`). Spec thresholds are untuned guesses; not yet checked on a real device.

## Saved scan flow — -Nimah (supersedes launch-only scan)

Completed face/eye analysis is reused on reopening. Root requires both saved results; Retake in Profile reruns
complete preparation. Sparse barycentric brow attachments and anatomical mapping points persist locally in
UserDefaults (versioned), with vertex/triangle counts and observed confidence. No full mesh, topology array or
camera frame is persisted by fitting. A new live mesh reattaches those sparse descriptors without Vision scanning.
Old installs with analysis but no sparse fit can enter home and explicitly use Profile Retake; unavailable tools
show a message instead of silently rendering nothing. First-launch incomplete analysis still opens onboarding.
Team sources: Khalish scan-overlay-lines b2d8ae0; Hanum Eyeliner-Hanum 071d2a0; profile-page supplies Profile.


## Soft cheek preview — -Nimah

Blush uses a common eye/nose reference for both cheek guides in face-local coordinates. Tutorial dots/V shapes
remain guidance; try-on combines each cheek into a wider elliptical pigment patch with continuous radial alpha.
Observed brow contours are retained even when optional formula annotations cannot bind. No extra try-on scan.
Device visual acceptance is required; these parameters do not establish TikTok-equivalent rendering quality.

## Detector lifecycle — -Nimah

A nil eyeliner style hides output and skips inference while retaining this screen's warmed models.
Only screen deactivation stops/releases them. A category change during startup must not leave startupTask stuck.
Home/tutorial sync is gated by active visibility so hidden routes cannot restart detection.

## Latest integration — -Nimah

Hanum profile `502e423`, eyeliner/tutorial `071d2a0`, and Khalish scan overlays/debug `99791b3` are integrated.
Home retains one selected makeup category, remembered shades/intensities, and launch-only fitting.
Profile retake uses the same complete launch preparation flow; Scan Debug is reachable from the profile toolbar.
Scan landmarks keep the `EyeScanLandmarks` name to avoid colliding with Hanum live `EyeLandmarks`.
Upper-inner blush try-on fills a wider soft cheek area; the tutorial V remains a placement guide.
These notes supersede older all-layers-on descriptions. Device visual/performance acceptance remains pending.


## Tutorial — scan-assigned

`AppRoute.recommendedTutorial(TutorialHandoff)` opens `Features/Tutorial/GuidedTutorialView` (tabs Brows / Eyeliner / Blush, no settings;
shade and strength are carried over from Try On). Eyeliner has three steps (`LinerTutorialStep`) for every look; the look only moves the dots. Not yet checked on a real device.

## Photo — after the tutorial

The tutorial's last-step button enters `GuidedTutorialModel.photoMode` (same screen and camera): full look, coloured frame
(`PhotoTheme`: palette button cycles pink/blue/white), shutter, then `PolaroidResultView`. Views in `Features/Tutorial/PhotoCaptureViews.swift`.
In-memory only; sharing is the only way it leaves the app. Not yet checked on a real device.

## Profile — scan stills

`AppRoute.profile` opens `ProfileView` (face + eye analysis, signature look). Its retake button opens `AppRoute.fullScan`
(`FullScanFlow`: face scan then eye scan in one flow). Portraits are the stills saved by `ScanSnapshots` at scan completion
(face: ARKit frame, oriented via the Vision orientation; eyes: MediaPipe frame cropped around the eyes). Not yet checked on a real device.

## Current merged scope — -Nimah

Smooth try-on — -Nimah: replayed identical scan outputs are ignored before any published state changes.
Brow/blush shade changes update material tint only: keep surface attachments, feather sources and topology.
`FaceRegionPreviewRenderer` uses a 6 mm XY triangle index for exact barycentric binding; live vertex updates
avoid intermediate arrays. Hidden guide renderers return before node construction/animation. Shared-camera
`LinerFrameRelay` budgets overlay delivery to 30 Hz without changing ARKit camera tracking or Hanum formulas.
Non-eyeliner tool/shade/intensity changes do not resynchronize eyeliner. For device performance acceptance,
use a Release build without Xcode's debugger; no measured physical-device FPS is claimed by simulator tests.


Startup recovery — -Nimah: initial face scanning offers tracked frames every 400 ms to a bounded background
`LaunchFitPreparation`; retain the first valid fit, rather than relying on one final frame. Launch fitting can
use observed brow contours without optional pupil/nose formula points; no missing landmarks are invented.
Legacy formula-dependent fitting remains strict. Neutral eyeliner does not block startup. If contour fitting
still fails, retain scan results and offer continuing with available makeup; home explicitly disables and labels
unfitted brow/blush layers instead of claiming they are rendered. Try-on still never runs another Vision scan.


Launch-only scan — -Nimah: `AppNavigator.launchScanComplete` is memory-only and starts false on every cold launch.
Welcome is remembered, analysis is not skipped. Launch runs face scan, eye scan, and transient makeup fitting before
try-on. `FaceAnalysis.scanScreen(onScanFrame:)` exposes the completed AR frame to the launch integrator without
changing classification formulas. `LaunchMakeupFit` keeps only in-memory fitting geometry for the current run;
no image/mesh is written to disk. Try-on/tutorial use `usesLaunchFit` and `followLaunchFit`, which reattach the
initial fit on matching ARKit topology without Vision scanning, sample accumulation or hold-still gates. No scan
prompts or rescan controls appear in try-on. All supported assigned layers start on. Liner live tracking remains
automatic; it skips the legacy Vision fitting phase. Initial preparation failures stay in the launch flow.


Visible pigment fix — -Nimah: layered render snapshots must request `includeBrow: configuration.needsBrow`,
otherwise turning on blush strips the brow input from the renderer. Brow/blush pigment cores use stronger alpha,
14% feather width, 1 mm surface lift, and default intensity 0.85. Before/After and intensity still control visibility.
These are preview rendering parameters, not measured real-world colour accuracy.


Palette try-on — -Nimah: `Features/TryOnHome/PaletteColorPicker.swift` provides a native ColorPicker,
PhotosPicker import and rear-camera capture, followed by tap-to-sample from bounded upright sRGB pixels.
Photos are memory-only and never uploaded/saved. Home dismantles the face camera while picking a palette,
then resumes it; custom RGB only changes shade, not the scan assignment. Presets follow the supplied blush/brow
references approximately (not colour-calibrated product swatches). `AppRoute.recommendedTutorial` carries the
chosen shade/intensity into the assigned Nimah tutorial after the live try-on. Existing camera permission text
includes palette capture; PhotosPicker needs no broad photo-library read permission.


Scan-assigned results — -Nimah: user-facing eyebrow/blush use exactly one stable assigned catalog ID for the saved
face shape (`MakeupPreferenceCatalog.assignedBrow/assignedBlush`); no source/style picker or manual face override.
Uncovered shapes and absent scans leave those layers off. Eyeliner exposes only Hanum's personal eye-scan result,
not the catalog. TryOnHome refreshes saved output changes without rebuilding the camera, and its profile route
opens scan results/rescan actions; the tutorial arrow opens the active assigned category. Data is an on-device
catalog, not a server database. See Docs/BrowBlushPreferences.md for assignments and uncovered shapes.


This section supersedes older status descriptions below. Khalish owns face/eye scanning and saved outputs;
Nimah owns eyebrow/blush placement and tutorials; Hanum owns the eyeliner planner/live overlay. The duplicate
Khalish eyebrow/blush catalog, personalizer and renderer were removed. Shared measurement/data helpers remain.
MediaPipe is used by both eye scanning and eyeliner (including hand occlusion); it is linked only to the app.
The package is pinned to revision `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`.
Khalish's scan-specific landmark model/file is named `EyeScanLandmarks` to avoid Hanum's `EyeLandmarks` collision;
measurement mathematics is unchanged. Both sets of eye tests are retained.
Catalog/import/save and Nimah studio are implemented MVP features, not placeholder-only services.
See `Docs/CodeOwnership.md`, `Docs/Performance.md`, and `Docs/Validation.md`; historical notes below may predate integration.

Home screen: after onboarding the app opens on `Features/TryOnHome/TryOnHomeView` (no tab bar). `TryOnHomeModel` swaps the camera
card between Nimah's blush/eyebrow engine and Hanum's eyeliner engine; profile and tutorial are blank placeholder routes for now.

Saved-analysis flow: onboarding runs Khalish face scan then eye scan. `FaceShapeStore.latest` supplies Nimah
eyebrow/blush presets; `FaceShapeStore.eyes` supplies Hanum eyeliner via the `MakeupPlan` adapter. Saved analysis
opens eyebrow/blush preview directly, with tutorial immediately available. Live geometric alignment is automatic,
not another classification step. Eye-scan measurements are converted using matching units; the lid is never
guessed from `mayBeHooded`. Missing/unclear measurements use the neutral liner. Older scans can still use the
eye measurements embedded in the face result when no separate eye result exists. Eyeshadow is outside this scope.

Eyeliner look (Hanum's overlay): `LinerOverlayRenderer` yields a halo fill plus a body fill per eye; the live canvas and photo
`compose` multiply them into the camera picture, erase a skin-texture grain (`LinerInk`, anchored to the eye) and hand
regions, and tint the pigment with skin sampled from the ARKit frame. Shared tuning constants live in `LinerInk` and `LinerOverlayRenderer`.

Shared brief for anyone working on this repo with an AI coding assistant (Claude Code, Codex, Cursor, Copilot, …).
It covers the project structure, what each feature does and how to use it, and the rules to follow.
`CHANGELOG.md` records what changed. Team docs in `Docs/` are written in Indonesian and give more detail.

**Keep it current:** a change that adds or moves a feature, a public entry point, a route, or a rule updates this
file and adds a `CHANGELOG.md` entry in the same PR.

## Project at a glance

- **SunriseApp** (working name): an iOS app that recommends eyebrow, blush and eyeliner styles for your face shape
  and lets you try them on live with AR.
- SwiftUI, iOS 17+, iPhone portrait. Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY = complete`.
- One third-party dependency: **MediaPipe Tasks Vision** (Swift Package from `google-ai-edge/mediapipe`, pinned to the `v1.1.1` commit `50505c8`; it must be pinned by revision, see ADR 0002), used only by the
  eye scan in `Features/EyeShape`. One app target (`SunriseApp`), one unit test target (`SunriseAppTests`) and one app extension (`SunriseLiveActivity`, the scan's Dynamic Island).
  Why and how: `Docs/Decisions/0002-mediapipe-eye-scan.md`.
- Light MVVM: ViewModels are `@MainActor final class … : ObservableObject` with `@Published`. Stateless views have no ViewModel.
- Apple frameworks, plus MediaPipe for the eye scan: ARKit + SceneKit (face tracking and makeup rendering), Vision (landmarks and face outline), AVFoundation (camera permission and the eye-scan camera), MediaPipe (eye and iris landmarks).

## Build and test

The first build downloads the MediaPipe package (needs internet; Xcode resolves it, no extra tool). Commit `Package.resolved`.

```sh
xcrun simctl list devices available | grep iPhone
xcodebuild test -project SunriseApp.xcodeproj -scheme SunriseApp \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath /tmp/SunriseDerived CODE_SIGNING_ALLOWED=NO
```

- The Simulator has no TrueDepth camera, so the live scan and try-on show their "unavailable" state there. Real AR
  behaviour must be checked on a Face ID iPhone. Say which one you used when you report results.
- `FaceShapeDatasetEvalTests` is skipped unless you pass a labelled dataset:
  `TEST_RUNNER_FACE_SHAPE_DATASET=/path/to/dataset xcodebuild test …` (folders named after shapes, e.g. `Heart/`, `Long/`).
- CI: `.github/workflows/ios-build.yml` builds and runs the unit tests on a macOS 15 runner; Xcode resolves the package.
- MediaPipe gotcha: link the package to the `SunriseApp` target only, never to `SunriseAppTests`. The tests run inside the app, and a second copy of
  MediaPipe crashes at launch ("Function with name ... already registered"). Do not also add it through CocoaPods.

## Project structure

```text
AGENTS.md / CLAUDE.md     AI brief (this file); CLAUDE.md just imports it
CHANGELOG.md              what changed, newest first
Docs/                     team docs in Indonesian: architecture, contracts, scope, testing, ADRs
.github/                  CI workflow, PR and issue templates
SunriseApp.xcodeproj/     explicit PBXGroups: every new file must be added to the project (see Rules)
SunriseApp/
  App/                    SunriseApp entry, AppContainer (composition root), AppRootView (tabs + route destinations)
    Navigation/           AppRoute (all destinations), AppNavigator (tabs, per-tab paths, onboarding flag)
  Core/
    Models/               cross-feature models: MakeupReference, Tutorial, SavedLookMetadata, FaceTrackingAvailability, ScanOverlay (+ ScanSnapshot)
    Services/Contracts/   Sendable async service protocols (catalog, saved looks, tracking availability)
  DesignSystem/
    Theme/                AppColors, AppSpacing, AppTypography (use these, never hard-coded values)
    Components/           PrimaryButton, EmptyStateView, FeaturePlaceholderView, ScanOverlayView, ScanProgressRing, ScanDoneBadge, DynamicIslandConfirmation
  Features/
    FaceShape/            face shape scan (ARKit mesh + Vision) and photo classification. Entry: FaceAnalysis.swift
    MakeupTryOn/          makeup recommendations and live AR try-on
    Onboarding/           welcome screen, then the face scan
    EyeShape/             eye shape (openness, tilt, spacing) from MediaPipe landmarks. In progress: measuring and classifying are done and tested,
                          the scan screen, onboarding step, home card and Try On route exist; not yet checked on a real face
    ScanDebug/            debug tab: correct the face and eye outline points from a live scan by hand and save raw + corrected as JSON (see below)
    ReferenceCatalog/ ReferenceDetail/ ReferenceImport/ FaceCalibration/ Tutorial/ LiveGuide/ Comparison/ SavedLooks/
                          scaffold features: mostly placeholder UI on mock data
  PreviewSupport/         SampleData + Mock services (used by previews and the scaffold container)
  Resources/              Assets.xcassets (named colours), Localizable.xcstrings
  Configuration/          Info.plist (camera + photo-library-add usage strings)
SunriseLiveActivity/      app extension: the scan's Live Activity (Dynamic Island). `ScanActivityAttributes` (Core/Models) is shared with the app; keep it free of app-only imports
SunriseDebugMac/          separate Mac-only Xcode project: edits scans exported from the Scan Debug tab (see below and its README)
SunriseAppTests/
  Features/               face shape, head pose, photo measurer, makeup recommender/personalization/texture tests
  Navigation/             AppNavigatorTests
  TestSupport/            ServiceStubs
```

## Navigation

- Tabs (`AppTab`): **Try On** (home), **Discover**, **My Looks**. Each tab has its own `NavigationStack` path in `AppNavigator`.
- `AppRoute` lists every destination, and `AppRootView.destination(for:)` builds them. To add a screen: add a case,
  add its destination, and push it with `navigator.open(route, in: tab)`. `returnToRoot(of:)` clears one tab's path only.
- Onboarding is persisted: `AppNavigator` stores `onboardingComplete` in `UserDefaults` and shows it once.
  To see onboarding again in the Simulator, delete the app.

## Features: status and how to use them

| Feature | Folder | Status | Use it through |
| --- | --- | --- | --- |
| Face shape | `Features/FaceShape` | Real: live ARKit scan + photo path, unit tested | `FaceAnalysis` |
| Makeup try-on | `Features/MakeupTryOn` | Real: recommendations + live AR try-on | `MakeupPlan`, `MakeupRecommendationsView`, `AppRoute.makeupTryOn` |
| Onboarding | `Features/Onboarding` | Real: welcome, then scan; Skip allowed | `OnboardingView(store:onFinish:)` |
| Catalog / detail / import / calibration / tutorial / live guide / comparison / saved looks | `Features/…` | Scaffold: placeholders on mock data | mocks in `PreviewSupport`, contracts in `Core/Services/Contracts` |

### Face shape — `Features/FaceShape/FaceAnalysis.swift`

The only entry point for other features. Use `FaceAnalysis` and the result types `FaceShape` / `FaceShapeResult`.
Don't call the measurers or the classifier directly, and don't change FaceShape internals from another feature.

```swift
FaceAnalysis.isLiveScanSupported                    // TrueDepth check; the photo path works on any device
FaceAnalysis.scanScreen(store: store) { … }         // ready-made scan screen; writes the result to the store
FaceAnalysis.makeLiveScanner()                      // FaceShapeViewModel for a custom UI: session, start(), stop(), phase
await FaceAnalysis.faceShape(in: cgImage)           // Result<FaceShapeResult, FaceAnalysis.PhotoFailure>
FaceAnalysis.savedResults()                         // FaceShapeStore restored from UserDefaults (latest result only)
FaceShapeStore(latest: result)                      // in-memory store for previews and tests
```

- `FaceShape`: oval, round, square, oblong, heart, diamond, triangle. Each has `title`, `symbol`, `summary`, `blushTip`.
- `FaceShapeResult`: `shape`, `runnerUp`, `confidence`, `scores`, `rankedShapes`, `deviation` (proportions vs. the reference face).
- How it works, for anyone tuning it: the ARKit mesh gives proportions (length, forehead, jaw, chin relative to
  cheekbones), and Vision's face outline corrects the jaw and chin. Only frames looking straight ahead at arm's length
  count (`HeadPose`: ±10° yaw/pitch, 25–65 cm). The median of about 180 frames is scored against shape prototypes.
  Tuning lives in `FaceShapeClassifier` (prototypes, `unit`) and `PhotoFaceMeasurer` (photo reference). Check
  accuracy changes with the dataset eval.
- Privacy: only the classified result is stored. No photos or meshes are saved or uploaded.
- Result picture: `FaceShapeViewModel.snapshot` is the camera picture (from the `ARSCNView`, wireframe hidden) with the face outline and the
  forehead, cheekbone and jaw widths and the length drawn on it (`FaceMeshMeasurer.guide` → `FaceGuide.overlay` → `FaceSnapshotter`), shown
  by `FaceShapeResultView`. The widths are scaled by the Vision correction, so the lines are the widths the classifier used. In memory only.
  It needs a device to check: the Simulator has no TrueDepth camera, so `FaceSnapshotter.capture` has only been compiled.

### Makeup try-on — `Features/MakeupTryOn`

- `MakeupPlan(scan: result)` builds the "Made for you" style per category (blended from nearby shapes and nudged by
  measured proportions), followed by that shape's catalog styles. `MakeupPlan(shape:)` is for a chosen shape without a scan.
- `MakeupRecommendationsView(store:onScanFace:)` is the Try On home tab. Open the live try-on with
  `navigator.open(.makeupTryOn(plan: plan, applied: [...]), in: .tryOn)`.
- Categories: eyebrow, blush, eyeliner (`MakeupCategory`). Shades come from `MakeupPalette`. Style rules live in
  `MakeupRecommender`, and per-face fitting in `MakeupFitter` (`FaceFit.swift`).
- Rendering: Vision locates the brows and eyes, and they're mapped onto the ARKit face mesh's UV texture. Each
  category is drawn into its own texture (`MakeupTextureRenderer`) on its own copy of the mesh (`MakeupARView`), so
  makeup follows the face.
- Try-on photos are only saved when the user shares or saves them (`NSPhotoLibraryAddUsageDescription`).

### Eye shape — `Features/EyeShape` (in progress)

Everything is built; nothing has been run on a real face yet (the Simulator has no camera, so the scan screen shows "unavailable" there).
Plan and decisions: `Docs/Decisions/0002-mediapipe-eye-scan.md`.

- Entry point: `EyeAnalysis.scanScreen(store:continueTitle:onFinish:)` returns `EyeScanView`. It writes `FaceShapeStore.eyes`
  (kept in `UserDefaults` under its own key, separate from the face shape) and leaves the ARKit session alone; `FaceShapeView` stops it
  before its `onShowMakeup` runs.
- Flow: onboarding is welcome, face scan (its result button reads "Next: scan your eyes"), eye scan, then home. Skip leaves only the
  current step. The Try On home shows an eye card ("Scan your eye shape" or the result, with "Scan eyes again") through `AppRoute.eyeScan`.
- `EyeScanViewModel`: phases idle / unavailable / cameraDenied / failed / scanning / finished. It takes 30 good frames (`EyeScanGuide`
  rejects too far or close, turned head, closed eyes), classifies their median and stops the camera. The result sheet asks which eyelid
  the person has (`EyeLid`, optional).
- The eye shape is shown on the home screen but does **not** change the makeup recommendations yet.
- On devices without TrueDepth the face scan is unavailable, and the home screen still needs a face shape before it shows anything, so
  those users only reach the eye scan from onboarding.

- `EyeLandmarks`: plain 2D eye points. `EyeLandmarks(normalizedMesh:imageSize:)` maps MediaPipe's 478-point mesh (`MeshIndex`). The eye
  outlines are checked against MediaPipe's own tables in `MediaPipeEyeDetectorTests`; the brow rows and the iris-to-eye assignment (done
  by distance, because MediaPipe's iOS right-iris table returns the left ring) are not, so **check them on a real scan on a device**.
  `headTurn` (0 facing the camera, 1 nose over a face edge) is for gating frames; its limit is still to be chosen on a device.
- `MediaPipeEyeDetector`: the only file that imports MediaPipe. Wraps Face Landmarker in video mode; `detect(pixelBuffer:timestampMs:)`
  wants upright BGRA frames in increasing time order from one serial queue. The model is `Resources/face_landmarker.task`, bundled, never downloaded.
- `EyeCameraSession`: front `AVCaptureSession` delivering upright BGRA frames off the main thread. Stop the ARKit face session
  (`FaceShapeViewModel.stop()`) before `start()`; the two must not run together. It only checks camera permission, the mesh scan asks for it.
- The Simulator build is arm64 only (`EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`): MediaPipe has no Intel-Simulator slice.
- Result picture: `EyeScanViewModel.snapshot` is the last good frame, mirrored like the preview and cropped around the eyes, with the lines
  from `EyeOverlay` (outlines, corner lines, opening, iris, brow, spacing), made by `EyeFrameSnapshot` on the camera queue and shown by
  `EyeShapeResultView`. In memory only. The eyelid split in `EyeOverlay` assumes `lid` lists the upper lid, then the lower, both from
  the outer corner (true for `MeshIndex`); check the drawn outline on a real scan.
- `EyeMeasurer.measure(_:)` gives `EyeMeasurements` (openness, tilt, spacing, lidSpace in iris diameters). It derives the face's own axes
  from the points, so roll, scale, mirroring and y-down images do not matter. `EyeMeasurementsSampler` takes the per-field median and skips blinks.
- `EyeShapeClassifier` turns measurements into `EyeShapeResult` (`EyeOpenness`, `EyeTilt`, `EyeSpacing`, `mayBeHooded`, `confidence`). The eyelid
  (`EyeLid`) cannot be seen in landmarks, so the person chooses it later; it stays `nil` until then.
- The thresholds in `EyeShapeClassifier.Thresholds` and `EyeMeasurer.minimumOpenness` are starting guesses, not tuned on real faces.

### Scan Debug — `Features/ScanDebug`

A fourth tab (`AppTab.scanDebug`, "Scan Debug") for correcting outlines by hand. It runs the same `FaceShapeView` / `EyeScanView` as onboarding
(into a throwaway `FaceShapeStore`, so real results are not changed) and takes their scan picture through the new optional `onResult` callback.
`ScanDebugSnapshotReader` turns that picture's overlay strokes into raw points (10 face, 14 eye). Corrected stage: points drag. Final: corrected vs
raw numbers, and Confirm writes `<face|eyes>-<name>.raw.json` and `.corrected.json` via `ScanDebugStore` (Application Support/ScanDebug; a name already
used gets `-2`). Only coordinates are stored. Measuring uses `FaceShapeClassifier.photo` and `EyeMeasurer` / `EyeShapeClassifier`. If `FaceGuide.overlay`
or `EyeOverlay.overlay` change their stroke order, update the reader (tests cover it). Its UI strings are English-only, not in `Localizable.xcstrings`.

#### Export for Mac and the Mac editor — `SunriseDebugMac/`

Scan Debug has an **Export for Mac** share button (`ScanDebugExportItem`, file format `ScanDebugExportFile`, extension `.sunrisescan`, type
`com.sunrise.scan-debug` declared in `Info.plist`). `SunriseDebugMac/SunriseDebugMac.xcodeproj` is a separate macOS app with no scanning that opens those
files (AirDrop), corrects the points with the mouse and writes the same raw and corrected JSON files. It compiles files from `SunriseApp/` directly, so a
shared file (listed in its project) must not import ARKit, UIKit or MediaPipe. See `SunriseDebugMac/README.md`.

### Scaffold features

Catalog, detail, import, calibration, tutorial, live guide, comparison and saved looks are still the original
scaffold. Their services are mocks composed in `AppContainer.scaffold()`, and Save throws `notImplemented` on purpose.
Keep their placeholder labels until a real implementation is tested (see `Docs/ProductScope.md`).

## Rules

- **Adding files:** create them in `Features/<Feature>/` and add them to the matching group **and** target in
  `project.pbxproj` (PBXFileReference, PBXGroup child, PBXBuildFile, Sources phase). Then build to confirm.
- **Third-party code:** MediaPipe is the only package dependency; the MI-GAN Core ML model (ADR 0014) is the only bundled
  third-party model besides MediaPipe's own, and its MIT notice must stay in `Resources/MI-GAN-LICENSE.txt`. `import MediaPipeTasksVision` is limited to the detector wrappers
  (`MediaPipeEyeDetector`, `MediaPipeEyeLandmarkProvider`, `HandOcclusionSegmenter`, `MediaPipeBrowTracker`); everything else
  works on plain landmark arrays. A new dependency needs an ADR in `Docs/Decisions/`.
- **Dependencies:** inject them through initializers. `AppContainer` is used only in `AppRootView`; features never reach into it.
- **Shared files** (`AppRootView`, `AppRoute`, `AppNavigator`, `AppContainer`, `project.pbxproj`, Core contracts,
  design tokens, strings): keep edits small and mention them in the PR. Change contracts in their own PR (see `Docs/IntegrationContracts.md`).
- **Concurrency:** strict mode is on. Keep Vision and image work off the main actor (`Task.detached`). Use `Sendable`
  snapshots across actors, and `nonisolated` ARSession delegate methods with `MainActor.assumeIsolated`.
- **UI:** use `AppColors` / `AppSpacing` / `AppTypography` and Dynamic Type text styles. User-facing strings go in
  `Localizable.xcstrings`, with English as the source language.
- **Privacy:** no networking, analytics or uploads. Never persist camera frames or face meshes. The one exception is `Features/FaceShape/ScanSnapshots.swift`: one small JPEG per scan (face, eyes) in Application Support, excluded from backup, shown on the profile (`TryOnHome/ProfileView`); a new scan replaces it. A new permission needs an Info.plist usage string.
- **Privacy:** no networking, analytics or uploads. The one exception to "never write pictures" is Scan Debug's **Export for Mac**: only when tapped, it hands the scan picture and points to the system share sheet as a `.sunrisescan` file (`ScanDebugExportItem`); the app writes nothing itself. Never persist photos, camera frames or face meshes. The scan result pictures
  (`ScanSnapshot`) are held in a view model for the result screen only; never write them to disk, `FaceShapeStore` or the photo library. A new permission needs an Info.plist usage string.
- **Honesty:** don't describe mock or sample data as real user results, and don't claim AR works on the strength of a Simulator run.
- **Git:** branch from `main` as `feature/…`, `fix/…` or `chore/…`. Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
  Keep refactors separate from features.

## Out-of-date team docs

These still describe the scaffold from before FaceShape and MakeupTryOn. Trust this file and the code where they disagree.

- `README.md`, `Docs/ProductScope.md`, `Docs/Architecture.md`: say there's no camera or ARKit, two tabs, and onboarding that resets every launch.
- `Docs/NavigationFlow.md`: no Try On tab, `faceScan` or `makeupTryOn` routes.
- `Docs/Testing.md`, `Docs/Validation.md`: the test counts and the "no camera permission" checks are from the scaffold.
- `Docs/IntegrationContracts.md` is current for face shape (section "Analisis bentuk wajah").
