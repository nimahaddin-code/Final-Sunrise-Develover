// -Nimah: AppRootView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct AppRootView: View {
    let container: AppContainer
    @StateObject private var navigator = AppNavigator()
    @AppStorage("sunrise.onboarding.complete") private var onboarded = false
    var body: some View {
        Group {
            if onboarded {
                TabView(selection: $navigator.selectedTab) {
                    NavigationStack(path: $navigator.discoverPath) {
                        ReferenceCatalogView(service: container.catalog)
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }.tabItem { Label("Discover", systemImage: "sparkles") }.tag(AppTab.discover)
                    NavigationStack(path: $navigator.savedPath) {
                        SavedLooksView(store: container.savedLooks)
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }.tabItem { Label("My Looks", systemImage: "heart") }.tag(AppTab.myLooks)
                }
            } else { OnboardingView { onboarded = true; navigator.completeOnboarding() } }
        }
        // -Nimah: Debug launch shortcut untuk membuka modul alis pada perangkat uji, tanpa merekam kamera.
        .onAppear {
            #if DEBUG
            if onboarded,ProcessInfo.processInfo.arguments.contains("--eyebrows"),navigator.discoverPath.isEmpty {
                navigator.open(.eyebrowGuide,in:.discover)
            }
            #endif
        }
    }
    @ViewBuilder private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .referenceDetail(let reference): ReferenceDetailView(reference: reference)
        case .eyebrowGuide: EyebrowOverlayView(checker:container.faceTracking)
        case .referenceImport: ReferenceImportView(checker: container.faceTracking, store: container.savedLooks)
        case .session(let reference):
            MakeupSessionView(reference: reference, checker: container.faceTracking, store: container.savedLooks) { navigator.returnToRoot(of: .discover) }
        case .savedLookDetail(let look): SavedLookDetailView(look: look, store: container.savedLooks)
        }
    }
}
