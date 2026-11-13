// -Nimah: the saved looks, one folder each: Application Support/MyLooks/<id>/ with look.json, expected.jpg, result.jpg,
// compare.jpg (the result lined up for the slider) and target.scan (`MyLookTarget`). Files are readable only while the phone is unlocked (complete file protection) and are left out of the
// iCloud / computer backup. Nothing else of a run is kept; nothing leaves the phone.
// Plain files rather than SwiftData: two photos and one small JSON per look, no queries, and older schema versions
// decode with defaults (`MyLook.init(from:)`).
import Foundation

actor MyLookStore {
    enum StoreError: Error, Equatable {
        /// The phone has no room for the photos or the data.
        case storageFull
        case notFound
        case writeFailed(String)
    }

    let root: URL
    private let fileManager = FileManager.default
    private let now: @Sendable () -> Date

    init(root: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.now = now
    }

    /// Application Support/MyLooks.
    static func live() -> MyLookStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MyLookStore(root: support.appendingPathComponent("MyLooks", isDirectory: true))
    }

    static let lookFile = "look.json", expectedFile = "expected.jpg", resultFile = "result.jpg", compareFile = "compare.jpg"
    enum Photo: Sendable { case expected, result, compare }

    // MARK: Reading

    /// Every saved look, the most recently updated first. Folders that cannot be read are skipped.
    func all() -> [MyLook] {
        guard let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return folders.compactMap { read(folder: $0) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func get(_ id: UUID) -> MyLook? { read(folder: folder(id)) }

    /// A saved photo's file, nil when the look has none.
    func photoURL(_ look: MyLook, expected: Bool) -> URL? { photoURL(look, expected ? .expected : .result) }

    func photoURL(_ look: MyLook, _ photo: Photo) -> URL? {
        let name = switch photo {
        case .expected: look.expectedPhoto
        case .result: look.resultPhoto
        case .compare: look.comparePhoto
        }
        return name.map { folder(look.id).appendingPathComponent($0) }
    }

    /// A saved photo's JPEG bytes.
    func photo(_ look: MyLook, _ photo: Photo) -> Data? {
        photoURL(look, photo).flatMap { try? Data(contentsOf: $0) }
    }

    /// The try-on's measured target, nil when the look has none (saved before schema 2, or no face at the shutter).
    func target(_ look: MyLook) -> FaceScan? {
        guard let name = look.targetScan, let data = try? Data(contentsOf: folder(look.id).appendingPathComponent(name)) else { return nil }
        return try? MyLookTarget.decode(data)
    }

    // MARK: Writing

    /// Saves a finished run. The same tool and look again replaces the photos, scores, shade and strength, keeps the title,
    /// moves the old score into `previousScores` and counts the attempt; otherwise a new look is added.
    @discardableResult
    func save(_ draft: MyLookDraft) throws -> MyLook {
        let date = now()
        var look: MyLook
        if var existing = all().first(where: { $0.tool == draft.tool && $0.lookId == draft.lookId }) {
            existing.previousScores.append(existing.score)
            existing.attemptCount += 1
            existing.updatedAt = date
            look = existing
        } else {
            look = MyLook(tool: draft.tool, lookId: draft.lookId, title: draft.title, createdAt: date, score: draft.score)
        }
        look.shades = draft.shades
        look.intensity = draft.intensity
        look.faceShape = draft.faceShape ?? look.faceShape
        look.eyeShape = draft.eyeShape ?? look.eyeShape
        look.score = draft.score
        look.rules = draft.rules
        look.marks = draft.marks
        look.language = draft.language
        look.schemaVersion = MyLook.currentSchema

        let folder = folder(look.id)
        try prepare(folder)
        look.expectedPhoto = try replace(Self.expectedFile, with: draft.expectedJPEG, in: folder)
        look.resultPhoto = try replace(Self.resultFile, with: draft.resultJPEG, in: folder)
        look.comparePhoto = try replace(Self.compareFile, with: draft.compareJPEG, in: folder)
        // A retry without a new desired photo keeps the target it was scored against.
        if let scan = draft.targetScan {
            let data: Data
            do { data = try MyLookTarget.encode(scan) } catch { throw StoreError.writeFailed(error.localizedDescription) }
            look.targetScan = try replace(MyLookTarget.fileName, with: data, in: folder)
        }
        try write(look, to: folder)
        return look
    }

    /// Trimmed, at most `MyLook.titleLimit` characters; an empty title goes back to the default one.
    @discardableResult
    func rename(_ id: UUID, to title: String) throws -> MyLook {
        guard var look = get(id) else { throw StoreError.notFound }
        look.title = MyLook.cleanTitle(title, default: look.defaultTitle)
        try write(look, to: folder(id))
        return look
    }

    /// Removes the look and both photos.
    func delete(_ id: UUID) throws {
        let folder = folder(id)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        do { try fileManager.removeItem(at: folder) } catch { throw StoreError.writeFailed(error.localizedDescription) }
    }

    // MARK: Files

    private func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func read(folder: URL) -> MyLook? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.lookFile)) else { return nil }
        return try? Self.decoder.decode(MyLook.self, from: data)
    }

    /// Creates the folders with complete protection and keeps the whole store out of backups.
    private func prepare(_ folder: URL) throws {
        do {
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: attributes)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var rootURL = root
            try rootURL.setResourceValues(values)
        } catch { throw Self.mapped(error) }
    }

    private func replace(_ name: String, with data: Data?, in folder: URL) throws -> String? {
        let url = folder.appendingPathComponent(name)
        guard let data else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        do { try data.write(to: url, options: [.atomic, .completeFileProtection]) } catch { throw Self.mapped(error) }
        return name
    }

    private func write(_ look: MyLook, to folder: URL) throws {
        do {
            let data = try Self.encoder.encode(look)
            try data.write(to: folder.appendingPathComponent(Self.lookFile), options: [.atomic, .completeFileProtection])
        } catch { throw Self.mapped(error) }
    }

    private static func mapped(_ error: Error) -> StoreError {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return .storageFull }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return .storageFull }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOSPC) { return .storageFull }
        return .writeFailed(ns.localizedDescription)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
