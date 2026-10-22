// -Nimah: LocalSavedLooksStore.swift — implementasi MVP SunriseApp.
import Foundation

// -Nimah: Actor mengisolasi file I/O dari UI; folder staging dipindah setelah semua file siap.
actor LocalSavedLooksStore: SavedLooksStoring {
    private let directory: URL
    init(directory: URL = URL.applicationSupportDirectory.appending(path: "SunriseApp/Looks", directoryHint: .isDirectory)) { self.directory = directory }
    func list() async throws -> [SavedLookMetadata] {
        try prepare()
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return try folders.filter { UUID(uuidString: $0.lastPathComponent) != nil }.map { folder in
            let item = try JSONDecoder().decode(SavedLookMetadata.self, from: Data(contentsOf: folder.appending(path: "metadata.json")))
            guard item.id == folder.lastPathComponent else { throw SavedLooksError.invalidIdentifier }
            return item
        }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ look: SavedLookMetadata) async throws { throw SavedLooksError.invalidCapture }
    func save(referenceID: String, before: Data, after: Data) async throws -> SavedLookMetadata {
        guard !before.isEmpty, !after.isEmpty, before.count < 15_000_000, after.count < 15_000_000 else { throw SavedLooksError.invalidCapture }
        try Task.checkCancellation()
        try prepare()
        let item = SavedLookMetadata(id: UUID().uuidString, referenceID: referenceID, createdAt: Date())
        let staging = directory.appending(path: ".pending-" + item.id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try before.write(to: staging.appending(path: "before.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try after.write(to: staging.appending(path: "after.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(item).write(to: staging.appending(path: "metadata.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: try folder(item.id))
        return item
    }
    func imageData(for lookID: String, kind: CaptureKind) async throws -> Data {
        let file = try folder(lookID).appending(path: kind.rawValue + ".jpg")
        guard FileManager.default.fileExists(atPath: file.path) else { throw SavedLooksError.missingCapture }
        return try Data(contentsOf: file)
    }
    func delete(id: String) async throws { try FileManager.default.removeItem(at: try folder(id)) }
    private func folder(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw SavedLooksError.invalidIdentifier }
        return directory.appending(path: id, directoryHint: .isDirectory)
    }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // -Nimah: Koleksi foto lokal dikecualikan dari backup otomatis untuk MVP.
        var location = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
    }
}
