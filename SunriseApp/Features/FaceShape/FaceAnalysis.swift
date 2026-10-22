import ARKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Entry point for face shape analysis. Other features should use only what is here, plus the result types
/// `FaceShape` and `FaceShapeResult`, instead of calling the measurers or the classifier directly.
///
/// - Live scan (TrueDepth iPhones): `scanScreen(store:onFinish:)` for the ready-made screen, or `makeLiveScanner()`
///   to drive a custom UI from its `phase`.
/// - Single photo (any device): `faceShape(in:orientation:)`.
/// - Last result, kept on device: `savedResults()`.
///
/// Everything else in this folder (mesh/contour measuring, classifier prototypes, head pose limits) is internal
/// tuning; change it here in the FaceShape feature, not from callers. Only the classified result is ever kept;
/// no photos or meshes are saved or uploaded.
enum FaceAnalysis {
    typealias PhotoFailure = PhotoFaceMeasurer.Failure

    /// Whether this device can run the live scan. Photos work on every device.
    static var isLiveScanSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    /// The live scan screen. It handles camera permission, guidance and the result sheet, and writes the result
    /// to `store`. `onFinish` runs when the person taps the result's main button, labelled `continueTitle`.
    @MainActor static func scanScreen(store: FaceShapeStore, continueTitle: LocalizedStringKey = "Try on recommended makeup",
                                      onFinish: @escaping () -> Void = {}) -> FaceShapeView {
        FaceShapeView(store: store, onShowMakeup: onFinish, continueTitle: continueTitle)
    }

    /// The live scan without UI. Show `session` in an AR view, call `start()`, and read `phase` for progress,
    /// guidance and the finished result. Call `stop()` when the screen goes away.
    @MainActor static func makeLiveScanner() -> FaceShapeViewModel { FaceShapeViewModel() }

    /// Classifies the largest face in a photo. Vision runs off the main actor. The face should look straight
    /// at the camera; a turned head fails with `.turnedAway`.
    static func faceShape(in image: CGImage, orientation: CGImagePropertyOrientation = .up) async -> Result<FaceShapeResult, PhotoFailure> {
        await Task.detached(priority: .userInitiated) {
            PhotoFaceMeasurer.proportions(of: image, orientation: orientation).map(FaceShapeClassifier.photo.classify)
        }.value
    }

    /// The latest result, restored from the previous launch. Use `FaceShapeStore(latest:)` for previews and tests.
    @MainActor static func savedResults(defaults: UserDefaults = .standard) -> FaceShapeStore {
        FaceShapeStore(defaults: defaults)
    }
}
