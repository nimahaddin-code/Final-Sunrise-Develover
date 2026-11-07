import SwiftUI

/// The new way into the app (behind `NewFlow`): splash, the onboarding pages, the compact opening, then Try On.
struct EntryFlowView: View {
    let onFinish: () -> Void
    @State private var step = Step.splash

    enum Step { case splash, pages, compact }

    var body: some View {
        switch step {
        case .splash: SplashView { step = .pages }
        case .pages: OnboardingPagesView { step = .compact }
        case .compact: CompactOpeningView(onFinish: onFinish)
        }
    }
}
