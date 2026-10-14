import Combine

@MainActor final class AppNavigator: ObservableObject {
    @Published private(set) var onboardingComplete = false
    @Published var selectedTab: AppTab = .discover
    @Published var discoverPath: [AppRoute] = []
    @Published var savedPath: [AppRoute] = []

    func completeOnboarding() { onboardingComplete = true }

    func open(_ route: AppRoute, in tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.append(route)
        case .myLooks: savedPath.append(route)
        }
    }

    func returnToRoot(of tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.removeAll()
        case .myLooks: savedPath.removeAll()
        }
    }
}
