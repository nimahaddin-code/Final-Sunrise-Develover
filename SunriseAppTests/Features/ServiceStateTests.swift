import XCTest
@testable import SunriseApp

final class ServiceStateTests: XCTestCase {
    @MainActor func testCatalogFailureCanBeRetriedToAnEmptyState() async {
        let model = ReferenceCatalogViewModel(service: RetryableCatalogStub())
        await model.load()
        XCTAssertEqual(model.state, .failed)
        await model.load()
        XCTAssertEqual(model.state, .loaded([]))
    }
    @MainActor func testCancelledCatalogDoesNotPresentAnError() async {
        let model = ReferenceCatalogViewModel(service: CancelledCatalogStub())
        await model.load()
        XCTAssertEqual(model.state, .idle)
    }
    @MainActor func testSavedCollectionFailureIsExposed() async {
        let model = SavedLooksViewModel(store: FailingSavedLooksStub())
        await model.load()
        XCTAssertEqual(model.state, .failed)
    }
    @MainActor func testUnsupportedTrackingCanReachTheUIWithoutARKit() async {
        let model = FaceCalibrationViewModel(checker: MockFaceTrackingChecker(result: .unsupported(reason: "Test device")))
        await model.loadAvailability()
        XCTAssertEqual(model.availability, .unsupported(reason: "Test device"))
    }
    func testMockSaveRejectsUnimplementedPersistence() async {
        do {
            try await MockSavedLooksStore().save(SampleData.savedLook)
            XCTFail("Mock save must not report success")
        } catch {
            XCTAssertEqual(error as? SavedLooksError, .notImplemented)
        }
    }
}
