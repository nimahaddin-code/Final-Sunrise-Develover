// -Nimah: FaceCalibrationView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct FaceCalibrationView: View {
    let calibrated: Bool
    let tracked: Bool
    var onCapture: () -> Void
    var onManual: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text("Let's find your face").font(AppTypography.title)
            Text("Face the camera in even light at arm's length. Hold still for two seconds. Calibration checks tracking stability, not your face shape.")
            PrimaryButton(title: calibrated ? "Capture before & begin" : "Hold still to calibrate", action: onCapture).disabled(!calibrated || !tracked)
            Button("Continue with manual tutorial", action: onManual)
        }
    }
}
