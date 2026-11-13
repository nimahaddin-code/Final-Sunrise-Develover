// -Nimah: Uji regresi route MVP dan pemisahan stack tab.
import XCTest
@testable import SunriseApp

final class AppNavigatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AppNavigatorTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A language picked on the home screen is used at once: by `String(localized:)`, by lists of steps, and by
    /// names kept as string resources (the eyeliner look).
    @MainActor func testChosenLanguageIsUsedAtOnce() {
        let saved = (UserDefaults.standard.object(forKey: AppLanguage.key), UserDefaults.standard.object(forKey: "AppleLanguages"))
        defer {
            AppLanguage.english.select()
            UserDefaults.standard.set(saved.0, forKey: AppLanguage.key)
            UserDefaults.standard.set(saved.1, forKey: "AppleLanguages")
        }
        AppLanguage.indonesian.select()
        XCTAssertEqual(AppLanguage.current, .indonesian)
        XCTAssertEqual(String(localized: "Start lesson"), "Mulai belajar")
        XCTAssertEqual(FeedbackLanguage.current, .id)
        AppLanguage.chinese.select()
        XCTAssertEqual(String(localized: "Start lesson"), "开始课程")
        XCTAssertEqual(FeedbackLanguage.current, .en)
        XCTAssertEqual(GuidedTutorialModel.browLessons[0].title, "梳理眉毛")
        let liner = ToolInfo.of(.eyeliner, handoff: TutorialHandoff(tool: .eyeliner, shades: [:], intensities: [:]))
        XCTAssertTrue(["经典", "猫眼", "狗狗眼", "狐狸眼", "阿拉伯式", "自然"].contains(liner.lookName), liner.lookName)
        AppLanguage.english.select()
        XCTAssertEqual(String(localized: "Start lesson"), "Start lesson")
        XCTAssertEqual(GuidedTutorialModel.browLessons[0].title, "Brush Your Brows")
    }
    @MainActor func testPreviousWelcomeRevisionMigratesOnce() {
        defaults.set(1,forKey:AppNavigator.welcomeVersionKey)
        let navigator=AppNavigator(defaults:defaults)
        XCTAssertTrue(navigator.needsWelcome)
        navigator.dismissWelcome()
        XCTAssertFalse(AppNavigator(defaults:defaults).needsWelcome)
    }
    @MainActor func testWelcomeAppearsOnceAndKeepsNavigationAtHome() {
        let navigator=AppNavigator(defaults:defaults)
        XCTAssertTrue(navigator.needsWelcome)
        navigator.dismissWelcome()
        XCTAssertFalse(navigator.needsWelcome)
        XCTAssertFalse(AppNavigator(defaults:defaults).needsWelcome)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
    }
    @MainActor func testOpensOnTryOnHomeWithoutAPath() {
        let navigator = AppNavigator()
        XCTAssertEqual(navigator.selectedTab, .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
        XCTAssertTrue(navigator.discoverPath.isEmpty)
        XCTAssertTrue(navigator.savedPath.isEmpty)
    }
    @MainActor func testOpeningTryOnForOneToolPushesThatRoute() {
        let navigator = AppNavigator()
        navigator.open(.tryOn(.blush), in: .tryOn)
        XCTAssertEqual(navigator.tryOnPath, [.tryOn(.blush)])
    }
    private func tutorial(_ tool: TryOnTool) -> AppRoute {
        .recommendedTutorial(TutorialHandoff(tool: tool, shades: [:], intensities: [:]))
    }
    @MainActor func testBackToTutorialDropsLaterScreensAndRestartsTheTutorial() {
        let navigator = AppNavigator()
        let handoff = TutorialHandoff(tool: .blush, shades: [:], intensities: [:])
        for route in [AppRoute.tryOn(.blush), .capture(.desired, handoff), .lookBrief(handoff), .recommendedTutorial(handoff),
                      .capture(.result, handoff), .feedback(handoff)] {
            navigator.open(route, in: .tryOn)
        }
        navigator.restartTutorial()
        XCTAssertEqual(navigator.tryOnPath, [.tryOn(.blush), .capture(.desired, handoff), .lookBrief(handoff),
                                             .recommendedTutorial(handoff, attempt: 1)])
        navigator.returnToRoot(of: .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
    }
    @MainActor func testRestartWithoutTutorialAndBackAtRootDoNothing() {
        let navigator = AppNavigator()
        navigator.goBack(in: .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
        navigator.open(.tryOn(.eyeliner), in: .tryOn)
        navigator.restartTutorial()
        XCTAssertEqual(navigator.tryOnPath, [.tryOn(.eyeliner)])
        navigator.goBack(in: .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
    }
    @MainActor func testFinishingDiscoverFlowPreservesSavedTabHistory() {
        let navigator = AppNavigator()
        let savedRoute = tutorial(.blush)
        navigator.open(savedRoute, in: .myLooks)
        navigator.open(tutorial(.eyebrow), in: .discover)
        navigator.open(tutorial(.eyeliner), in: .discover)
        navigator.returnToRoot(of: .discover)
        XCTAssertEqual(navigator.selectedTab, .discover)
        XCTAssertTrue(navigator.discoverPath.isEmpty)
        XCTAssertEqual(navigator.savedPath, [savedRoute])
    }
    @MainActor func testOpeningSavedDetailSelectsItsTabAndPreservesDiscoverPath() {
        let navigator = AppNavigator()
        navigator.open(tutorial(.eyebrow), in: .discover)
        let route = tutorial(.blush)
        navigator.open(route, in: .myLooks)
        XCTAssertEqual(navigator.selectedTab, .myLooks)
        XCTAssertEqual(navigator.savedPath, [route])
        XCTAssertEqual(navigator.discoverPath, [tutorial(.eyebrow)])
    }
    @MainActor func testReturningToTryOnRootSelectsTabAndClearsOnlyItsPath() {
        let navigator = AppNavigator()
        navigator.open(tutorial(.eyebrow), in: .discover)
        let route = tutorial(.blush)
        navigator.open(route, in: .tryOn)
        XCTAssertEqual(navigator.tryOnPath, [route])
        navigator.returnToRoot(of: .tryOn)
        XCTAssertEqual(navigator.selectedTab, .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
        XCTAssertEqual(navigator.discoverPath, [tutorial(.eyebrow)])
    }
}
