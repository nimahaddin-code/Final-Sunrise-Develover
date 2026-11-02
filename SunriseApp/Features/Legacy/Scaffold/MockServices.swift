/// These mocks power the scaffold and previews, not production features.
struct MockReferenceCatalog: ReferenceCatalogProviding {
    let items: [MakeupReference]
    init(items: [MakeupReference] = SampleData.references) { self.items = items }
    func references() async throws -> [MakeupReference] { items }
}

struct MockFaceTrackingChecker: FaceTrackingAvailabilityChecking {
    let result: FaceTrackingAvailability
    init(result: FaceTrackingAvailability = .notChecked) { self.result = result }
    func availability() async -> FaceTrackingAvailability { result }
}

struct MockSavedLooksStore: SavedLooksStoring {
    let items: [SavedLookMetadata]
    init(items: [SavedLookMetadata] = [SampleData.savedLook]) { self.items = items }
    func list() async throws -> [SavedLookMetadata] { items }
    func save(_ look: SavedLookMetadata) async throws { throw SavedLooksError.notImplemented }
}
