import SwiftUI

// -Nimah: Launch scan owns all classification and makeup fitting; try-on never repeats it.
struct OnboardingView: View {
    private enum Step { case welcome, faceScan, eyeScan, preparing }
    @ObservedObject var store: FaceShapeStore
    var onFinish: () -> Void
    @State private var step:Step
    @State private var started=false
    @State private var preparation:Task<Bool,Never>?
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
                    preparation?.cancel()
                    let input=FaceLandmarkFrame(frame:frame,anchor:face)
                    preparation=Task.detached(priority:.userInitiated) { LaunchMakeupFit.shared.prepare(input) }
                }) { step = .eyeScan }
            case .eyeScan:
                EyeAnalysis.scanScreen(store:store,continueTitle:"See my makeup") {
                    step = .preparing
                    Task {
                        let fitted=await preparation?.value ?? false
                        guard fitted,store.latest != nil,let eyes=store.eyes,
                              MakeupPlan(shape:.oval,eyeScan:eyes).eyeliner.isNeutral == false else {
                            preparationFailed=true;return
                        }
                        onFinish()
                    }
                }
            case .preparing:ProgressView("Preparing your recommended makeup")
            }
        }
        .onAppear { if !started { started=true;LaunchMakeupFit.shared.clear() } }
        .alert("Makeup preparation unavailable",isPresented:$preparationFailed) {
            Button("Repeat initial scan") { preparation?.cancel();LaunchMakeupFit.shared.clear();step = .faceScan }
        } message: { Text("The initial scan did not provide a usable face fit and eye result. Complete it before opening try-on.") }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Image(systemName: "face.smiling").font(.largeTitle).foregroundStyle(AppColors.rose)
                    .accessibilityHidden(true)
                Text("Your next glow starts here").font(AppTypography.title)
                Text("First, let's find your face shape, then your eye shape. We'll use the front camera for a few seconds each, then recommend brow, blush and eyeliner styles you can try on live.")
                    .font(AppTypography.body)
                Label("Only your face and eye shape results are kept on this device. No photos are saved or uploaded.",
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
