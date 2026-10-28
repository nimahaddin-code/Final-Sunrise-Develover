import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()

    var body: some View {
        // Try On is the only screen: no tab bar, onboarding or face/eye scan.
        NavigationStack(path: $navigator.tryOnPath) {
            TryOnHomeView(plan: plan, assessment: assessment, checker: container.faceTracking,
                          onTutorial: { handoff in navigator.open(.recommendedTutorial(handoff),in:.tryOn) })
                .navigationDestination(for: AppRoute.self, destination: destination)
        }
    }

    // Without an eye scan the eyeliner is the natural line.
    private let plan=MakeupPlan(shape:.oval)
    private let assessment=FaceShapeAssessment.standardLook

    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .referenceDetail(let reference): ReferenceDetailView(reference: reference)
        // -Nimah: Integration routing; teammate feature implementations remain unchanged.
        case .eyebrowGuide: EyebrowOverlayView(checker: container.faceTracking,assessment:assessment)
        case .browBlush(let region): EyebrowOverlayView(checker:container.faceTracking,assessment:assessment,initialRegion:region)
        case .recommendedTutorial(let handoff):
            GuidedTutorialView(checker:container.faceTracking,assessment:assessment,plan:plan,handoff:handoff)
        case .referenceImport: ReferenceImportView(checker: container.faceTracking, store: container.savedLooks)
        case .session:
            // -Nimah: Old catalog/import routes cannot reopen the superseded mixed renderer.
            EyebrowOverlayView(checker:container.faceTracking,assessment:assessment)
        case .savedLookDetail(let look): SavedLookDetailView(look: look, store: container.savedLooks)
        case .makeupTryOn(let plan, let applied): MakeupTryOnView(plan: plan, applied: applied)
        case .tutorial: BlankPageView(title: "Tutorial")
        }
    }
}
