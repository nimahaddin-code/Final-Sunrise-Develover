import SwiftUI

/// After the result photo: a loading state while `provider` compares the two photos (lo-fi: the photo in a green frame
/// with a percentage), then the feedback with "Back to tutorial" and "Done". The comparison itself is a placeholder
/// until the real one is plugged in through `MakeupFeedbackProviding`.
struct FeedbackView: View {
    let handoff: TutorialHandoff
    @ObservedObject var store: MakeupFlowStore
    let provider: any MakeupFeedbackProviding
    let onBackToTutorial: () -> Void
    let onDone: () -> Void
    @State private var progress = 0.0
    @State private var feedback: MakeupFeedback?

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            if let feedback { result(feedback) } else { loading }
        }
        .foregroundStyle(AppColors.snow)
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .animation(.easeInOut(duration: 0.3), value: feedback)
        .sensoryFeedback(.success, trigger: feedback != nil)
        .task {
            guard feedback == nil else { return }
            let request = MakeupFeedbackRequest(tool: handoff.tool, styleTitle: handoff.styleTitle,
                                                desired: store.desired, result: store.result)
            feedback = await provider.feedback(for: request) { value in progress = value }
        }
    }

    private var loading: some View {
        VStack(spacing: AppSpacing.medium) {
            Text("Checking your look")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, AppSpacing.small)
            ZStack {
                if let photo = store.result {
                    Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }.clipped()
                } else {
                    FlowPlaceholderBox(label: "No photo taken", symbol: "camera")
                }
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(AppColors.captionFill.opacity(0.8), in: Capsule())
                    .contentTransition(.numericText())
                    .animation(.default, value: progress)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadius, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.85), lineWidth: 8)
            }
            .frame(maxHeight: .infinity)
            Text(handoff.styleTitle).font(.title3.weight(.semibold))
            ProgressView(value: progress).tint(AppColors.flamingo)
                .padding(.bottom, AppSpacing.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your look")
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    private func result(_ feedback: MakeupFeedback) -> some View {
        VStack(spacing: AppSpacing.medium) {
            Spacer()
            HStack(spacing: AppSpacing.small) {
                photo(store.desired, label: "Desired")
                photo(store.result, label: "Yours")
            }
            .frame(height: 220)
            if let score = feedback.score {
                Text(score, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
            }
            Text(feedback.headline)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ForEach(feedback.comments, id: \.self) { comment in
                Text(comment)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.snow.opacity(0.85))
            }
            Spacer()
            HStack(spacing: AppSpacing.medium) {
                Button(action: onBackToTutorial) {
                    Text("Back to tutorial")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .glassCapsule(tint: AppColors.glassBase)
                }
                .buttonStyle(.plain)
                FlowPrimaryButton(title: "Done", action: onDone)
            }
        }
        .transition(.opacity)
    }

    private func photo(_ image: UIImage?, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            if let image {
                Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                FlowPlaceholderBox(label: "No photo", symbol: "camera")
            }
            Text(label).font(.footnote.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
