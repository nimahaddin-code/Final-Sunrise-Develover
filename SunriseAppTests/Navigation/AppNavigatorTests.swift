import XCTest
@testable import SunriseApp

final class AppNavigatorTests: XCTestCase {
    @MainActor func testOnboardingRevealsTabsWithoutCreatingAPath() {
        let navigator = AppNavigator()
        XCTAssertFalse(navigator.onboardingComplete)
        navigator.completeOnboarding()
        XCTAssertTrue(navigator.onboardingComplete)
        XCTAssertTrue(navigator.discoverPath.isEmpty)
        XCTAssertTrue(navigator.savedPath.isEmpty)
    }
    @MainActor func testFinishingDiscoverFlowPreservesSavedTabHistory() {
        let navigator = AppNavigator()
        let savedRoute = AppRoute.savedLookDetail(SampleData.savedLook)
        navigator.open(savedRoute, in: .myLooks)
        navigator.open(.faceCalibration(referenceID: "reference"), in: .discover)
        navigator.open(.tutorial(referenceID: "reference"), in: .discover)
        navigator.open(.comparison(referenceID: "reference"), in: .discover)
        navigator.returnToRoot(of: .discover)
        XCTAssertEqual(navigator.selectedTab, .discover)
        XCTAssertTrue(navigator.discoverPath.isEmpty)
        XCTAssertEqual(navigator.savedPath, [savedRoute])
    }
    @MainActor func testOpeningSavedDetailSelectsItsTabAndPreservesDiscoverPath() {
        let navigator = AppNavigator()
        navigator.open(.referenceImport, in: .discover)
        let route = AppRoute.savedLookDetail(SampleData.savedLook)
        navigator.open(route, in: .myLooks)
        XCTAssertEqual(navigator.selectedTab, .myLooks)
        XCTAssertEqual(navigator.savedPath, [route])
        XCTAssertEqual(navigator.discoverPath, [.referenceImport])
    }
}
