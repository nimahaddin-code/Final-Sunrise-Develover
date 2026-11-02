protocol ReferenceCatalogProviding: Sendable {
    func references() async throws -> [MakeupReference]
}
