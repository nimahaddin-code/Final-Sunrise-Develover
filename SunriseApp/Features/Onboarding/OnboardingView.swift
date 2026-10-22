// -Nimah: OnboardingView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.large) {
                Text("SUNRISE").font(.caption.weight(.semibold)).tracking(5)
                LookArtwork(referenceID: "douyin")
                Text("Your face. Your kind of glow.").font(AppTypography.title).multilineTextAlignment(.center)
                Text("Choose a look you love. Learn one step at a time, with a live blush guide on your own face.").multilineTextAlignment(.center)
                Text("MVP · Try virtual makeup with placement points. Preview colors are a simulation. Camera photos stay on this device.").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                PrimaryButton(title: "Find my glow", action: onContinue)
            }.padding(AppSpacing.large)
        }.background(AppColors.background).foregroundStyle(AppColors.ink)
    }
}
#Preview { OnboardingView(onContinue: {}) }
