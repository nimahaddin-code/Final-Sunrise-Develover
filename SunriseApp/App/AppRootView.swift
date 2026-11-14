import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    /// The photos of the current run; cleared when a new feature is picked and when the flow ends.
    @StateObject private var flow = MakeupFlowStore()
    /// Splash, onboarding and the compact opening run once per launch, and only when the new flow was on at launch.
    @State private var showEntry = UserDefaults.standard.bool(forKey: NewFlow.key)
    /// Changed by the language button on the home screen.
    @AppStorage(AppLanguage.key) private var language = AppLanguage.current

    var body: some View {
        Group {
            if showEntry {
                EntryFlowView { showEntry = false; navigator.dismissWelcome() }
            } else if navigator.needsWelcome {
                OnboardingWelcomeScreen {navigator.dismissWelcome()}
            } else {
        // One feature at a time: home -> Try On -> photo -> brief -> tutorial -> photo -> feedback -> home.
        NavigationStack(path: $navigator.tryOnPath) {
            FeatureHomeView(onSelect: { tool in
                flow.reset()
                navigator.open(.tryOn(tool), in: .tryOn)
            }, looks: container.myLooks, onOpenLook: { id in navigator.open(.myLook(id), in: .tryOn) },
               onOpenMyLooks: { navigator.open(.myLooks, in: .tryOn) })
                .navigationDestination(for: AppRoute.self, destination: destination)
            }
            // Hands are busy with makeup: the screen stays on from Try On to feedback; home lets it sleep again.
            .onChange(of: navigator.tryOnPath.isEmpty, initial: true) { _, atHome in
                UIApplication.shared.isIdleTimerDisabled = !atHome
            }
        }
        }
        .environment(\.locale, language.locale)
    }

    // Without an eye scan the eyeliner is the natural line.
    private let plan=MakeupPlan(shape:.oval)
    private let assessment=FaceShapeAssessment.standardLook

    /// -Nimah: "Try again" from My Looks. With the look's saved expected photo and measured target it goes straight to the
    /// tutorial, and the next feedback is scored against that same target (and updates the same look). Without them (a
    /// look saved before targets were kept, or no photo) it starts again from Try On with the look's tool.
    private func retry(_ look: MyLook, expected: UIImage?, target: FaceScan?) {
        guard let handoff = MyLookFeedback.handoff(for: look) else { return }
        flow.reset()
        if let expected, let target, !look.photosCropped {
            flow.desired = expected
            flow.desiredScan = target
            navigator.returnToRoot(of: .tryOn)
            navigator.open(.recommendedTutorial(handoff), in: .tryOn)
        } else {
            navigator.returnToRoot(of: .tryOn)
            navigator.open(.tryOn(handoff.tool), in: .tryOn)
        }
    }

    /// "Redo This Look" on the My Looks page: the same as Try again from the look's detail.
    private func redo(_ id: UUID) async {
        let store = container.myLooks
        guard let look = await store.get(id) else { return }
        let expected = await store.photo(look, .expected).flatMap(UIImage.init(data:))
        let target = await store.target(look)
        retry(look, expected: expected, target: target)
    }

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
            FeedbackView(handoff: handoff, store: flow, provider: container.feedback, looks: container.myLooks,
                         onBackToTutorial: {
                             flow.result = nil
                             navigator.restartTutorial()
                         },
                         onDone: {
                             flow.reset()
                             navigator.returnToRoot(of: .tryOn)
                         })
        case .myLook(let id):
            MyLookDetailView(id: id, store: container.myLooks, onRetry: { look, expected, target in
                retry(look, expected: expected, target: target)
            }, onDeleted: { navigator.goBack(in: .tryOn) }, onBack: { navigator.goBack(in: .tryOn) })
        case .myLooks:
            MyLooksPage(store: container.myLooks, onBack: { navigator.goBack(in: .tryOn) },
                        onOpen: { id in navigator.open(.myLook(id), in: .tryOn) },
                        onRedo: { id in Task { await redo(id) } },
                        onFindLook: { navigator.returnToRoot(of: .tryOn) })
        }
    }
}
