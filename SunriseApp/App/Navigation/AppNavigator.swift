import Combine
import Foundation

@MainActor final class AppNavigator: ObservableObject {
    /// Try On is the home screen; the app opens on it with no onboarding or scan.
    @Published var selectedTab: AppTab = .tryOn
    @Published var discoverPath: [AppRoute] = []
    @Published var savedPath: [AppRoute] = []
    @Published var tryOnPath: [AppRoute] = []

    func open(_ route: AppRoute, in tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.append(route)
        case .myLooks: savedPath.append(route)
        case .tryOn: tryOnPath.append(route)
        }
    }

    func returnToRoot(of tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.removeAll()
        case .myLooks: savedPath.removeAll()
        case .tryOn: tryOnPath.removeAll()
        }
    }
}
