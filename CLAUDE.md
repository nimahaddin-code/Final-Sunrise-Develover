# Sunrise (Final-Sunrise-Develover)

SwiftUI, iOS 17+, light MVVM. Docs are in Indonesian: `Docs/Architecture.md`, `Docs/IntegrationContracts.md`.

## Rules (from Docs)
- One external dependency: MediaPipe Tasks Vision (eyeliner only), vendored as xcframeworks in `Vendor/MediaPipe` (git-ignored, ~370 MB; run `Scripts/fetch-mediapipe.sh` after cloning). No Pods/SPM. One app target + one unit test target. See `Docs/Decisions/0002-mediapipe-eyeliner.md`.
- Feature-based folders. `ObservableObject` + `@Published`; ViewModels and navigator are `@MainActor`.
- No AppContainer access from ViewModels/singletons/Environment; root passes services via initializers.
- Services are async + Sendable; heavy work (images, Vision, file I/O) off the main actor.
- Framework types (UIImage, ARFaceAnchor) never enter shared domain/contracts in `Core`.
- AR overlays follow the tracked face mesh/anchor, never fixed screen coordinates. Exception: the eyeliner is a 2D overlay built from MediaPipe landmarks and mapped through the frame's display transform (ADR 0002).
- Handle permission, unsupported device, session failure, interruption, tracking loss; keep manual fallback.
- Don't persist mesh or send photos anywhere. Don't add mandatory ARKit entitlements.

## Live makeup try-on: `SunriseApp/Features/MakeupTryOn`
Brows and blush: ARKit face tracking -> Vision brow/eye points (averaged) mapped to face-mesh UV (`FaceFeatureLocator`,
`FaceFeatureMap`) -> `MakeupTextureRenderer` draws each category into its own texture -> `MakeupARView` (mesh material).
Eyeliner: ARKit frames -> MediaPipe Face Landmarker (`Eyeliner/MediaPipeEyeLandmarkProvider`) -> `LinerTracker`
(One Euro smoothing, open-eye baseline, `LinerPathBuilder`) -> 2D `LinerOverlayView` above the AR view
(`ImageToViewMapping`). Style comes from the eye shape measured in the face scan (`EyelinerPlanner`, `EyeScan`).
`DEBUG` only: launch arg `-legacyMeshEyeliner YES` draws the liner in the mesh texture instead, for comparison.
`FaceFit`/`MakeupFitter` fit styles to the face; `MakeupRecommender` is the catalog; `MakeupPlan` blends styles.
Models: `MakeupRecommendation.swift` (BrowStyle, BlushStyle, LinerStyle, MakeupPalette).

## Build / test (simulator: iPhone 17 Pro; `xcode-select` points at CommandLineTools, so set DEVELOPER_DIR)
Never read full xcodebuild logs; always use these filters. Fetch the MediaPipe frameworks first if `Vendor/MediaPipe` is empty.
```
Scripts/fetch-mediapipe.sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Build
xcodebuild -project SunriseApp.xcodeproj -scheme SunriseApp -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -E "error:|warning:.*(Liner|Makeup)|BUILD (SUCCEEDED|FAILED)" | head -40
# Test (SIM = an iPhone 17 Pro simulator id; the name destination does not resolve)
SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro " | head -1 | grep -oE '[0-9A-F-]{36}')
xcodebuild -project SunriseApp.xcodeproj -scheme SunriseApp -destination "id=$SIM" test 2>&1 | grep -E "error:|failed|TEST (SUCCEEDED|FAILED)|Executed" | tail -40
```
List sims: `xcrun simctl list devices available | grep iPhone`.

## Git
`EyelinerSpike/` (MediaPipe prototype) is local-only, excluded via `.git/info/exclude`; never commit it. Don't push unless asked.
