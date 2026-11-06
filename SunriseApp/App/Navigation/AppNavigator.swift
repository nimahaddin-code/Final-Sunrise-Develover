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

    /// The flow's own back buttons (the navigation bar is hidden).
    func goBack(in tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: if !discoverPath.isEmpty { discoverPath.removeLast() }
        case .myLooks: if !savedPath.isEmpty { savedPath.removeLast() }
        case .tryOn: if !tryOnPath.isEmpty { tryOnPath.removeLast() }
        }
    }

    /// Feedback's "Back to tutorial": drops the screens after the tutorial and starts it again from its first step
    /// (a new `attempt` is a new screen). Does nothing when no tutorial is open.
    func restartTutorial() {
        guard let index = tryOnPath.lastIndex(where: { if case .recommendedTutorial = $0 { true } else { false } }),
              case .recommendedTutorial(let handoff, let attempt) = tryOnPath[index] else { return }
        tryOnPath = Array(tryOnPath[..<index]) + [.recommendedTutorial(handoff, attempt: attempt + 1)]
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
