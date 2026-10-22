# AGENTS.md — read this first

## Current merged scope — -Nimah

This section supersedes older status descriptions below. Khalish owns face/eye scanning and saved outputs;
Nimah owns eyebrow/blush placement and tutorials; Hanum owns the eyeliner planner/live overlay. The duplicate
Khalish eyebrow/blush catalog, personalizer and renderer were removed. Shared measurement/data helpers remain.
MediaPipe is used by both eye scanning and eyeliner (including hand occlusion); it is linked only to the app.
The package is pinned to revision `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb`.
Khalish's scan-specific landmark model/file is named `EyeScanLandmarks` to avoid Hanum's `EyeLandmarks` collision;
measurement mathematics is unchanged. Both sets of eye tests are retained.
Catalog/import/save and Nimah studio are implemented MVP features, not placeholder-only services.
See `Docs/CodeOwnership.md`, `Docs/Performance.md`, and `Docs/Validation.md`; historical notes below may predate integration.

Saved-analysis flow: onboarding runs Khalish face scan then eye scan. `FaceShapeStore.latest` supplies Nimah
eyebrow/blush presets; `FaceShapeStore.eyes` supplies Hanum eyeliner via the `MakeupPlan` adapter. Saved analysis
opens eyebrow/blush preview directly, with tutorial immediately available. Live geometric alignment is automatic,
not another classification step. Eye-scan measurements are converted using matching units; the lid is never
guessed from `mayBeHooded`. Missing/unclear measurements use the neutral liner. Older scans can still use the
eye measurements embedded in the face result when no separate eye result exists. Eyeshadow is outside this scope.

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
  Core/
    Models/               cross-feature models: MakeupReference, Tutorial, SavedLookMetadata, FaceTrackingAvailability
    Services/Contracts/   Sendable async service protocols (catalog, saved looks, tracking availability)
  DesignSystem/
    Theme/                AppColors, AppSpacing, AppTypography (use these, never hard-coded values)
    Components/           PrimaryButton, EmptyStateView, FeaturePlaceholderView
  Features/
    FaceShape/            face shape scan (ARKit mesh + Vision) and photo classification. Entry: FaceAnalysis.swift
    MakeupTryOn/          makeup recommendations and live AR try-on
    Onboarding/           welcome screen, then the face scan
    EyeShape/             eye shape (openness, tilt, spacing) from MediaPipe landmarks. In progress: measuring and classifying are done and tested,
                          the scan screen, onboarding step, home card and Try On route exist; not yet checked on a real face
    ReferenceCatalog/ ReferenceDetail/ ReferenceImport/ FaceCalibration/ Tutorial/ LiveGuide/ Comparison/ SavedLooks/
                          scaffold features: mostly placeholder UI on mock data
  PreviewSupport/         SampleData + Mock services (used by previews and the scaffold container)
  Resources/              Assets.xcassets (named colours), Localizable.xcstrings
  Configuration/          Info.plist (camera + photo-library-add usage strings)
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
- `EyeMeasurer.measure(_:)` gives `EyeMeasurements` (openness, tilt, spacing, lidSpace in iris diameters). It derives the face's own axes
  from the points, so roll, scale, mirroring and y-down images do not matter. `EyeMeasurementsSampler` takes the per-field median and skips blinks.
- `EyeShapeClassifier` turns measurements into `EyeShapeResult` (`EyeOpenness`, `EyeTilt`, `EyeSpacing`, `mayBeHooded`, `confidence`). The eyelid
  (`EyeLid`) cannot be seen in landmarks, so the person chooses it later; it stays `nil` until then.
- The thresholds in `EyeShapeClassifier.Thresholds` and `EyeMeasurer.minimumOpenness` are starting guesses, not tuned on real faces.

### Scaffold features

Catalog, detail, import, calibration, tutorial, live guide, comparison and saved looks are still the original
scaffold. Their services are mocks composed in `AppContainer.scaffold()`, and Save throws `notImplemented` on purpose.
Keep their placeholder labels until a real implementation is tested (see `Docs/ProductScope.md`).

## Rules

- **Adding files:** create them in `Features/<Feature>/` and add them to the matching group **and** target in
  `project.pbxproj` (PBXFileReference, PBXGroup child, PBXBuildFile, Sources phase). Then build to confirm.
- **Third-party code:** MediaPipe is the only dependency. `import MediaPipeTasksVision` appears in one file,
  `Features/EyeShape/MediaPipeEyeDetector.swift`; everything else works on plain landmark arrays. A new dependency needs an ADR in `Docs/Decisions/`.
- **Dependencies:** inject them through initializers. `AppContainer` is used only in `AppRootView`; features never reach into it.
- **Shared files** (`AppRootView`, `AppRoute`, `AppNavigator`, `AppContainer`, `project.pbxproj`, Core contracts,
  design tokens, strings): keep edits small and mention them in the PR. Change contracts in their own PR (see `Docs/IntegrationContracts.md`).
- **Concurrency:** strict mode is on. Keep Vision and image work off the main actor (`Task.detached`). Use `Sendable`
  snapshots across actors, and `nonisolated` ARSession delegate methods with `MainActor.assumeIsolated`.
- **UI:** use `AppColors` / `AppSpacing` / `AppTypography` and Dynamic Type text styles. User-facing strings go in
  `Localizable.xcstrings`, with English as the source language.
- **Privacy:** no networking, analytics or uploads. Never persist photos, camera frames or face meshes. A new permission needs an Info.plist usage string.
- **Honesty:** don't describe mock or sample data as real user results, and don't claim AR works on the strength of a Simulator run.
- **Git:** branch from `main` as `feature/…`, `fix/…` or `chore/…`. Use conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
  Keep refactors separate from features.

## Out-of-date team docs

These still describe the scaffold from before FaceShape and MakeupTryOn. Trust this file and the code where they disagree.

- `README.md`, `Docs/ProductScope.md`, `Docs/Architecture.md`: say there's no camera or ARKit, two tabs, and onboarding that resets every launch.
- `Docs/NavigationFlow.md`: no Try On tab, `faceScan` or `makeupTryOn` routes.
- `Docs/Testing.md`, `Docs/Validation.md`: the test counts and the "no camera permission" checks are from the scaffold.
- `Docs/IntegrationContracts.md` is current for face shape (section "Analisis bentuk wajah").
