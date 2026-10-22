import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @StateObject private var faceShapeStore = FaceShapeStore(defaults: .standard)

    var body: some View {
        Group {
            if navigator.onboardingComplete {
                TabView(selection: $navigator.selectedTab) {
                    NavigationStack(path: $navigator.tryOnPath) {
                        MakeupRecommendationsView(store: faceShapeStore) { navigator.open(.faceScan, in: .tryOn) }
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }
                    .tabItem { Label("Try On", systemImage: "wand.and.stars") }
                    .tag(AppTab.tryOn)
                    NavigationStack(path: $navigator.discoverPath) {
                        ReferenceCatalogView(service: container.catalog)
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }
                    .tabItem { Label("Discover", systemImage: "sparkles") }
                    .tag(AppTab.discover)
                    NavigationStack(path: $navigator.savedPath) {
                        SavedLooksView(store: container.savedLooks)
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }
                    .tabItem { Label("My Looks", systemImage: "heart") }
                    .tag(AppTab.myLooks)
                }
            } else {
                OnboardingView(store: faceShapeStore, onFinish: navigator.completeOnboarding)
            }
        }
    }

    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .referenceDetail(let reference): ReferenceDetailView(reference: reference)
        case .referenceImport: ReferenceImportView()
        case .faceCalibration(let id): FaceCalibrationView(referenceID: id, checker: container.faceTracking)
        case .tutorial(let id): TutorialView(referenceID: id)
        case .liveGuide(let id): LiveGuideView(referenceID: id)
        case .comparison(let id):
            ComparisonView(referenceID: id) { navigator.returnToRoot(of: .discover) }
        case .savedLookDetail(let look): SavedLookDetailView(look: look)
        case .makeupTryOn(let plan, let applied): MakeupTryOnView(plan: plan, applied: applied)
        case .faceScan:
            FaceShapeView(store: faceShapeStore) { navigator.returnToRoot(of: .tryOn) }
        }
    }
}
