import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void
    var body: some View {
        FeaturePlaceholderView(title: "Your next glow starts here", symbol: "sparkles",
            explanation: "Explore the SunriseApp project scaffold. All references and saved entries are sample data. Camera, AR, photo import and saving are not implemented. Onboarding resets when the app restarts.") {
                PrimaryButton(title: "Explore scaffold", action: onContinue)
            }
    }
}

#Preview { OnboardingView(onContinue: {}) }
