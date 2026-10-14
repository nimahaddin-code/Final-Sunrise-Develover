import SwiftUI

struct LiveGuideView: View {
    let referenceID: String
    var body: some View {
        FeaturePlaceholderView(title: "Live AR guide", symbol: "viewfinder",
            explanation: "AR and the camera are not implemented. The next proof of concept will render blush on the tracked face mesh. Other makeup overlays remain out of scope.") {
                Text("No camera preview or simulated face tracking is shown.").font(AppTypography.caption)
                NavigationLink("Explore comparison placeholder", value: AppRoute.comparison(referenceID: referenceID))
            }
    }
}
