// -Nimah: ReferenceDetailView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct ReferenceDetailView: View {
    let reference: MakeupReference
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: AppSpacing.large) {
            LookArtwork(referenceID: reference.id)
            Text(reference.name).font(AppTypography.title)
            Text(reference.summary).foregroundStyle(AppColors.subtle)
            Text("YOUR FIVE-STEP RITUAL").font(.caption.weight(.semibold)).tracking(2)
            ForEach(TutorialStep.allCases) { step in HStack {
                Text(step.title); Spacer()
                Text(step == .blush ? "Live AR guide" : "Manual guide").font(.caption).foregroundStyle(AppColors.rose)
            } }
            NavigationLink(value: AppRoute.session(reference)) {
                Text("Start my tutorial").font(.headline).frame(maxWidth: .infinity).padding().background(AppColors.rose, in: Capsule()).foregroundStyle(.white)
            }
            Text("AR is available on supported iPhones. Manual tutorials work on every device. Placement is an approximate guide, not automatic face-shape analysis.").font(.caption).foregroundStyle(AppColors.subtle)
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("The look").navigationBarTitleDisplayMode(.inline)
    }
}
