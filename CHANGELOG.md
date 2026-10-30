## Try On starts bare, keeps each tool's choice, shows all together — -Nimah (2026-10-30)

`TryOnHomeModel.enabled` starts empty on every launch (no makeup on any tool). Picking a tool only shows its controls; a
tool goes on when a shade, blush look, brow picture or strength is chosen for it, off with the no-makeup button, and keeps
that state and its last choice across tool switches. All tools that are on show together. `BeautyBlushEngine` can now draw
blush and brow in one frame: `prepareBlush` (fit, atlas, mask, visibility, smoothed mesh, tutorial outlines; before the
encoder) and `encodeBlush` (depth prepass, pigment) are used by the blush-only `render` and by `drawBrow` when
`Settings.withBlush` (between the camera and the brow strip). The brow path runs whenever the brow is on
(`isBrow = needsBrow`, was `needsBrow && !needsBlush`, which dropped the brow whenever blush was on, also in the tutorial
photo). Brow and blush keep separate tint/strength (`blushTint`, `blushIntensity`) and visibility (`blushVisibility`); with
both on, the brow tracker's answers also feed the blush cheek fit (`addBlushSample`). `TryOnHomeModel.tutorialHandoff`
carries `enabled`: each tutorial tab previews its tool as last chosen, and a tab for a tool that was off guides without
a makeup preview (the eyeliner tab still shows its liner). The photo step stays Hanum's plain camera (merged 2026-10-30).
Device check pending.

## Blush skin tone fix, iOS 26.5 target — -Nimah (2026-10-30)

Device feedback over three rounds (darker cheeks, then a hazy camera, then "brighter when Try On is off"). Final state:
the Metal camera (blush and brow) now shows the tone ARSCNView shows. Measured on iPhone 17 from paired screenshots
(Try On on with no pigment / off, same scene): neither the sRGB decode (up to 13/255 too dark in the mid-tones) nor the
BT.709 decode (11/255 too light in the shadows, the haze) matched. A fitted 11-knot curve, `cameraTone` in
BeautyBlush.metal and `BeautyBlushConfiguration.cameraTone` (a test keeps them equal), left under 1.5/255 of systematic
error per brightness band on blocks not used to fit it; `decodeCamera` applies it, then the inverse of the drawable's sRGB
encoding, whatever the transfer tag. One device, one scene, lossy screenshots: re-measure if another iPhone differs. The
blush layer is colour-managed as sRGB. The darker cheeks came from the absorbing layer in `pigmentTarget`; the target is
rescaled to 95% of the skin's own luminance (test: at least 92% of bare luminance). Fixtures that hand-write camera
colours use `BeautyBlushConfiguration.cameraLinear`. `IPHONEOS_DEPLOYMENT_TARGET` 26.6 -> 26.5 so the app installs on
iOS 26.5 phones and runs on this Mac's 26.5 Simulators (Xcode 26.6 here ships the 26.5 SDK); no 26.6 API is used.
## Liner hides when the head turns, zoom hint (2026-10-30)

- `LinerOverlayModel.submit`: past 32 degrees of head turn (back under 25) the liner is removed at once and in-flight
  detections are ignored, so it no longer jumps to the other eye late. Limits are guesses, not tuned on a device.
- "Too far" caption now says "Pinch the screen to zoom in." instead of asking to bring the phone closer.

## Photo, polaroid save, liner lower dot, labelled pickers (2026-10-30)

- Photo step is a plain camera: no brow, blush or eyeliner (`photoConfiguration` has every layer off, natural brow kept,
  `syncLiner` skips photo mode, `takePhoto` no longer composes the liner).
- The polaroid's check button saves the polaroid to Photos (`UIImageWriteToSavedPhotosAlbum`, add-only permission) and closes.
- Eyeliner tutorial: the lower-line dot, dashes and fill (step 3 now fills it) only exist for Arabian
  (`GuidedTutorialModel.linerShowsLower`, `LinerStepGeometry(showsLower:)`); puppy and foxy no longer show it.
