import Combine
import Foundation

@MainActor final class AppNavigator: ObservableObject {
    static let welcomeVersionKey="dandan.welcome.version"
    static let currentWelcomeVersion=2
    @Published private(set) var needsWelcome:Bool
    @Published var selectedTab: AppTab = .tryOn
    @Published var discoverPath: [AppRoute] = []
    @Published var savedPath: [AppRoute] = []
    @Published var tryOnPath: [AppRoute] = []
    private let defaults: UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        needsWelcome=defaults.integer(forKey:Self.welcomeVersionKey)<Self.currentWelcomeVersion
    }
    func dismissWelcome() {
        defaults.set(Self.currentWelcomeVersion,forKey:Self.welcomeVersionKey)
        needsWelcome=false
    }

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
