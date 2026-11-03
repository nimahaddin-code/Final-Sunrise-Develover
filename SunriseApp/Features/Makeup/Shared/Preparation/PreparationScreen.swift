import SwiftUI

/// The preparation page as a step of the new flow: the existing "get you ready" page, with Back going to the comparison.
/// What to have ready per tool is in `ToolInfo.chosen(in:)`, for when the page is redesigned.
struct PreparationScreen: View {
    let handoff: TutorialHandoff
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TutorialPrepView(onBack: { dismiss() }, onStart: onStart)
    }
}