- Brow and liner pickers show the picture with its name under it; the first tile reads "None".
Not checked on a real device.

## Try On: zoom, faster liner, picture picker, tutorial look (2026-10-30)

- Try On camera card has the same zoom as the tutorial: pinch or tap the chip (1x / 1.5x / 2x / 3x). Picture and overlays
  scale together; the light, captions and status stay put. Tracking is unchanged.
- `LinerFrameRelay` no longer caps eyeliner frames at 30 Hz (that budget is for brow/blush); every ARKit frame is offered,
  so fast blinks follow like the Eyeliner-Hanum build.
- "Keep it to just you" no longer shows for one person: `CameraSignalSampler.otherFaceCount` ignores faces under 40% of
  the main face's area and overlapping duplicate boxes, and three readings in a row (~1.5 s) are needed.
- Eyeliner looks are pictures (`LinerLookPicker`, drawn eyes with each wing/lower line) with a no-sign tile first,
  like the brow pictures.
- Tutorial screen: wine background (not black), round frosted back button and one Next/Done capsule (a duplicate Next
  button left over from the merge is removed).
Not checked on a real device.

## Blush tutorial per UX spec 3.5 — -Nimah (2026-10-29)

`GuidedTutorialModel.blushLessons`: two steps, "Dab a little blush inside the small circle." / "Dab outward to blend it
into your skin.", with their own `blushStep` (the brow model's three blush lessons are no longer used here). Caption is
`stepCaption` (spec 1.1: STEP n OF 2 at 70%, 4 pt gap, `AppColors.captionFill` #370B21, radius 18, 22 x 4 padding, max
300 pt). `BlushTutorialOverlay` draws, anchored to each cheek: step 1 the inner dotted circle (0.38 of the pigment field)
with a fingertip dabbing three times and a pink tap ring; step 2 also the outer dotted line (0.82), the ring between them
pulsing 20%-50% every 2 s, the fingertip dabbing outward along the look's direction. 3 s animation, 2 s rest, repeat;
Reduce Motion shows the last frame and a still 40% ring; thermal `.serious` pauses the loop. Outlines are bound to the
mesh at bake (`BeautyBlushEngine.guideOutline`), projected with the pigment's own filtered vertices and `mvp`
(`projectGuide`) at 30 Hz, and published through `FaceCameraState.blushGuide` (`BlushGuideFeed`). The blush shader
contour is off (`tracking.y = 0`); Try On never used it. Camera messages (spec 1-2) are not implemented. Device check pending.

## Blush cheek fit from MediaPipe landmarks, wide natural wash — -Nimah (2026-10-29)

Device feedback: blush too small and not shaped to the face. For Youthful/Sunkissed/Lifted, `BeautyBlushEngine` now runs
the shared MediaPipe tracker while blush is selected, only until the cheek fit is measured: 17 landmarks per frame
(`BlushCheekLandmarks.pairs`: eye corners, lower lid, nostril wing, mouth corner, cheekbone, apple, face edge) are lifted
onto the same frame's ARKit mesh (`BrowFaceFrame.faceLocal`), frontal frames only (|yaw|,|pitch| < 15), median of 10,
once per face anchor. `BlushPlacementGenerator.landmarkField` places each cheek in that person's corridor (nostril wing
to face edge, mouth corner to lower lid) with new preset fields `landmark_*` (fractions of the corridor) and a
flat-topped `wash` profile (1 - smoothstep(r), atlas `paint.z`), cut softly by nose/lid/face-edge feathers. Pigment is
still drawn on the ARKit mesh with ARKit UVs. Until the fit arrives, or when it is implausible, the ARKit-only fit is
drawn (one re-bake when it arrives, no crossfade). Look `max_alpha` 0.48 -> 0.34. Other blush styles are unchanged.
Synthetic tests only; device look pending.

## Skin-preserving blush compositing and blush lab — -Nimah (2026-10-29)

