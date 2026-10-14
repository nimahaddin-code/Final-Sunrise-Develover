import XCTest
@testable import SunriseApp

final class TutorialViewModelTests: XCTestCase {
    @MainActor func testStepNavigationStopsAtBothBoundaries() {
        let model = TutorialViewModel(tutorial: Tutorial(referenceID: "test", steps: [.blush, .lips]))
        model.previous()
        XCTAssertEqual(model.currentStep, .blush)
        XCTAssertFalse(model.canGoBack)
        model.next(); model.next()
        XCTAssertEqual(model.currentStep, .lips)
        XCTAssertFalse(model.canGoNext)
        model.previous()
        XCTAssertEqual(model.currentStep, .blush)
    }
    @MainActor func testEmptyTutorialHasNoStepAndCannotAdvance() {
        let model = TutorialViewModel(tutorial: Tutorial(referenceID: "empty", steps: []))
        model.next(); model.previous()
        XCTAssertNil(model.currentStep)
        XCTAssertFalse(model.canGoNext)
        XCTAssertFalse(model.canGoBack)
    }
}
