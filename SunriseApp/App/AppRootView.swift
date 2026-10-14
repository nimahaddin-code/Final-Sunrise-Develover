import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()

    var body: some View {
        Group {
            if navigator.onboardingComplete {
                TabView(selection: $navigator.selectedTab) {
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
                OnboardingView(onContinue: navigator.completeOnboarding)
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
        }
    }
}
