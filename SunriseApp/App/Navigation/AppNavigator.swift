import Combine
import Foundation

@MainActor final class AppNavigator: ObservableObject {
    static let onboardingCompleteKey = "onboardingComplete"

    @Published private(set) var onboardingComplete: Bool
    // -Nimah: Completed analysis survives closing the app; Retake is explicit in Profile.
    @Published private(set) var launchScanComplete=false
    /// Try On is the home tab once onboarding is done.
    @Published var selectedTab: AppTab = .tryOn
    @Published var discoverPath: [AppRoute] = []
    @Published var savedPath: [AppRoute] = []
    @Published var tryOnPath: [AppRoute] = []
    // -Nimah: Retake is presented above Profile, not a nested NavigationStack pushed inside it.
    @Published var retakePresented=false
    private var retakeSucceeded=false
    func beginRetake() { retakeSucceeded=false;retakePresented=true }
    func cancelRetake() { retakeSucceeded=false;retakePresented=false }
    func finishRetake() { retakeSucceeded=true;retakePresented=false }
    // -Nimah: Dismiss the camera cover before revealing/activating home, avoiding overlapping disappearance callbacks.
    func retakeDismissed() {
        if retakeSucceeded { retakeSucceeded=false;returnToRoot(of:.tryOn) }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Self.onboardingCompleteKey)
        launchScanComplete = onboardingComplete
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
