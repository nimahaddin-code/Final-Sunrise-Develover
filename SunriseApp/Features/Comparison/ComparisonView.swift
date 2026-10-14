import SwiftUI

struct ComparisonView: View {
    let referenceID: String
    var onFinish: () -> Void
    var body: some View {
        FeaturePlaceholderView(title: "Before and after", symbol: "rectangle.split.2x1",
            explanation: "Comparison will show actual user captures in a future milestone. There are no captures, scoring or persistence in this scaffold.") {
                Text("Reference ID: \(referenceID)").font(AppTypography.caption)
                PrimaryButton(title: "Save unavailable") {}.disabled(true)
                PrimaryButton(title: "Return to Discover", action: onFinish)
            }
    }
}
