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
        // -Nimah: Integration routing; teammate feature implementations remain unchanged.
        case .eyebrowGuide: EyebrowOverlayView(checker: container.faceTracking)
        case .referenceImport: ReferenceImportView(checker: container.faceTracking, store: container.savedLooks)
        case .session(let reference):
            MakeupSessionView(reference: reference, checker: container.faceTracking, store: container.savedLooks) { navigator.returnToRoot(of: .discover) }
        case .savedLookDetail(let look): SavedLookDetailView(look: look, store: container.savedLooks)
        case .makeupTryOn(let plan, let applied): MakeupTryOnView(plan: plan, applied: applied)
        case .faceScan:
            FaceShapeView(store: faceShapeStore) { navigator.returnToRoot(of: .tryOn) }
        }
    }
}
