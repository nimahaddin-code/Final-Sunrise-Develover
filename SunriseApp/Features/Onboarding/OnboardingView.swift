import SwiftUI

/// First launch: a short welcome, then the face shape scan. Seeing the result leads to the Try On home screen.
struct OnboardingView: View {
    @ObservedObject var store: FaceShapeStore
    var onFinish: () -> Void
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            if isScanning {
                FaceShapeView(store: store, onShowMakeup: onFinish)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { isScanning = false }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Skip", action: onFinish)
                        }
                    }
            } else {
                welcome
            }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Image(systemName: "face.smiling").font(.largeTitle).foregroundStyle(AppColors.rose)
                    .accessibilityHidden(true)
                Text("Your next glow starts here").font(AppTypography.title)
                Text("First, let's find your face shape. We'll use the front camera to scan your face for a few seconds, then recommend brow, blush and eyeliner styles you can try on live.")
                    .font(AppTypography.body)
                Label("Only your face shape result is kept on this device. No photos are saved or uploaded.",
                      systemImage: "lock")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                PrimaryButton(title: "Scan my face") { isScanning = true }
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
