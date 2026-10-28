import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @StateObject private var faceShapeStore = FaceAnalysis.savedResults()

    var body: some View {
        // Try On is the only screen: no tab bar, no launch scan.
        NavigationStack(path: $navigator.tryOnPath) {
            TryOnHomeView(store: faceShapeStore, assessment: studioAssessment, checker: container.faceTracking,
                          onProfile: { navigator.open(.profile, in: .tryOn) },
                          onTutorial: { handoff in
                              // Eyeliner without a clear eye scan still opens the tutorial with the natural line.
                              navigator.open(.recommendedTutorial(handoff),in:.tryOn)
                          })
                .navigationDestination(for: AppRoute.self, destination: destination)
        }
    }

    private var tutorialPlan:MakeupPlan {
        faceShapeStore.latest.map { MakeupPlan(scan:$0,eyeScan:faceShapeStore.eyes) } ?? MakeupPlan(shape:.oval,eyeScan:faceShapeStore.eyes)
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
        case .recommendedTutorial(let handoff):
            GuidedTutorialView(checker:container.faceTracking,assessment:studioAssessment,plan:tutorialPlan,handoff:handoff)
        case .referenceImport: ReferenceImportView(checker: container.faceTracking, store: container.savedLooks)
        case .session:
            // -Nimah: Old catalog/import routes cannot reopen the superseded mixed renderer.
            EyebrowOverlayView(checker:container.faceTracking,assessment:studioAssessment)
        case .savedLookDetail(let look): SavedLookDetailView(look: look, store: container.savedLooks)
        case .makeupTryOn(let plan, let applied): MakeupTryOnView(plan: plan, applied: applied)
        case .profile: ProfileView(store:faceShapeStore,onTry:{ navigator.returnToRoot(of:.tryOn) })
        case .tutorial: BlankPageView(title: "Tutorial")
        }
    }
}
