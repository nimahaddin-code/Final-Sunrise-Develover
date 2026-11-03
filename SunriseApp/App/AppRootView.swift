import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()

    var body: some View {
        Group {
            if navigator.needsWelcome {
                OnboardingWelcomeScreen {navigator.dismissWelcome()}
            } else {
        // Preserve staging’s scan-free home after the one-time welcome.
        NavigationStack(path: $navigator.tryOnPath) {
            TryOnHomeView(plan: plan, assessment: assessment, checker: container.faceTracking,
                          onTutorial: { handoff in navigator.open(.recommendedTutorial(handoff),in:.tryOn) })
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
            GuidedTutorialView(checker:container.faceTracking,assessment:assessment,plan:plan,handoff:handoff)
        }
    }
}
