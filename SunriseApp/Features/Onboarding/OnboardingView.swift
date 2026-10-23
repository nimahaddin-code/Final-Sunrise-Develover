import SwiftUI

/// First launch: a short welcome, then the face shape scan, then the eye shape scan. Finishing (or skipping) leads to the
/// Try On home screen.
struct OnboardingView: View {
    private enum Step { case welcome, faceScan, eyeScan }

    @ObservedObject var store: FaceShapeStore
    var onFinish: () -> Void
    @State private var step = Step.welcome

    var body: some View {
        NavigationStack {
            switch step {
            case .welcome:
                welcome
            case .faceScan:
                FaceAnalysis.scanScreen(store: store, continueTitle: "Next: scan your eyes") { step = .eyeScan }
                    .toolbar { navigation(back: .welcome, skip: { step = .eyeScan }) }
            case .eyeScan:
                EyeAnalysis.scanScreen(store: store, continueTitle: "See my makeup", onFinish: onFinish)
                    .toolbar { navigation(back: .faceScan, skip: onFinish) }
            }
        }
    }

    /// Skip leaves only the current step, so the face scan can be skipped (or unavailable) and the eye scan still offered.
    @ToolbarContentBuilder private func navigation(back: Step, skip: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Back") { step = back }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Skip", action: skip)
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Image(systemName: "face.smiling").font(.largeTitle).foregroundStyle(AppColors.rose)
                    .accessibilityHidden(true)
                Text("Your next glow starts here").font(AppTypography.title)
                Text("First, let's find your face shape, then your eye shape. We'll use the front camera for a few seconds each, then recommend brow, blush and eyeliner styles you can try on live.")
                    .font(AppTypography.body)
                Label("Only your face and eye shape results and one small photo from each scan are kept on this device. Nothing is uploaded.",
                      systemImage: "lock")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                PrimaryButton(title: "Scan my face") { step = .faceScan }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .padding(AppSpacing.large)
        }
        .foregroundStyle(AppColors.ink)
        .background(AppColors.background)
    }
}

#Preview { OnboardingView(store: FaceShapeStore(), onFinish: {}) }
