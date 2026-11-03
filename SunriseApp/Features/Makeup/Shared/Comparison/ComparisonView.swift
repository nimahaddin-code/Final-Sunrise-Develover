import SwiftUI

/// After Try On: the photo of the chosen look and what was chosen for each tool, then on to preparation.
/// Placeholder until it is designed; the look names and descriptions come from each tool's `ToolInfo`.
struct ComparisonView: View {
    let handoff: TutorialHandoff
    let onNext: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FlowPlaceholder(title: "Comparison", owner: "Hanum",
                        note: "The photo taken on Try On and the look chosen for each tool.",
                        buttonTitle: "Next", action: onNext, onBack: { dismiss() }) {
            LookPhoto(image: handoff.lookPhoto, empty: "No look photo yet: the Try On photo button is still to come.")
            ForEach(ToolInfo.chosen(in: handoff)) { info in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: info.lookName).font(.headline)
                    Text(verbatim: info.lookDescription).font(.subheadline).foregroundStyle(AppColors.snow.opacity(0.8))
                }
            }
        }
    }
}

/// A photo from the flow, or a grey box saying why there is none yet.
struct LookPhoto: View {
    let image: UIImage?
    let empty: String

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(verbatim: empty).font(.footnote).multilineTextAlignment(.center).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.snow.opacity(0.12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
