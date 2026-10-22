import SwiftUI

/// Entry point for the eye shape scan, next to `FaceAnalysis`. Other features should use only this and the result
/// types (`EyeShapeResult`, `EyeOpenness`, `EyeTilt`, `EyeSpacing`, `EyeLid`).
///
/// - `scanScreen(store:)`: the ready-made scan screen. It asks for nothing the face scan has not, writes the result to
///   `store.eyes`, and leaves the ARKit face session alone, so stop that first (it leaves the screen on its own).
/// - The latest result is `FaceShapeStore.eyes`, restored from the previous launch.
enum EyeAnalysis {
    @MainActor static func scanScreen(store: FaceShapeStore, continueTitle: LocalizedStringKey = "See my makeup",
                                      onFinish: @escaping () -> Void = {}) -> EyeScanView {
        EyeScanView(store: store, continueTitle: continueTitle, onFinish: onFinish)
    }
}
