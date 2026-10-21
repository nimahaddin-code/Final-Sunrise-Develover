# Sunrise (Final-Sunrise-Develover)

SwiftUI, iOS 17+, light MVVM. Docs are in Indonesian: `Docs/Architecture.md`, `Docs/IntegrationContracts.md`.

## Rules (from Docs)
- No external dependencies (no Pods/SPM). One app target + one unit test target.
- Feature-based folders. `ObservableObject` + `@Published`; ViewModels and navigator are `@MainActor`.
- No AppContainer access from ViewModels/singletons/Environment; root passes services via initializers.
- Services are async + Sendable; heavy work (images, Vision, file I/O) off the main actor.
- Framework types (UIImage, ARFaceAnchor) never enter shared domain/contracts in `Core`.
- AR overlays must follow the tracked face mesh/anchor, never screen coordinates.
- Handle permission, unsupported device, session failure, interruption, tracking loss; keep manual fallback.
- Don't persist mesh or send photos anywhere. Don't add mandatory ARKit entitlements.

## Live makeup try-on: `SunriseApp/Features/MakeupTryOn`
ARKit face tracking -> Vision brow/eye points (averaged) mapped to face-mesh UV (`FaceFeatureLocator`, `FaceFeatureMap`)
-> `MakeupTextureRenderer` draws each category into its own texture -> `MakeupARView` (mesh material).
`FaceFit`/`MakeupFitter` fit styles to the face; `MakeupRecommender` is the catalog; `MakeupPlan` blends styles.
Models: `MakeupRecommendation.swift` (BrowStyle, BlushStyle, LinerStyle, MakeupPalette).

## Build / test (simulator: iPhone 17 Pro; `xcode-select` points at CommandLineTools, so set DEVELOPER_DIR)
Never read full xcodebuild logs; always use these filters.
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Build
xcodebuild -project SunriseApp.xcodeproj -scheme SunriseApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|warning:.*(Liner|Makeup)|BUILD (SUCCEEDED|FAILED)" | head -40
# Test
xcodebuild -project SunriseApp.xcodeproj -scheme SunriseApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "error:|failed|TEST (SUCCEEDED|FAILED)|Executed" | tail -40
```
List sims: `xcrun simctl list devices available | grep iPhone`.

## Git
`EyelinerSpike/` (MediaPipe prototype) is local-only, excluded via `.git/info/exclude`; never commit it. Don't push unless asked.
