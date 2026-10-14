import SwiftUI

struct ReferenceImportView: View {
    var body: some View {
        FeaturePlaceholderView(title: "Reference import", symbol: "photo.on.rectangle",
            explanation: "Photos import will be implemented here. No photo library is opened, no image is imported, and automatic makeup analysis is not planned for this milestone.") {
                Text("Future integration: system PhotosPicker, image preview and import error handling.").font(AppTypography.caption)
            }
    }
}
