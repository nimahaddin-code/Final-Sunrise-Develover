// -Nimah: TutorialView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct TutorialView: View {
    @ObservedObject var model: TutorialViewModel
    let referenceID: String
    let manual: Bool
    @Binding var overlay: Bool
    @Binding var guideStep: TutorialStep
    @Binding var previewMode: MakeupPreviewMode
    @Binding var previewFullLook: Bool
    @Binding var previewStrength: Float
    // -Nimah: Scope tutorial dan fine adjustment hanya untuk eyeliner yang sedang diperbaiki.
    @Binding var showPreviousSteps: Bool
    @Binding var eyelinerStyle: EyelinerStyle
    let canCapture: Bool
    var onCapture: () -> Void
    var onFinishManual: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            if let step = model.currentStep {
                ProgressView(value: Double(model.stepIndex + 1), total: Double(model.tutorial.steps.count)).tint(AppColors.rose)
                Text(step.title).font(AppTypography.title)
                Text(TutorialInstructions.text(for: step, referenceID: referenceID))
                Text(!manual && (referenceID == "sculpted-glam" || step == .blush) ? "LIVE GUIDE · Approximate placement, adjust to your features" : "MANUAL GUIDE · Apply at your own pace").font(.caption).foregroundStyle(AppColors.rose)
                if !manual && (referenceID == "sculpted-glam" || step == .blush) {
                    Toggle("Enable live overlay", isOn: $overlay)
                    Picker("Preview view", selection: $previewMode) {
                        ForEach(MakeupPreviewMode.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                    if referenceID == "sculpted-glam" {
                        Toggle("Full look preview · experimental", isOn: $previewFullLook)
                            .onChange(of:previewFullLook) { _, full in if full { showPreviousSteps=false } }
                        Toggle("Show previous steps", isOn: $showPreviousSteps)
                            .onChange(of:showPreviousSteps) { _, previous in if previous { previewFullLook=false } }
                        Text(previewFullLook ? "Full look preview · all layers" : "Tutorial · \(step.title)\(showPreviousSteps ? " + previous steps" : " only")")
                            .font(.caption).foregroundStyle(AppColors.rose)
                    }
                    if step == .eyeliner && referenceID == "sculpted-glam" {
                        DisclosureGroup("Adjust eyeliner") {
                            Text("Wing length · relative to eye width").font(.caption)
                            Slider(value:$eyelinerStyle.wingLength,in:0...0.3).accessibilityLabel("Wing length")
                            Text("Wing angle · \(Int(eyelinerStyle.wingAngle))°").font(.caption)
                            Slider(value:$eyelinerStyle.wingAngle,in:0...35).accessibilityLabel("Wing angle")
                            Text("Line thickness").font(.caption)
                            Slider(value:$eyelinerStyle.thickness,in:0.015...0.065).accessibilityLabel("Eyeliner thickness")
                            Button("Reset eyeliner") { eyelinerStyle=EyelinerStyle() }
                            Text("Surface approximation · adjust style only after checking alignment. Eyeliner is hidden on a blinking eye.").font(.caption).foregroundStyle(AppColors.subtle)
                        }
                    }
                    if previewMode.showsMakeup {
                        Text("Makeup intensity").font(.subheadline)
                        Slider(value: $previewStrength, in: 0...1).accessibilityLabel("Virtual makeup intensity")
                    }
                    Text("Virtual color preview · not a prediction of the final physical result. Camera captures stay unfiltered.").font(.caption).foregroundStyle(AppColors.subtle)
                }
                HStack {
                    Button("Previous step") { model.previous(); syncGuide() }.disabled(!model.canGoBack)
                    Spacer()
                    if model.canGoNext { Button("Next step") { model.next(); syncGuide() } }
                }.font(.headline)
                if !model.canGoNext {
                    if manual { PrimaryButton(title: "Finish manual tutorial", action: onFinishManual) }
                    else { PrimaryButton(title: "Capture after", action: onCapture).disabled(!canCapture) }
                }
            }
        }
    }
    // -Nimah: Glam memiliki titik semua tahap; look lain mempertahankan cakupan blush awal.
    private func syncGuide() {
        previewFullLook=false; showPreviousSteps=false
        guideStep = model.currentStep ?? .blush
        overlay = !manual && (referenceID == "sculpted-glam" || guideStep == .blush)
    }

}
