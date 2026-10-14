import SwiftUI

struct SavedLookDetailView: View {
    let look: SavedLookMetadata
    var body: some View {
        FeaturePlaceholderView(title: "Saved look detail", symbol: "heart.text.square",
            explanation: "This is sample metadata to demonstrate navigation. It is not a captured or persisted user result. No images have been saved.") {
                Text("Sample ID: \(look.id)").font(AppTypography.caption)
                Text("Reference ID: \(look.referenceID)").font(AppTypography.caption)
                Text(look.createdAt, style: .date).font(AppTypography.caption)
            }
    }
}
