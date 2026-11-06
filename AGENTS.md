## Feedback v1: blush target area on the result photo — -Nimah (2026-11-05)

`FeedbackView` (`Features/Screens/Feedback/`) is no longer a placeholder: one large photo with a Look | Result switch
(opens on Result), the blush target area (the tutorial's small circle and outer line, same dotted white stroke) drawn on
the result photo, tap the photo to hide or show the lines, and a caption. No look photo yet: the Look side says so until
Try On's photo button (Hanum) fills `TutorialHandoff.lookPhoto`. No face seen at the shutter: the photo shows without lines
and says why. Blush off on Try On: no lines or caption. No measuring yet (v2 reads `makeup-feedback.database.json`).
The tutorial now hands over `TutorialPhoto` (image + `blushOutline`, in the photo's 0...1 coordinates) instead of a
bare `UIImage`; `FeedbackInput(handoff:photo:)`. Shared-screen change (Hanum's `GuidedTutorialView`): with blush on
(`GuidedTutorialModel.measuresBlushInPhoto`), the photo configuration keeps the engine on with region blush,
`showGuide` and `pigmentHalf = .none` (no blush pigment encoded: the photo is still the plain camera) so the outlines are
measured on the shutter frame; the tutorial overlay stays hidden in photo mode. New texts have Indonesian drafts (`needs_review`). All in memory. Simulator tests only: the
screen and the line placement on a real photo are not yet seen on a device.

## Feature homepage, one tool per Try On — Khalish (2026-11-05)

After the welcome the app opens on `FeatureHomeView` (`Features/Screens/TryOn/`): three cards, Blush, Eyeliner, Eyebrow
(`TryOnTool.allCases`), no camera. A card pushes `AppRoute.tryOn(tool)`, which builds `TryOnHomeView(tool:)`; the camera
starts there and stops when going back. Try On has no tool strip any more (back button instead), and
`TryOnHomeModel(tool:)` starts on and `activate()` returns to that tool (`startTool`; default `.eyebrow` for tests), so only
that tool can be switched on and drawn; the tutorial and photo get only it. The model logic is otherwise unchanged and still
supports several tools (`choose(_:)` stays for tests): "one tool" is enforced by the screens, not the model. The tutorial's
tab bar shows the tool's name instead of three tabs (`GuidedTutorialModel.select` stays). New strings have Indonesian
drafts (`needs_review`). Simulator only (homepage, card -> Try On -> back); camera, tutorial and photo need a device check.

## Prep page: brow kit list — Khalish (2026-11-04)

`TutorialPrepView` (`Features/Screens/Preparation/`) shows three cards; "Phone at eye level" is gone. The kit card's `Tip.items`
(`KitItem`: image name + label) lists Spoolie, Brow pencil, Cotton bud, picture left, name right. Pictures are vector image
sets `kit-spoolie` (a mascara wand), `kit-brow-pencil`, `kit-cotton-bud`: CC0 SVGs from one SVG Repo pack, sources in
`Resources/KitImages-SOURCES.txt`. To change an item: edit the `items` array and its image set. Brow only; blush and
eyeliner tools are not listed. Simulator render only, no device check.

## Three-page onboarding — Khalish (2026-11-04)

`OnboardingWelcomeScreen` (`Features/Onboarding/Welcome/OnboardingView.swift`) is now three swipeable pages in one `TabView`: the welcome
(logo, Get Started), "TRY IT ON, LIVE" (blush, brows, eyeliner) and "LEARN IT, STEP BY STEP" (tutorial and photo, photos stay on
the phone), with Next, Skip on pages 2-3, three progress dots, and Start Try On calling `onStart`. The old four dots and scan hint
are gone. `AppNavigator.currentWelcomeVersion` stays 2, so only devices that have not yet dismissed the welcome see it. New strings
are in `Resources/Localizable.xcstrings` with Indonesian drafts (`needs_review`); "Step 1 of 4" and the scan hint were removed.
Simulator only, no device check.

## English and Indonesian — Khalish (2026-11-03)

Two languages: English (source) and Indonesian (`id`). Strings are in `Resources/Localizable.xcstrings`, the camera and
photo-library permission prompts in `Resources/InfoPlist.xcstrings`; `knownRegions` has `id`. The Indonesian was drafted by AI
and every entry is `needs_review` until a native speaker checks it. Developer-only strings (eye debug readout, brow debug
menu, format-only keys such as `%lld`) are `shouldTranslate: false`. New UI text: write English in code with `Text("...")` or
`String(localized:)`; an enum title that returns `String` must use `String(localized:)`, or it is never translated. Shade names come
from `makeup-reference.database.json` and are manual catalog keys (`extractionState: manual`): add a key when adding a palette.
`xcodebuild` does not write new keys back into the catalog: build in Xcode, or run
`xcrun xcstringstool sync SunriseApp/Resources/Localizable.xcstrings --stringsdata <the build's .stringsdata files>` and
check the diff. Test with the scheme's App Language or `-AppleLanguages (id)`. Simulator only, no device check.

## Tool-first folders: Features/Blush, Brow, Eyeliner, Screens — -Nimah (2026-11-03)

Files moved, no code, flow or UI change. Each tool is at the top of `Features/`: `Blush/`, `Brow/`, `Eyeliner/`, each with
`TryOn/`, `Engine/`, `Tutorial/`, `Info/`. Screens that show all tools are in `Features/Screens/`: `TryOn/` (was
`Makeup/Shared/Home`), `Comparison/`, `Preparation/`, `Tutorial/`, `Feedback/`. What works behind the screens joined the
top-level `Engine/`: `Camera/`, `Rules/`, `Info/` (`ToolInfo`), and `FaceData/` (was `Makeup/Shared/Support`: face and eye
shape types still in use). `Features/Onboarding/` is unchanged. Owners: Blush and Feedback Nimah; Brow and Onboarding
Khalish; Eyeliner and the other Screens Hanum; `App/`, `Engine/`, `DesignSystem/`, `Resources/` shared (tell the group
first). Paths in older notes: `Makeup/<Tool>/` is now `Features/<Tool>/`, `Makeup/Shared/...` as listed here.

## Guided flow, Phase 0: skeleton behind a switch — -Nimah (2026-11-03)

The new flow (splash, onboarding, compact opening, comparison, preparation, feedback) exists as placeholder screens,
already wired, behind `NewFlow` (`App/NewFlow.swift`, UserDefaults `dandan.newFlow`, off by default). Switch it on with
developer tools (long-press the logo) -> "New flow" chip on Try On: the screens after Try On follow at once, the entry
screens from the next launch. Off, the app is exactly as before. Work split and order: the team page "Pembagian Kerja
Dandan". Placeholders use `FlowPlaceholder` (DesignSystem, English developer text, replace the whole view).

- Entry (Khalish): `Features/Onboarding/` now has `Splash/SplashView`, `Pages/OnboardingPagesView` (2 pages),
  `CompactOpening/CompactOpeningView`, run by `EntryFlowView`; the existing welcome moved to `Welcome/OnboardingView.swift`.
- After Try On (Hanum): routes `AppRoute.comparison` -> `.preparation` -> `.recommendedTutorial` -> `.feedback`.
  `Makeup/Shared/Comparison/ComparisonView`, `Makeup/Shared/Preparation/PreparationScreen` (wraps `TutorialPrepView`, moved
  here). `TutorialHandoff.lookPhoto` (memory only) is for the Try On photo, nil until that button exists.
- Feedback (Nimah): `Makeup/Shared/Feedback/FeedbackView`, input `FeedbackInput` (handoff + result photo).
  `GuidedTutorialView(onFinish:)` hands the result photo over on Done instead of closing.
- Per-tool data: `ToolInfo` (`Makeup/Shared/Info/`: look name, description, `minutes`, tools and products; each `Item` has
  name, detail, alternative, symbol, `required` (false: nice to have), `imageName` (asset instead of the symbol) and
  `showsShade` (product card shows the chosen shade)) is
  filled by each tool in `Makeup/<Tool>/Info/` (`BlushInfo`, `BrowInfo`, `EyelinerInfo`, sample wording to replace);
  `ToolInfo.chosen(in:)` gives the tools that are on. Field rules and examples: the team page "Data Alat dan Produk".
- `BlushLookPicker` (`Makeup/Blush/TryOn/`) is the blush look row moved out of `TryOnHomeView`, unchanged.
Tests: `GuidedFlowTests` (331 pass). Seen on the Simulator: the splash; the rest checked by tests only, not on a device.

## Unused code deleted — -Nimah (2026-11-02)

Checked by building, not guessed: everything in `Features/Legacy/` was deleted, then the app and tests were built and
any file still needed was put back. Kept and moved to `Makeup/Shared/Support/`: `EyeScan` (`EyeShape`, used by
`EyelinerPlanner`), `FaceShape`, `FaceProportions`, `FaceContourMeasurer`, `FaceMeshMeasurer`, `EyeMeasurer`,
`EyeScanLandmarks`, `FaceFeatureMap`, `FaceFit`; `ScanDebugOrientation` (`AppOrientationDelegate`, portrait lock) to `App/`.
Deleted: face/eye scan screens and classifiers, Scan Debug, `SunriseDebugMac/` (its tab was gone), old try-on and tutorial,
Profile, catalog/import/saved looks, comparison, calibration, mocks, `PreviewSupport`, unused design components, the
`.sunrisescan` type in Info.plist, `mediapipe-canonical-face.json` and its licence, images `AppIcon test`, `logo-grey`,
`brow-overlay-3`. `AppRoute` keeps only `recommendedTutorial`; `AppContainer` only `faceTracking`; the old scan
`OnboardingView` is gone (`OnboardingWelcomeScreen` stays). `MockFaceTrackingChecker` moved to the tests' `ServiceStubs`.
Tests of deleted code were deleted (423 -> 327); two Try On/tutorial tests now build their plan with `MakeupPlan(shape:)`
as the app does, and three navigation tests use the tutorial route. No flow or UI change.

## Folders per tool: Makeup/<Tool>/{TryOn,Engine,Tutorial}, Legacy — -Nimah (2026-11-02)

Files moved, no code, flow or UI change. Live code is under `Features/TryOn/`, one folder per tool, each with `TryOn/`
(what the Try On screen shows: pickers, looks, config), `Engine/` (what draws it on the camera) and `Tutorial/` (steps,
animations); `Shared/` holds what the tools share: `Home/` (Try On screen, live card, palette), `Camera/` (LiveGuide,
CameraGuidance, `DeviceFaceTrackingChecker`, `TrackingReadiness`), `Tutorial/` (`GuidedTutorialView` shell, prep page,
photo), `Rules/` (rule database, `MakeupPlan`, recommendation types), `Support/` (five files from the old scan/try-on that
live code still uses: `FaceContourDetector`/`SendablePixelBuffer`, `FaceShapeClassifier`/`FaceShapeResult`,
`EyeShapeResult`, `EyeDebugView`/`DeveloperTools`, `MakeupTextureRenderer`; their own dependencies still live in Legacy).
`Core/Engine/` keeps the shared engine (`BeautyBlushEngine`, `BeautyBlush.metal.txt`, `MediaPipeBrowTracker`).
`Features/Legacy/` holds what the app no longer reaches, kept, not deleted: `Scan/` (FaceShape, EyeShape), `ScanDebug/`,
`OldTryOn/` (old try-on screen and renderer, `EyebrowOverlayView`, `ProfileView`, `BlushMask`, `BlushPlacementSketch`),
`OldTutorial/`, `Reference*`, `SavedLooks/`, `Comparison/`, `FaceCalibration/`, `BlushComparison/` (orphans, not in the
project). `Onboarding/` (welcome) stays. `SunriseDebugMac` paths follow. Types keep their names; resources load by bundle
name. Older notes below use the old paths:

Split, no logic change (2026-11-02, second commit): each tool's tutorial is in its `Tutorial/` folder as an extension of
`GuidedTutorialModel` (`BlushTutorial.swift`: `blushLessons` and `BlushTutorialOverlay`, now internal;
`BrowTutorial.swift`: `browLessons`; `EyelinerTutorial.swift`: `linerLessons`, `linerShowsLower`); the shell
(`GuidedTutorialView.swift`: handoff, compare, tabs, per-tab `liveConfiguration`, screen, photo) stays in
`Shared/Tutorial/`. The blush parts of the engine moved from `BeautyBlushEngine.swift` to
`TryOn/Blush/Engine/BlushEngine+Draw.swift` (cheek landmark fit, guide outlines, `bind`, `prepareBlush`, `encodeBlush`), like
the brow's `BrowEngine+*`; `Core/Engine/BeautyBlushEngine.swift` keeps state, setup, configure/submit, `render`, the mask.

Top level and name (2026-11-02, third commit; files only): `Features/TryOn/` is now `Features/Makeup/` (it holds Try On
and tutorial). `SunriseApp/` has five folders: `App/` (entry, root view, container, navigation, `Info.plist`, was
`Configuration/`), `Engine/` (was `Core/AR` + `Core/Engine`, plus `FaceTrackingAvailability` and
`FaceTrackingAvailabilityChecking`), `Features/`, `DesignSystem/` (theme and `GlassKit` only) and `Resources/`.
`Core/Models/Tutorial.swift` moved to `Makeup/Shared/Tutorial/`; the rest of `Core/Models`, `Core/Services/Contracts` and
`PreviewSupport/` went to `Legacy/Scaffold/`, the scan components and `ScanOverlay` to `Legacy/Scan/`, unused components
to `Legacy/DesignSystem/`. `INFOPLIST_FILE` is `SunriseApp/App/Info.plist`. Paths above that say `TryOn/<Tool>` or
`TryOn/Shared` now read `Makeup/<Tool>` and `Makeup/Shared`; `Core/Engine/` reads `Engine/`.

| Old | New |
| --- | --- |
| `Features/TryOnHome/` | `TryOn/Shared/Home/`; brow/liner pickers in their tool's `TryOn/`; prep page in `Shared/Tutorial/` |
| `Features/Tutorial/` | `TryOn/Shared/Tutorial/` (`GuidedTutorialView`, photo); `BrowTutorialOverlay` → `Brow/Tutorial/`, `LinerStepGuide` → `Eyeliner/Tutorial/` |
| `Features/BeautyBlush/`, `Features/Blush/` | shared engine in `Core/Engine/`, blush drawing in `TryOn/Blush/Engine/`; config and placement in `TryOn/Blush/TryOn/` |
| `Features/Eyebrow/`, `Features/Brow/` | `TryOn/Brow/TryOn/` (style, overlays, view model, picker) and `TryOn/Brow/Engine/` (drawing, tracking, eraser, forehead guide) |
| `Features/MakeupTryOn/Eyeliner/` | `TryOn/Eyeliner/Engine/` (with `LinerGeometry`); `EyelinerPlanner` → `Eyeliner/TryOn/` |
| `Features/LiveGuide/`, `Features/CameraGuidance/` | `TryOn/Shared/Camera/` |
| `Features/MakeupPreferences/` | `TryOn/Shared/Rules/` |
| `Features/Forehead/` | `TryOn/Brow/Engine/` |
| `Features/FaceShape/`, `Features/EyeShape/` | `Legacy/Scan/` (except the `Support/` files above) |

## Brow tutorial demo, face-midline split, get-ready page on Try On — 2026-11-02

`BrowTutorialOverlay` (Features/Tutorial) draws the brow tutorial of UX spec 3.4 on the brow outlines the engine publishes
(`BrowGuideFeed`, `BrowEngine.browGuide`): guide outline, three dots, pulsing regions, spoolie/pencil/cotton bud. The
tutorial's split comparison cuts at the face's midline (`FaceSplitFeed`, `BeautyBlushEngine.updateSplit`: nose bridge for brows,
the face anchor for blush, which also scissors the blush pigment), not at the screen's middle. The "get you ready" page is an
overlay of `TryOnHomeView` (`prepHandoff`), no longer the route `tutorialPrep`: replacing a pushed route with the tutorial in one
path update was the suspected cause of the arrow doing nothing after coming back from the tutorial (not reproduced; no device
log). The photo screen's flash now turns on the screen light. Device check pending.

## Brows compare one brow at a time; brow overlay cleanup — Khalish (2026-11-02)

The Brows tab's compare button cycles `BrowCompare` (`.both` → `.left` → `.right` → `.off`), not the split screen. `EyebrowConfiguration.browOnlySide`
(`.subjectLeft`/`.subjectRight`, nil = both brows) makes `drawBrow` draw only that half of the strip index buffer (`BrowEngine+Draw`); `comparisonSplit`
stays false on Brows. `.off` is the plain camera: no hidden natural brow, guide or preview. Blush still cycles the split (`TutorialCompare`).
Removed the eight `brow-sample-1…8` overlays and the `mirrorsForPair` flag: the `supplied.*` PNGs are already head-left/tail-right, so
`browStrip` and the shader no longer mirror them. Simulator build only; device check pending.

## Brow tracker frames via VideoToolbox — Khalish (2026-11-01)

`MediaPipeBrowTracker.bgra(from:)` scales the ARKit YCbCr frame to the 512-long-side BGRA pool buffer with a lazily created
`VTPixelTransferSession` (scaling mode normal, whole source, one call) instead of a Core Image graph per frame. The session lives
on the tracker's serial queue and is invalidated there in `stop()`. If a transfer fails, that frame uses the old `CIContext` render
(still lazy). MediaPipe's `MPImage(pixelBuffer:)` only takes BGRA/RGBA buffers (`MPPImage+Utils.mm`), so a conversion stays
needed. VT uses the buffer's YCbCr matrix attachments and writes the pool buffer's own colour space; no extra colour management.
Simulator build only; device timing and colour match not measured.

## Brow draw loop cleanups — Khalish (2026-11-01)

No behaviour change: the brow's per-frame work is trimmed. Marks use a 3-slot buffer ring like the brow vertices, the developer
menu flags are read at most twice a second, the camera colour attachments are read only when the pixel format or size changes,
and the natural-brow unwrap grid is built only on frames where the eraser's fill is due (`BrowEraser.isDue`). Simulator build only; device check pending.

## Brow split compare in Metal — Khalish (2026-11-01)

The tutorial no longer stacks a second `ARSCNView` (`RealCameraView`, deleted) masked over half the screen. Merged with
staging (2026-11-02): blush halves use staging's `pigmentHalf` (scissor in `render`); this change's `HorizontalEdge`
`comparisonSplit` and `splitScissor` were dropped, and the Brows tab no longer splits (see the top section). Simulator build only;
device look pending.

## Brow: legacy fit off while Metal draws — Khalish (2026-11-01)

When the Metal engine is installed and the configuration is brow-only (`needsBrow`, not blush, not `layered`, not
`showAllRegions`; `LiveGuideView.Coordinator.metalBrowOnly`), the old ARKit/Vision/SceneKit brow path no longer runs: no
`LaunchMakeupFit.fitLive`, `followLaunchFit` or Vision `observe` per frame, `renderEyebrows` hides the anchor node and
returns before copying vertices or taking a pipeline snapshot, and the 0.1 s publish no longer builds a brow snapshot (it
sets `eyebrowWasTracked`/`eyebrowGuideReady` to true once the face is tracked, for the legacy `EyebrowOverlayView`).
Layered/blush/all-regions configurations keep the old behaviour. The ARSCNView drops 4x MSAA once the engine is
installed (kept if it failed, since SceneKit then draws the brow); it stays at 60 fps. Simulator build only; device check pending.

## Eyeliner stretch follow and native Liquid Glass — 2026-10-31

`LidFollower` now starts a pull from the skin's own motion (`skinSpeed`/`skinFrames`), holds it until the followed points and
the detector agree (`stretchRelease`), and pulls back slowly while held (`stretchPullPerResult`); `refresh` + `LinerOverlayModel.refollow`
redraw the followed lid every camera frame. Tutorial and Try On share the model, so guide dots follow too. Benchmark:
`LinerStretchTests`. UI controls use `DesignSystem/Components/GlassKit.swift` (native `glassEffect`; tints `AppColors.glassBase`/
`glassSelected`); the image assets for buttons are gone. Simulator needs iOS 27.0 (target is 26.6); with `xcode-select` on the
Command Line Tools use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Device check pending. See ADR 0018.

## Tutorial brow and eyeliner guides back — -Nimah (2026-10-30)

After Try On started bare, the Brows tab turned its makeup preview off for a brow that was off, which stopped the makeup
engine and with it the brow guide (drawn by that engine). Now the tab keeps the engine on and only drops the brow picture
(`browOverlay = nil`, natural brow left alone). The face landmarker the engine starts for the blush cheek fit is stopped
whenever the engine has nothing to draw (e.g. the Eyeliner tab), so it no longer runs beside the eyeliner's own MediaPipe
detector. The eyeliner cause is not confirmed on a device.

## Blush tutorial comparison like eyeliner, one camera — -Nimah (2026-10-30)

The Blush tab uses the five compare layouts the way the eyeliner does: look | guide, guide | look, look | plain,
plain | look, plain. The pigment is clipped to the look's half (`EyebrowConfiguration.pigmentHalf`, engine
`Settings.pigmentHalf`: full, left, right, none; scissor in `render`), the animated guide (`BlushTutorialOverlay`) to the
guide's half over the bare camera. The Metal camera stays on in every layout (`showMakeupPreview` true for the tab), so the
halves never come from different cameras: `RealCameraView` (a second ARSCNView, a visible seam) is now used by the Brows
tab only. `comparisonSplit` still means `.left` when `pigmentHalf` is nil. Device check pending.

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
BytePlus exists; the orphan `Features/Blush/Comparison/` files are not in the project. See ADR 0017 and
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
## Brow frame rate — Khalish (2026-10-29)

No frame cap until the phone is hot: `BrowLoad.trackerFPS`/`drawFPS` are nil at nominal and fair thermal state, so every
camera frame is drawn unless the previous one is still queued, and MediaPipe takes every frame it is free for (`isBusy`).
Serious and critical: 15 fps tracker / 30 fps draw. Lifting landmarks onto the face mesh (`BrowFaceStabilizer`) passes
`projectedVertices()` so each ray tests only triangles around its pixel; `browStrip` evaluates the centerline once per
column (`BrowGeometry.section`). Device check pending.

## Tutorial bottom bar and screen light — Khalish (2026-10-29)

The tutorial's background is `AppColors.wine`, like Try On. Its bottom bar is compare (`CameraBarButton`, left), the tabs
Blush / Brows / Eyeliner, and the screen light (right). `ScreenLight` (DesignSystem/Components) sets brightness to 1 and
`ScreenLightGlow` draws a 24 pt `AppColors.ringLight` (#FFF4EA) frame round the camera; leaving restores the brightness,
backgrounding suspends it and returning turns it back on. Try On has no light
button yet. Simulator build only; device look pending.

## Brow drawn on every ARKit frame — Khalish (2026-10-29)

Like blush, the brow now draws each ARKit camera frame (`drawLiveBrow`, up to `BrowLoad.trackerFPS`, skipping frames while one
is still queued) instead of only when MediaPipe answers. A MediaPipe answer only updates `browLatest` (steadied on that frame's
face by `BrowFaceStabilizer`); each live frame moves it onto its own face pose (`BrowFaceStabilizer.reproject`), or draws it
where it was seen when ARKit had no face, and drops it after 0.5 s without a new answer. The camera picture no longer waits for
MediaPipe. Device check pending.

## Brow code split out of BeautyBlush — Khalish (2026-10-29)

There is still one makeup engine, `BeautyBlushEngine` (blush and brow share its camera session, Metal layer, hand mask and
shader library). Its brow-only parts now live in `Features/Brow/Engine/` as extensions: `BrowEngine+Tracking` (fps cap,
`BrowLoad`, handing frames to MediaPipe), `BrowEngine+Draw` (brow strip, texture/picture, `drawBrow`), `BrowEngine+Hair`
(3D hair), `BrowEngine+Marks` (tutorial mapping, tracking view), `BrowEngine+Fixtures` (DEBUG test helpers), plus
`BrowEraser`/`BrowInpainter` and the brow shaders `Brow.metal.txt`. `BeautyBlushEngine.swift` keeps stored state, setup,
configure/pause/submit, camera decoding, the mask and blush. Engine members are internal (not private) so the extensions
in other files can reach them. `BeautyBlushShaders.sources` joins `BeautyBlush.metal.txt` then `Brow.metal.txt` into one
library (brow shaders use the shared helpers defined first); shader changes are only checked at runtime, by the tests.
No behaviour change.

## Brow load: SceneKit, fill model, temperature — Khalish (2026-10-29)

The `ARSCNView` under the brow's Metal layer stays at 60 fps: slowing it to 10 (tried 2026-10-29) also slowed the ARKit
frames the brow is drawn from, and the brow lagged and dropped out. MI-GAN (`BrowEraser.modelDue`) is asked again only after the face crop moved more than 6% of its size or
1 s passed (never sooner than 0.12 s); its answer stays mapped in brow space between requests. `BeautyBlushEngine.BrowLoad`
follows `ProcessInfo.thermalState`: nominal 40 fps tracker / 15 Hz mask / model; fair 30 fps / 10 Hz / model ≥0.5 s;
serious and critical 20 fps / 8 Hz / no model (push-pull fill only). Not measured on a device.

## Tutorial follows the Try On brow filter — Khalish (2026-10-29)

`TutorialHandoff` now carries `browOverlay` and `hideNaturalBrow` besides tool, shades and intensities; the Brows tab draws that
picture with the chosen shade and strength (`GuidedTutorialModel.liveConfiguration`). The tutorial no longer shows the landmark
view: brow mapping as with a pencil: dashed magenta lines from each side's nostril wing (MediaPipe 129/358, as an offset
from the steadied ala 98/327) through the inner eye corner (Start), the iris ring's outer edge (Arch; 469-472/474-477, else
iris centre + 0.2 eye width) and the outer eye corner (End), with cyan dots and labels where they cross the brow
(`BeautyBlushEngine.mappingMarks`, full-filter mode only). The mapping is drawn as soft white dashes with small pink
dots ringed in white, no labels. The Brows tab has its own five steps (`GuidedTutorialModel.browLessons`: brush up, mark three
dots, outline, fill, brush through; its own `browStep`, not the brow model's step) shown as a spaced "STEP 1 OF 5" over one
instruction in a wine pill; the mapping shows only on the dot and outline steps (`browMappingSteps`). The guide and the brow no longer wait for
the face-skin mask: a mask up to 0.6 s old keeps hands in front, an older one draws the brow without occlusion instead of
fading it out (the brow used to vanish whenever the segmenter fell behind). Brow tracking runs at up to 40 fps (`browMaxFramesPerSecond`, one frame per 1/40 s slot: two of every
three 60 Hz camera frames), still skipped while MediaPipe is busy. Try On → tutorial no longer hangs: `LiveGuideView` keeps a screen whose camera
lease was taken (`revoked`) from taking it back until it is paused. The split
button's "real" half was a second `ARSCNView` (`RealCameraView`, removed 2026-11-01: the engine scissors the look instead). Simulator tests only; split and smoothness need a device check.

## ARKit pose for the brow, and the 3D hair brow — Khalish (2026-10-28)

Details in `Docs/Decisions/0015-arkit-brow-pose.md`. `BrowFaceStabilizer` lifts MediaPipe's brow landmarks onto ARKit's face
mesh (same frame's anchor), smooths them in face-local metres and projects them back (fallback: the image-space smoother when
ARKit has no face or disagrees). "Brow 3D" (`BrowOverlay.is3D`) draws `brow-hair-3d.obj` ribbons on ARKit's pose with a depth-only
face mesh pass, 1.5 px minimum hair width, ambient-light shading and the hand mask; it falls back to its picture without a tracked
face. Removed from the picker list (`BrowOverlay.all`) on 2026-10-29, with Brow 3 (its image set `brow-overlay-3` stays in the assets, unused); the 3D renderer stays, add an `is3D: true` entry
to bring it back. New shader code is only checked at runtime: compile the shader sources (`BeautyBlushShaders.sources`) with `MTLDevice.makeLibrary(source:)` (a build
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

`AppColors.screen` (black) is the full-screen background of the tutorial, the palette sheet and placeholder pages;
`AppColors.wine` stays for pills and accents. Try On's background is `AppColors.wine` (#660033) again (2026-10-29).

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
  eye scan in `Features/EyeShape`. One app target (`SunriseApp`) and one unit test target (`SunriseAppTests`).
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
                          Info.plist (camera + photo-library-add usage strings)
  Engine/                 shared engine (Metal, ARKit session, hand mask, MediaPipe tracker) + Camera/, Rules/, Info/, FaceData/
  DesignSystem/
    Theme/                AppColors, AppSpacing, AppTypography (use these, never hard-coded values)
    Components/           GlassKit (frosted glass buttons and pills)
  Features/
    Blush/ Brow/ Eyeliner/  one folder per tool: TryOn/ (pickers, looks, config), Engine/ (drawing), Tutorial/ (steps), Info/ (look, kit)
    Screens/              screens that show all tools: TryOn/, Comparison/, Preparation/, Tutorial/, Feedback/
    Onboarding/           Welcome/ (shown once); Splash/, Pages/, CompactOpening/ + EntryFlowView (new flow)
  Resources/              Assets.xcassets (named colours), Localizable.xcstrings
SunriseAppTests/
  Features/               makeup engine, blush, brow, eyeliner, tutorial, camera message tests
  Navigation/             AppNavigatorTests
  TestSupport/            ServiceStubs
```

## Navigation

- The app opens on the welcome (once per `AppNavigator.currentWelcomeVersion`), then `FeatureHomeView` (three tool
  cards, no camera). Routes: `AppRoute.tryOn(TryOnTool)` (card -> Try On for that one tool) and
  `AppRoute.recommendedTutorial(TutorialHandoff)` (Try On -> tutorial); `AppRootView.destination` builds both. To add a
  screen: add a case, its destination, and push it with `navigator.open(route, in: .tryOn)`.
- `AppTab` and the per-tab paths in `AppNavigator` remain, though only `.tryOn` is shown.

## Features

Everything the app shows is in `Features/Makeup/` (see the folder note at the top) plus `Features/Onboarding/`
(`OnboardingWelcomeScreen`). The face/eye scan, Scan Debug, the Mac scan editor (`SunriseDebugMac/`), the old try-on and
tutorial, catalog, saved looks and other scaffold pages were deleted on 2026-11-02; sections and notes elsewhere in this
file that describe them are history. Get them back from git history (before commit "chore: delete unused code") if needed.

## Rules

- **Adding files:** create them in `Features/<Feature>/` and add them to the matching group **and** target in
  `project.pbxproj` (PBXFileReference, PBXGroup child, PBXBuildFile, Sources phase). Then build to confirm.
- **Third-party code:** MediaPipe is the only package dependency; the MI-GAN Core ML model (ADR 0014) is the only bundled
  third-party model besides MediaPipe's own, and its MIT notice must stay in `Resources/MI-GAN-LICENSE.txt`. `import MediaPipeTasksVision` is limited to the detector wrappers
  (`MediaPipeEyeLandmarkProvider`, `HandOcclusionSegmenter`, `MediaPipeBrowTracker`); everything else
  works on plain landmark arrays. A new dependency needs an ADR in `Docs/Decisions/`.
- **Dependencies:** inject them through initializers. `AppContainer` is used only in `AppRootView`; features never reach into it.
- **Shared files** (`AppRootView`, `AppRoute`, `AppNavigator`, `AppContainer`, `project.pbxproj`, `Engine/`,
  design tokens, strings): keep edits small and mention them in the PR. Change contracts in their own PR (see `Docs/IntegrationContracts.md`).
- **Concurrency:** strict mode is on. Keep Vision and image work off the main actor (`Task.detached`). Use `Sendable`
  snapshots across actors, and `nonisolated` ARSession delegate methods with `MainActor.assumeIsolated`.
- **UI:** use `AppColors` / `AppSpacing` / `AppTypography` and Dynamic Type text styles. User-facing strings go in
  `Localizable.xcstrings`, with English as the source language.
- **Privacy:** no networking, analytics or uploads. Never persist photos, camera frames or face meshes; the tutorial photo
  stays in memory and leaves the app only through the share sheet. A new permission needs an Info.plist usage string.
- **Honesty:** don't describe mock or sample data as real user results, and don't claim AR works on the strength of a Simulator run.
- **Git:** branch from `main` as `feature/…`, `fix/…` or `chore/…`. Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
  Keep refactors separate from features.

## Out-of-date team docs

These still describe the scaffold from before FaceShape and MakeupTryOn. Trust this file and the code where they disagree.

- `README.md`, `Docs/ProductScope.md`, `Docs/Architecture.md`: say there's no camera or ARKit, two tabs, and onboarding that resets every launch.
- `Docs/NavigationFlow.md`: no Try On tab, `faceScan` or `makeupTryOn` routes.
- `Docs/Testing.md`, `Docs/Validation.md`: the test counts and the "no camera permission" checks are from the scaffold.
- `Docs/IntegrationContracts.md` is current for face shape (section "Analisis bentuk wajah").
