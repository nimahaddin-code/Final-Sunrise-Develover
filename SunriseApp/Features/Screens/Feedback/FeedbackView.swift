import SwiftUI

/// What the feedback screen gets: what was chosen on Try On (with its look photo) and the photo taken after the tutorial.
/// Held in memory only, like every photo in the app.
struct FeedbackInput: Hashable {
    let handoff: TutorialHandoff
    let result: UIImage
}

/// After the tutorial's photo: the look photo beside the result, then feedback per tool. Placeholder until it is designed.
struct FeedbackView: View {
    let input: FeedbackInput
    let onDone: () -> Void

    var body: some View {
        FlowPlaceholder(title: "Feedback", owner: "Nimah",
                        note: "The look photo beside the result, then tips for each tool.",
                        buttonTitle: "Done", action: onDone) {
            HStack(spacing: AppSpacing.small) {
                LookPhoto(image: input.handoff.lookPhoto, empty: "No look photo yet")
                LookPhoto(image: input.result, empty: "")
            }
            ForEach(ToolInfo.chosen(in: input.handoff)) { info in
                Text(verbatim: "\(info.lookName): feedback to come").font(.subheadline)
            }
        }
    }
}