Blush stays a UV atlas on the native ARKit mesh; placement/silhouettes are unchanged. Fixed in
`BeautyBlush.metal.txt` (its camera decode stands; see the 2026-10-30 entry above); default blend colours low-frequency skin
(`detail_radius_px`, new required JSON field, 2...16 camera px) and puts back each pixel's luminance ratio and chroma
residual, keeping pores, highlights and freckles; out-of-gamut colours move towards their own luminance instead of
per-channel clamping; tutorial contour is an antialiased isoline. Alpha 0 is exactly the camera pixel.
Developer tools + Blush: `BlushDebugMenu` picks blend (pigment, previous, linear alpha, multiply, soft light) and
diagnostics (neutral, UV checker, mask, boundaries, visibility, wireframe). No MediaPipe blush renderer, Banuba or
BytePlus exists; the orphan `Features/BeautyBlush/Comparison/` files are not in the project. See ADR 0017 and
`Docs/blush-rendering.schema.json`. Synthetic Simulator tests only; device look pending.

## Tutorial camera handoff and welcome revision — 2026-10-29

Try On deactivates before pushing tutorial. Paused/revoked/dismantled ARSCNViews detach
from the shared ARSession; resume reattaches before acquiring the delegate. This avoids
retained navigation views remaining attached while the new screen owns the camera.
Tutorial split comparison uses the same Metal camera pass, with pigment scissored to
the left half, instead of attaching a second ARSCNView to the shared session. Tutorial
handoff carries brow overlay/hiding settings; Filter Off also disables natural-brow hiding.
Welcome version 2 migrates devices that already dismissed revision 1, without resetting
saved data. Verified device preference was revision 1 before install.

381 Simulator tests executed, 4 skipped, 0 failures, including lease/detachment,
tutorial configuration and welcome migration regressions. Signed Release build and
installation on Nimah New succeeded. Physical tutorial camera/compare acceptance pending.
Logs: /tmp/sunrise-tutorial-camera-tests.log and /tmp/sunrise-tutorial-camera-release.log.
Existing local Xcode project/signing and strings edits preserved. No push or main change.

## Staging integration merge — 2026-10-28

Merged integration blush v0.5, mask continuity and hi-fi welcome with staging's latest
MediaPipe/ARKit-pose brow, overlays and MI-GAN work. Staging's scan-free home remains:
the versioned welcome dismisses directly to Try On; historical scan/Profile migration
notes below describe the integration parent, not this merged flow. Brow tracking,
overlay selection, erasing and 3D rendering remain from staging. Blush retains its
native UV pipeline, three looks, palette and tutorial handoff. Device QA is pending.
## Archive app icon configuration — 2026-10-29

- Wired the `AppIcon` asset catalog into the app target for Debug and Release archives and removed the obsolete Live Activities plist flag.

## Tutorial bar, screen light and uncapped brow — Khalish (2026-10-29)

- Tutorial: wine background like Try On; bottom bar with compare on the left, Blush / Brows / Eyeliner, and a screen light
  on the right (`ScreenLight`, `ScreenLightGlow`, `CameraBarButton`, `AppColors.ringLight`).
- Brow frame caps removed at nominal and fair thermal state (drawing and MediaPipe run as fast as frames are free); hot
  phones keep 15 / 30 fps. Split view's real half at 60 fps.
- Simulator tests only; device check pending.

## Brow frame rate — Khalish (2026-10-29)

- MediaPipe gets at most 30 camera frames a second again (`browMaxFramesPerSecond`; fair 24, hot 15); the brow is still drawn
  on every 60 Hz frame (`BrowLoad.drawFPS`, 30 when hot), moved by ARKit's pose between answers. Running the landmarker at 60
  fps took GPU and Neural Engine time from drawing.
- `BrowFaceFrame.faceLocal(at:projected:)` skips mesh triangles whose image cannot contain the landmark (same result, far
  fewer ray tests per MediaPipe answer on the render queue). `browStrip` evaluates the centerline once per column
  (`BrowGeometry.section`) instead of three times per vertex.
