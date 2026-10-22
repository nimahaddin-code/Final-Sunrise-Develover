import SwiftUI

struct FaceShapeResultView: View {
    let result: FaceShapeResult
    var onScanAgain: () -> Void
    var onShowMakeup: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                summaryCard
                card(title: "Blush tip") { Text(result.shape.blushTip).font(AppTypography.body) }
                card(title: "Closest matches") {
                    ForEach(result.rankedShapes.prefix(3), id: \.shape) { match in
                        VStack(alignment: .leading, spacing: AppSpacing.small) {
                            HStack {
                                Label { Text(match.shape.title) } icon: { Image(systemName: match.shape.symbol) }
                                Spacer()
                                Text(match.score, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            ProgressView(value: match.score).tint(AppColors.rose)
                        }
                    }
                }
                Text("An estimate from ARKit's face mesh, not a professional assessment. Only the face shape result is kept on this device; no photos are saved or uploaded.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                if let onShowMakeup {
                    PrimaryButton(title: "Try on recommended makeup", action: onShowMakeup)
                    Button("Scan again", action: onScanAgain)
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    PrimaryButton(title: "Scan again", action: onScanAgain)
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Image(systemName: result.shape.symbol).font(.largeTitle).foregroundStyle(AppColors.rose)
                .accessibilityHidden(true)
            Text("Your face shape").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            Text(result.shape.title).font(AppTypography.title)
            Text(result.shape.summary).font(AppTypography.body)
            Text("Also close to \(Text(result.runnerUp.title)).")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }

    private func card<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(title).font(AppTypography.heading)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
    }
}

#Preview {
    let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
    return FaceShapeResultView(result: classifier.classify(FaceProportions(length: 1.2, forehead: 0.89, jaw: 0.76, chin: 0.47)),
                               onScanAgain: {})
}
