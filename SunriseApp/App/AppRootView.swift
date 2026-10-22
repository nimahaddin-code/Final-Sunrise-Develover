import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @StateObject private var faceShapeStore = FaceAnalysis.savedResults()

    var body: some View {
        Group {
            if navigator.launchScanComplete {
                // Try On is the only screen: no tab bar.
                NavigationStack(path: $navigator.tryOnPath) {
                    TryOnHomeView(store: faceShapeStore, assessment: studioAssessment, checker: container.faceTracking,
                                  onProfile: { navigator.open(.profile, in: .tryOn) },
                                  onTutorial: { tool,shade,intensity in
                                      // -Nimah: Launch already prepared the result; tutorial navigation never opens a scanner.
                                      switch tool {
                                      case .eyebrow,.blush:
                                          navigator.open(.recommendedTutorial(tool == .eyebrow ? .eyebrows : .blush,shade,intensity),in:.tryOn)
                                      case .eyeliner:
                                          let plan=faceShapeStore.latest.map { MakeupPlan(scan:$0,eyeScan:faceShapeStore.eyes) } ?? MakeupPlan(shape:.oval,eyeScan:faceShapeStore.eyes)
                                          if !plan.eyeliner.isNeutral { navigator.open(.makeupTryOn(plan:plan,applied:plan.madeForYou),in:.tryOn) }
                                      }
                                  })
                        .navigationDestination(for: AppRoute.self, destination: destination)
                }
            } else {
                OnboardingView(store: faceShapeStore, showWelcome:!navigator.onboardingComplete, onFinish: navigator.completeOnboarding)
            }
        }
    }

    // -Nimah: Adapt classifier output without changing Khalish's classifier or scan result model.
    private var studioAssessment:FaceShapeAssessment? {
        guard let result=faceShapeStore.latest else { return nil }
        let shape=result.shape == .triangle ? MakeupFaceShape.pear : MakeupFaceShape(rawValue:result.shape.rawValue) ?? .unknown
        return FaceShapeAssessment(shape:shape,origin:.analysis,confidence:Float(result.confidence))
    }

    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .referenceDetail(let reference): ReferenceDetailView(reference: reference)
        // -Nimah: Integration routing; teammate feature implementations remain unchanged.
        case .eyebrowGuide: EyebrowOverlayView(checker: container.faceTracking,assessment:studioAssessment)
        case .browBlush(let region): EyebrowOverlayView(checker:container.faceTracking,assessment:studioAssessment,initialRegion:region)
        case .recommendedTutorial(let region,let shade,let intensity):
            EyebrowOverlayView(checker:container.faceTracking,assessment:studioAssessment,initialRegion:region,
                               initialShade:shade,initialIntensity:intensity,startTutorial:true)
        case .referenceImport: ReferenceImportView(checker: container.faceTracking, store: container.savedLooks)
        case .session:
            // -Nimah: Old catalog/import routes cannot reopen the superseded mixed renderer.
            EyebrowOverlayView(checker:container.faceTracking,assessment:studioAssessment)
        case .savedLookDetail(let look): SavedLookDetailView(look: look, store: container.savedLooks)
        case .makeupTryOn(let plan, let applied): MakeupTryOnView(plan: plan, applied: applied)
        case .faceScan:
            FaceAnalysis.scanScreen(store: faceShapeStore) { navigator.returnToRoot(of: .tryOn) }
        // -Nimah: Profile shows launch results, without starting another scan.
        case .profile: MakeupRecommendationsView(store:faceShapeStore,allowsRescan:false,
            onScanFace:{ navigator.open(.faceScan,in:.tryOn) },onScanEyes:{ navigator.open(.eyeScan,in:.tryOn) })
        case .tutorial: BlankPageView(title: "Tutorial")
        case .eyeScan:
            EyeAnalysis.scanScreen(store: faceShapeStore, continueTitle: "Back to my makeup") { navigator.returnToRoot(of: .tryOn) }
        }
    }
}