- Simulator tests only; frame rate not measured on a device.

## Remove scan Live Activity — 2026-10-29

- Removed the unused `SunriseLiveActivity` extension and ActivityKit scan feedback. Face and eye scans keep their in-app progress and completion badge.

## ARKit-pose brow stabilizer and 3D hair brow — Khalish (2026-10-28)

- `BrowFaceStabilizer`: brow landmarks lifted onto ARKit's face mesh, smoothed in face-local metres, projected back; falls
  back to the image smoother without a tracked face or when ARKit and MediaPipe disagree. Metric `brow_stabilized`.
- New "Brow 3D" tile (`BrowOverlay.is3D`): the OBJ's hair ribbons on ARKit's face pose, depth-tested against the face mesh,
  hand-masked, widened to 1.5 px so thin hairs do not flicker; shows its picture when ARKit has no face. ADR 0015.
- Tests: stabilizer on a synthetic moving head with noise; placement; GPU fixtures for depth hiding, hand mask and intensity.
  Device check pending.

## Brow overlay pictures — Khalish (2026-10-28)

- The eyebrow tool now offers two PNG brows in a horizontal picker; the chosen one is drawn over the hidden natural brow,
  keeps its own arch and strands, and follows the tracked brow (head/tail anchored to the landmarks).
- Try On starts with Landmarks off and Natural brow off (hidden). Initial eyebrow intensity 0.9.
- New: `BrowOverlay`, `BrowSpriteBaker`/`BrowSpriteStore`, `BrowOverlayPicker`, `BrowGeometry.chordOffset`; shader samples
  an overlay in chord space. Tests: `BrowOverlayTests`. Device check pending.
- Device feedback (tilted face): faint natural brow hair and glitter. Hair detection threshold lowered (0.06/0.16 to 0.035/0.11), the
  hidden area now reaches 85% of the way to the eyelid (was 70%), and the overlay is lit by the smooth fill under it instead of
  the camera pixel, sampled with a mip bias, with softer strand detail. Device check pending.
