import SwiftUI

/// Splash: the dandan logo, then onboarding. Placeholder until it is designed.
struct SplashView: View {
    let onFinish: () -> Void

    var body: some View {
        FlowPlaceholder(title: "Splash", owner: "Khalish", note: "The dandan logo, then onboarding.",
                        buttonTitle: "Next", action: onFinish)
    }
}
