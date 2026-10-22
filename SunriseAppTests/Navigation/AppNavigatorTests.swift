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

    @MainActor func testOnboardingLandsOnTryOnHomeWithoutCreatingAPath() {
        let navigator = AppNavigator(defaults: defaults)
        navigator.selectedTab = .discover
        XCTAssertFalse(navigator.onboardingComplete)
        navigator.completeOnboarding()
        XCTAssertTrue(navigator.onboardingComplete)
        XCTAssertEqual(navigator.selectedTab, .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
        XCTAssertTrue(navigator.discoverPath.isEmpty)
        XCTAssertTrue(navigator.savedPath.isEmpty)
    }
    @MainActor func testCompletedOnboardingIsRememberedAcrossLaunches() {
        AppNavigator(defaults: defaults).completeOnboarding()
        let relaunched = AppNavigator(defaults: defaults)
        XCTAssertTrue(relaunched.onboardingComplete)
        XCTAssertEqual(relaunched.selectedTab, .tryOn)
    }
    @MainActor func testFinishingDiscoverFlowPreservesSavedTabHistory() {
        let navigator = AppNavigator(defaults: defaults)
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
        let navigator = AppNavigator(defaults: defaults)
        navigator.open(.referenceImport, in: .discover)
        let route = AppRoute.savedLookDetail(SampleData.savedLook)
        navigator.open(route, in: .myLooks)
        XCTAssertEqual(navigator.selectedTab, .myLooks)
        XCTAssertEqual(navigator.savedPath, [route])
        XCTAssertEqual(navigator.discoverPath, [.referenceImport])
    }
    @MainActor func testReturningToTryOnRootSelectsTabAndClearsOnlyItsPath() {
        let navigator = AppNavigator(defaults: defaults)
        navigator.open(.referenceImport, in: .discover)
        let plan = MakeupPlan(shape: .oval)
        let route = AppRoute.makeupTryOn(plan: plan, applied: plan.madeForYou)
        navigator.open(route, in: .tryOn)
        XCTAssertEqual(navigator.tryOnPath, [route])
        navigator.returnToRoot(of: .tryOn)
        XCTAssertEqual(navigator.selectedTab, .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
        XCTAssertEqual(navigator.discoverPath, [.referenceImport])
    }
    @MainActor func testRescanFromHomeReturnsToTryOnRoot() {
        let navigator = AppNavigator(defaults: defaults)
        navigator.open(.faceScan, in: .tryOn)
        XCTAssertEqual(navigator.tryOnPath, [.faceScan])
        navigator.returnToRoot(of: .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
    }
    @MainActor func testFaceShapeResultIsRestoredAcrossLaunches() {
        let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))
        var result = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
        result.contourSamples = 12
        result.eyes = EyeScan(tiltLeft: 3, tiltRight: 5, spacing: 1.05, openness: 0.31, samples: 8, lidType: .hooded)
        FaceShapeStore(defaults: defaults).latest = result
        XCTAssertEqual(FaceShapeStore(defaults: defaults).latest, result)
        FaceShapeStore(defaults: defaults).latest = nil
        XCTAssertNil(FaceShapeStore(defaults: defaults).latest)
    }
}
