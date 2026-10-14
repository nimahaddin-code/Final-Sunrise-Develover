import SwiftUI

struct FaceCalibrationView: View {
    let referenceID: String
    @StateObject private var model: FaceCalibrationViewModel
    init(referenceID: String, checker: any FaceTrackingAvailabilityChecking) {
        self.referenceID = referenceID
        _model = StateObject(wrappedValue: FaceCalibrationViewModel(checker: checker))
    }
    var body: some View {
        FeaturePlaceholderView(title: "Face calibration", symbol: "faceid",
            explanation: "Calibration is not implemented. No camera is running and no face has been detected. This screen only demonstrates a future integration point.") {
                switch model.availability {
                case .notChecked: Text("Device support has not been checked. Mock service only.")
                case .supported: Text("Injected support result: supported. This does not mean a camera session is active.")
                case .unsupported(let reason): Text("Injected support result: unsupported. \(reason)")
                }
                NavigationLink("Skip calibration and explore tutorial scaffold", value: AppRoute.tutorial(referenceID: referenceID))
            }.task { await model.loadAvailability() }
    }
}
