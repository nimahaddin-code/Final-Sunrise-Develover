import Combine
import Foundation

@MainActor final class AppNavigator: ObservableObject {
    static let onboardingCompleteKey = "onboardingComplete"

    @Published private(set) var onboardingComplete: Bool
    // -Nimah: Welcome is remembered, but every cold launch requires fresh face/eye analysis.
    @Published private(set) var launchScanComplete=false
    /// Try On is the home tab once onboarding is done.
    @Published var selectedTab: AppTab = .tryOn
    @Published var discoverPath: [AppRoute] = []
    @Published var savedPath: [AppRoute] = []
    @Published var tryOnPath: [AppRoute] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Self.onboardingCompleteKey)
    }

    /// Ends onboarding for good and lands on the Try On home screen.
    func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingCompleteKey)
        selectedTab = .tryOn
        onboardingComplete = true
        launchScanComplete = true
    }

    func open(_ route: AppRoute, in tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.append(route)
        case .myLooks: savedPath.append(route)
        case .tryOn: tryOnPath.append(route)
        case .scanDebug: break  // a single screen with no routes
        }
    }

    func returnToRoot(of tab: AppTab) {
        selectedTab = tab
        switch tab {
        case .discover: discoverPath.removeAll()
        case .myLooks: savedPath.removeAll()
        case .tryOn: tryOnPath.removeAll()
        case .scanDebug: break
        }
    }
}
