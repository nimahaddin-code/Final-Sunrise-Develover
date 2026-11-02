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
            Text("Face the camera straight on in even light. Relax your eyes and lips, then hold still while the mesh is fitted. Move closer or farther naturally; the overlay follows the tracked 3D surface.")
            PrimaryButton(title: calibrated ? "Capture before & begin" : "Hold still to calibrate", action: onCapture).disabled(!calibrated || !tracked)
            Button("Continue with manual tutorial", action: onManual)
        }
    }
}