- Recording review: the natural brow tail showed past the overlay and strands vanished on dark shades. The picture now runs
  u -0.04...1.06 (MediaPipe's rows end short of the hair), the brow-space area is wider (-0.3...1.35) with a later, longer tail
  fade, and strand detail also adds a little light. Device check pending.
- The brow picker starts with a "no overlay" tile (`BrowOverlayPicker`, `TryOnHomeModel.browOverlay` is optional): it removes the picture
  only; the natural brow stays hidden or shown as the "Natural brow" toggle has it.
- Brow 3: hair-strand brow rendered from `eyebrows_3d.obj` (right brow, ribbons as 4 px lines; `Tools/BrowOverlay/render_obj_brow.py`).
- Brow redraw is capped at 30 fps (`BeautyBlushEngine.browMaxFramesPerSecond`) to see whether it calms the wobble; the camera picture
  in the eyebrow tool follows the same rate. Device check pending.

## Natural brow: real edge detection, sharper fill — Khalish (2026-10-28)

- Device feedback: brow not fully covered and the fill looked hazy. The eraser now detects the actual brow edge
  (pixels clearly darker than a blurred skin estimate, past MediaPipe's rows) and hides it too; the fill excludes it.
- Full-resolution forehead texture is always added (it was off when MI-GAN ran, whose 256-pixel crop looks soft).
- New test: hair past the landmark rows is hidden; skin above a brow that ends at its landmarks is not.
- Simulator tests pass (344); device check pending.

## MI-GAN bundled — Khalish (2026-10-28)

- Converted MI-GAN 256 FFHQ (Picsart AI Research, MIT code and weights) to Core ML with
  `Tools/MIGAN/convert_migan_coreml.py`; matches PyTorch within 0.0072 (PSNR 68-73 dB in the filled area).
- Bundled as `Resources/MIGANFace256.mlpackage` (12 MB) with its licence notice; "Natural brow" off now uses it on top
  of the brow-space fill. New test runs the bundled model and checks it fills only the hole.
- Simulator tests pass (343); device latency and quality still to check.

## Natural-brow hiding: brow-space fill and MI-GAN runtime — Khalish (2026-10-28)

- Replaced the sample-point skin fill with `BrowEraser`: each brow is unwrapped into brow space and filled by
  push-pull from all the skin around the hidden area (no seams, no grey smudge), with forehead texture and
  temporal smoothing; the result stays attached to the brow.
- Added `BrowInpainter`: MI-GAN (MIT code and weights) via Core ML on an upright face crop, cached in brow space and
  faded over the fill. Runs only once `MIGANFace256` is bundled, which needs the checkpoint converted (ADR 0014).
- New tests: push-pull fills a hole smoothly from both sides, MI-GAN input/output layout, upright face crop.
- Simulator tests pass; device check pending.

## Natural-brow hiding without the patch — Khalish (2026-10-28)

- Device feedback: the hidden area read as a lighter patch, with hard bright slabs at the brow heads and a white
  streak at the temple. Skin colour is now read right next to the brow landmarks and only along the brow (not the
  nose bridge or past the face edge), averaged around its dominant brightness (hair and shine rejected).
- 20% of the original shading is kept so the brow ridge looks natural; detail is symmetric (±25%) so nothing brightens.
- Long, soft fades at the brow head and tail; a slightly smaller area overall.
- Simulator tests pass (339); device check pending.

## Softer natural-brow edge — Khalish (2026-10-28)

- Device feedback: the lower edge was still harsh. The fade near the eye was only ~25% of the hidden depth; it now
  spans at least 55% (ending at most 70% of the way to the eyelid) with a smootherstep profile, and the upper fade is wider.
- Skin fill is sampled at the hidden area's own top and bottom edges and blended between them, so there is no
  brightness step where it meets the forehead or brow bone.
- Hair detail is cut harder (dark detail to 20%), so the old brow shape no longer reads through.
- Simulator tests pass (339); device check pending.

## Smoother natural-brow hiding, black background — Khalish (2026-10-28)

- "Natural brow" off now uses frequency separation: a forehead-weighted, temporally smoothed skin reference for the
  low frequency, plus the original fine detail with hair contrast cut, so skin texture stays instead of a smudge.
- The hidden area's lower edge stops at most 55% of the way to MediaPipe's upper-eyelid row (now tracked and drawn
  in the tracking view), so it covers the lower brow without reaching the crease.
- App screens use a black background (`AppColors.screen`).
- Simulator tests pass (339); the look on a face needs a Face ID iPhone.

## Eyebrow tracking view — Khalish (2026-10-27)

- Eyebrow shapes and the shape picker are hidden for now (kept in code, `EyebrowConfiguration.showsBrowTracking`).
- The eyebrow tool and tutorial Brows tab show MediaPipe tracking: every face landmark, raw vs smoothed brow points,
  brow contours, fitted centerline and brow frame, labelled with MediaPipe indices, plus head pose and timing.
- Test toggles under the eyebrow tool: "Landmarks" shows/hides the whole tracking overlay; "Natural brow" hides the
  user's own eyebrow: a soft-edged, wider-than-contour brow area filled with a smooth, hair-rejecting skin blur
  (the first version's darkness threshold left a grey outline and missed the brow head). Head pose readout is now in screen terms (roll no longer reads about -90° in portrait).
- Simulator tests pass (338); the live overlay and brow hiding need a Face ID iPhone to see.

## New eyebrow shape list — Khalish (2026-10-27)

- Replaced all eight brow presets with nine new shapes following the supplied TikTok effect screenshot: Bold arch,
  Slim arch, Soft natural, Flat straight, Curved arch, Peaked angle, Slim straight, Full arch, Bold straight.
- New `brow.*` presets in the rule database (source `brow_D`), face-shape assignments remapped, default is Soft natural.
- Picker thumbnails now draw each shape's real design curve and thickness; names added to the string catalog.
- Simulator tests pass (336); not yet checked on a device.

## Eyebrow tracking on MediaPipe — Khalish (2026-10-27)

- Eyebrow detection moved from the ARKit mesh + Vision fit to MediaPipe Face Landmarker on the shared camera frames:
  brow contours, eye/nose points and head pose per frame, smoothed, then a brow-local strip samples the style's baked
  brow texture on the same frame the landmarks came from.
- Shader segments the original brow pixels (new "Original brow mask" debug view); composite stays overlay only.
- Tutorial brow guide and nose-eye mapping lines are drawn by the Metal engine; status pill reports when no face is seen.
- Removed the ARKit brow atlas, `BeautyBrowStabilizer` and their tests; added `MediaPipeBrowTests`. Blush unchanged.
- Simulator tests pass; not yet checked on a Face ID iPhone.

## Eyebrow try-on switching and tutorial comparison — 2026-10-27

- Keep the last committed brow atlas visible while a style change is baked, throttle repeated failed binds, and retry a newly selected style immediately so switching does not appear to drop the filter.
- Hide the brow placement and mapping outlines during the tutorial's split comparison; the filtered half now shows pigment against the real eyebrow without the boxy guide.
- Simulator build passes; physical-device AR quality and latency still need Face ID iPhone QA.

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

## Mask continuity and welcome migration — -Nimah (2026-10-28)

Device screenshot showed Preparing makeup visibility; scalar report error=none, GPU about1ms, ~60FPS.
Fix actual hard freshness gate: reprojection uses three native head anchors; 150ms fresh window plus bounded
100ms smooth opacity fade (new consumed mask_fade_seconds). Never show after250ms; no unlimited old mask.
Opacity target is continuous and capped by mask weight, not hard fresh ? alpha : 0. Stale/mismatched dimensions
and implausible reprojection remain excluded. Status waits for low effective visibility. This permits brief
stale-mask fading, not perfect new-hand occlusion: validate on device.
Welcome revision gate dandan.welcome.version shows new hi-fi welcome once on upgrade. Get Started dismisses
welcome; users with completed face/eye results go to try-on, fresh users enter face then eyes. No scan erasure.

## Hi-fi welcome onboarding — -Nimah (2026-10-28)

Welcome uses OnboardingWelcomeScreen, static generated onboarding-silk asset and native logo/copy/CTA.
Match supplied burgundy silk reference. Responsive scroll fallback, Dynamic Type-scaled text, light status
appearance and four progress dots (welcome/face/eyes/preparing). Get Started still enters face scan then eyes.
Preserve saved-scan bypass and Retake routing. No fake system status bar or rasterized controls; no animation,
second camera or model added. Existing in-flight blush look changes stay intact. No merge/push requested.

## Three reference blush looks v0.5.0 — -Nimah (2026-10-28)

User requested Youthful / Sunkissed / Lifted options, overriding prior no-style-picker for blush only.
JSON presets drive the three shapes; same per-cheek anatomical fitting. Sunkissed alone adds upper-nose
bridge channel. Curved Lifted mask, continuous soft falloff, mipmapped pigment atlases, capped 0.25 mm blush
mesh residual and blush-only mask-confidence threshold. No retouch/morph/scan/extra tracker. Five new colors
(total nine), design approximations only. Selected look handed to tutorial; shade/intensity stay independent.
See Docs/Decisions/0013-three-reference-blush-looks.md. Do not merge staging/main without new instruction.

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

## Eyebrow UV / Metal strands — -Nimah (2026-10-27)

- Bake personal, JSON-shaped brows to native face UVs; soft heads, tapered tails and deterministic fine strands.
- Dedicated hair pigment blend and shared depth, camera timing, tracking and obstruction pipeline.
- Suppress duplicate SceneKit pigment; separate category atlas identity and guard delayed GPU completions.
- Keep face-shape recommendations, color/intensity controls, stored scans, tutorial and Retake routes.
- Simulator GPU atlas/occlusion tests included; physical quality acceptance remains pending.

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

### Fixed / Changed — eyeliner tutorial guide and compare button
- Step 2/3 outline now includes the wing (`LinerStepGeometry.shapes` uses `LinerGuide.outlines`, which merges the wing; `upperLiner` alone stops at the outer corner).
- `LinerStepGuide` no longer observes every published liner frame (the timeline redraws it), keeps ticking while held so dots follow the face,
  and its clock only runs while a fresh frame exists; halves are clipped inside the canvas instead of masked.
- Compare button (`TutorialCompare`) cycles five layouts: look|guide, guide|look, look|plain, plain|look, plain. Eyeliner splits per half
  (`LinerOverlayView(visibleSide:)`, `LinerStepGuide(side:)`). Brows/blush draw on one face mesh, so guide layouts show the guide full width and
  look|plain layouts show the look beside the plain camera. Not yet checked on a real device.

### Added — camera messages, light and the three-step eyeliner tutorial (dandan camera and tutorial UX spec)
- New shared folder `Features/CameraGuidance/`, used by every tool: `CameraMessage` (the 11 lines and their priority/delays), `CameraMessageEngine`
  (pure: show/clear delays plus hysteresis, unit tested), `CameraSignalSampler` (reads `ARSession.currentFrame`: light estimate, face-vs-frame
  luma, distance, yaw/roll, speed; Vision face count and coverage about every 0.5 s), `CameraAdvisor` (10 Hz loop, CoreMotion tilt, thermal state),
  `CameraCaption` (the 15 pt pill and STEP label) and `ScreenLight` (screen at full brightness plus a `#FFF4EA` ring; restored when leaving).
  It never takes the ARKit session or its delegate.
- Tutorial and Try On show one message at a time over the camera, fade the preview/guide to 30% and pause the step animation while it shows.
  Serious heat runs the camera at 30 fps (`LiveGuideView.reducedFrameRate`); critical heat pauses it and shows "Your phone is warm".
  "Face covered" is Try On only; "face lost" (2 s) replaces "no face" once a tutorial has tracked the face.
- Eyeliner tutorial: three steps (`LinerTutorialStep`, `Features/Tutorial/LinerStepGuide.swift`): mark dots (inner, middle, outer, wing end; the
  lower-line dot stays for puppy/foxy/arabian), connect them, fill. A drawn pen taps and moves; the loop is 3 s plus a 2 s pause; Reduce Motion
  shows the last frame. The last step's button reads Done and goes to the photo step. Replaces the one-step "Follow the dots".
- Follow-up: head tilt (roll) is ignored and "Face your phone straight on" needs a ~45° turn; tracking lost right after a close or turned face
  says "Move your phone back" / "Face your phone straight on" (`CameraMessageEngine.Limits`, guesses). Tutorial Back/Next are labelled capsules.
  Eyeliner step 2 draws the whole closed outline (a wing is a triangle); the split-compare divider line is gone.
- Camera denied card now reads "I need your camera to be your mirror." with "Turn on camera".
- Brow and blush tutorial lessons are unchanged (long text); they only get the camera messages, the light and Done. While a message shows,
  their guide is hidden rather than faded. Thresholds are the spec's suggestions, not tuned; nothing is checked on a real device (simulator build
  and unit tests only).

### Changed — six eyeliner looks on Try On
- `LinerLook` is now Classic, Cat, Puppy, Foxy, Arabian, Natural (was Liner only / With wing). Each is a fixed preset in
  `EyelinerPlanner.style(_:look:)` (the fitted style only supplies the shade); the picker on Try On scrolls sideways. Default is Classic;
  the tutorial follows the chosen look. Preset numbers are estimates, not yet checked on a real face.

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
