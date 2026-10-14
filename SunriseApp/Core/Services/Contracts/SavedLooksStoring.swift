enum SavedLooksError: Error, Equatable {
    case notImplemented
}

protocol SavedLooksStoring: Sendable {
    func list() async throws -> [SavedLookMetadata]
    /// Reserved metadata boundary; it is not a media persistence API.
    func save(_ look: SavedLookMetadata) async throws
}
