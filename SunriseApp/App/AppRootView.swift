import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    /// The guided flow being built; off by default (see `NewFlow`).
    @AppStorage(NewFlow.key) private var newFlow = false
    /// Splash, onboarding and the compact opening run once per launch, and only when the new flow was on at launch.
    @State private var showEntry = UserDefaults.standard.bool(forKey: NewFlow.key)

    var body: some View {
        Group {
            if showEntry {
                EntryFlowView { showEntry = false; navigator.dismissWelcome() }
            } else if navigator.needsWelcome {
                OnboardingWelcomeScreen {navigator.dismissWelcome()}
            } else {
        // Preserve staging’s scan-free home after the one-time welcome.
        NavigationStack(path: $navigator.tryOnPath) {
            TryOnHomeView(plan: plan, assessment: assessment, checker: container.faceTracking,
                          onTutorial: { handoff in
                              navigator.open(newFlow ? .comparison(handoff) : .recommendedTutorial(handoff), in: .tryOn)
                          })
                .navigationDestination(for: AppRoute.self, destination: destination)
            }
        }
        }
    }

    // Without an eye scan the eyeliner is the natural line.
    private let plan=MakeupPlan(shape:.oval)
    private let assessment=FaceShapeAssessment.standardLook

    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .recommendedTutorial(let handoff):
            GuidedTutorialView(checker:container.faceTracking,assessment:assessment,plan:plan,handoff:handoff,
                               onFinish: newFlow ? { result in
                                   navigator.open(.feedback(FeedbackInput(handoff: handoff, result: result)), in: .tryOn)
                               } : nil)
        case .comparison(let handoff):
            ComparisonView(handoff: handoff) { navigator.open(.preparation(handoff), in: .tryOn) }
        case .preparation(let handoff):
            PreparationScreen(handoff: handoff) { navigator.open(.recommendedTutorial(handoff), in: .tryOn) }
        case .feedback(let input):
            FeedbackView(input: input) { navigator.returnToRoot(of: .tryOn) }
        }
    }
}
