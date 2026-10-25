import SwiftUI

// -Nimah: Launch scan owns all classification and makeup fitting; try-on never repeats it.
struct OnboardingView: View {
    private enum Step { case welcome, faceScan, eyeScan, preparing }
    @ObservedObject var store: FaceShapeStore
    var onFinish: () -> Void
    @State private var step:Step
    @State private var started=false
    @StateObject private var preparation=LaunchFitPreparation()
    @State private var preparationFailed=false

    // -Nimah: Repeat analysis on launch, with welcome shown only on the first launch.
    init(store:FaceShapeStore,showWelcome:Bool = true,onFinish:@escaping ()->Void) {
        self.store=store;self.onFinish=onFinish;_step=State(initialValue:showWelcome ? .welcome : .faceScan)
    }
    var body: some View {
        NavigationStack {
            switch step {
            case .welcome:welcome
            case .faceScan:
                FaceAnalysis.scanScreen(store:store,continueTitle:"Next: scan your eyes",onScanFrame:{ frame,face in
                    // -Nimah: Compute brow/cheek attachments here, while the launch scan is still visible.
                    preparation.submit(FaceLandmarkFrame(frame:frame,anchor:face))
                }) { step = .eyeScan }
            case .eyeScan:
                EyeAnalysis.scanScreen(store:store,continueTitle:"See my makeup") {
                    step = .preparing
                    Task {
                        let fitted=await preparation.finish()
                        // -Nimah: A neutral eye recommendation is a valid fallback, not a failed face scan.
                        guard fitted,store.latest != nil,store.eyes != nil else {
                            preparationFailed=true;return
                        }
                        onFinish()
                    }
                }
            case .preparing:ProgressView("Preparing your recommended makeup")
            }
        }
        .onAppear { if !started { started=true;LaunchMakeupFit.shared.clear() } }
        .alert("Brow fitting unavailable",isPresented:$preparationFailed) {
            Button("Continue with available makeup") { onFinish() }
            Button("Repeat initial scan") { LaunchMakeupFit.shared.clear();step = .faceScan }
        } message: { Text("Brow contours could not be fitted from the initial scan. Your face and eye results are retained. You can continue with available makeup.") }
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
