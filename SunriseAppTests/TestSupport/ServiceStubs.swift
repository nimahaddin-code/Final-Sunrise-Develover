import Foundation
@testable import SunriseApp

enum StubError: Error { case unavailable }
actor RetryableCatalogStub: ReferenceCatalogProviding {
    private var attempts = 0
    func references() async throws -> [MakeupReference] {
        attempts += 1
        if attempts == 1 { throw StubError.unavailable }
        return []
    }
}
struct CancelledCatalogStub: ReferenceCatalogProviding {
    func references() async throws -> [MakeupReference] { throw CancellationError() }
}
struct FailingSavedLooksStub: SavedLooksStoring {
    func list() async throws -> [SavedLookMetadata] { throw StubError.unavailable }
    func save(_ look: SavedLookMetadata) async throws { throw StubError.unavailable }
}
