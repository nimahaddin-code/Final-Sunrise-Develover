import SwiftUI

struct ReferenceDetailView: View {
    let reference: MakeupReference
    var body: some View {
        FeaturePlaceholderView(title: "Reference detail", symbol: "sparkle",
            explanation: "This screen will explain the chosen makeup reference. The catalog is sample data; no personalized recommendation or photo analysis is available.") {
                Text(reference.name).font(AppTypography.heading)
                Text(reference.summary)
                NavigationLink("Explore calibration placeholder", value: AppRoute.faceCalibration(referenceID: reference.id))
            }
    }
}
