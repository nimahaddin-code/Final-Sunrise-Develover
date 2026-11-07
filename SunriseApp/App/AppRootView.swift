import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    /// The photos of the current run; cleared when a new feature is picked and when the flow ends.
    @StateObject private var flow = MakeupFlowStore()
    /// Splash, onboarding and the compact opening run once per launch, and only when the new flow was on at launch.
    @State private var showEntry = UserDefaults.standard.bool(forKey: NewFlow.key)

    var body: some View {
        Group {
            if showEntry {
                EntryFlowView { showEntry = false; navigator.dismissWelcome() }
            } else if navigator.needsWelcome {
                OnboardingWelcomeScreen {navigator.dismissWelcome()}
            } else {
        // One feature at a time: home -> Try On -> photo -> brief -> tutorial -> photo -> feedback -> home.
        NavigationStack(path: $navigator.tryOnPath) {
            FeatureHomeView { tool in
                flow.reset()
                navigator.open(.tryOn(tool), in: .tryOn)
            }
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
        case .tryOn(let tool):
            TryOnHomeView(plan: plan, assessment: assessment, checker: container.faceTracking, tool: tool,
                          onBack: { navigator.goBack(in: .tryOn) },
                          onContinue: { handoff in navigator.open(.capture(.desired, handoff), in: .tryOn) })
        case .capture(let stage, let handoff):
            FeatureCaptureView(stage: stage, handoff: handoff, plan: plan, assessment: assessment, checker: container.faceTracking,
                               store: flow, onBack: { navigator.goBack(in: .tryOn) }, onNext: {
                navigator.open(stage == .desired ? .lookBrief(handoff) : .feedback(handoff), in: .tryOn)
            })
        case .lookBrief(let handoff):
            LookBriefView(handoff: handoff, photo: flow.desired, onBack: { navigator.goBack(in: .tryOn) },
                          onStart: { navigator.open(.recommendedTutorial(handoff), in: .tryOn) })
        case .recommendedTutorial(let handoff, _):
            GuidedTutorialView(checker:container.faceTracking,assessment:assessment,plan:plan,handoff:handoff,
                               onFinished: { navigator.open(.capture(.result, handoff), in: .tryOn) })
        case .feedback(let handoff):
            FeedbackView(handoff: handoff, store: flow, provider: container.feedback,
                         onBackToTutorial: {
                             flow.result = nil
                             navigator.restartTutorial()
                         },
                         onDone: {
                             flow.reset()
                             navigator.returnToRoot(of: .tryOn)
                         })
        }
    }
}
