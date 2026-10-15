// -Nimah: TutorialView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct TutorialView: View {
    @ObservedObject var model: TutorialViewModel
    let referenceID: String
    let manual: Bool
    @Binding var overlay: Bool
    let canCapture: Bool
    var onCapture: () -> Void
    var onFinishManual: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if let step = model.currentStep {
                ProgressView(value: Double(model.stepIndex + 1), total: Double(model.tutorial.steps.count)).tint(AppColors.rose)
                Text(step.title).font(AppTypography.title)
                Text(TutorialInstructions.text(for: step, referenceID: referenceID))
                Text(step == .blush && !manual ? "LIVE AR · Approximate cheek placement" : "MANUAL GUIDE · Apply at your own pace").font(.caption).foregroundStyle(AppColors.rose)
                if step == .blush && !manual { Toggle("Show blush guide", isOn: $overlay) }
                HStack {
                    Button("Previous step") { model.previous(); overlay = model.currentStep == .blush && !manual }.disabled(!model.canGoBack)
                    Spacer()
                    if model.canGoNext { Button("Next step") { model.next(); overlay = model.currentStep == .blush && !manual } }
                }.font(.headline)
                if !model.canGoNext {
                    if manual { PrimaryButton(title: "Finish manual tutorial", action: onFinishManual) }
                    else { PrimaryButton(title: "Capture after", action: onCapture).disabled(!canCapture) }
                }
            }
        }
    }
}
