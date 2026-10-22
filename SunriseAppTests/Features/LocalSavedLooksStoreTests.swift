// -Nimah: LocalSavedLooksStoreTests.swift — implementasi MVP SunriseApp.
import XCTest
@testable import SunriseApp

final class LocalSavedLooksStoreTests: XCTestCase {
    private func location() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory) }
    func testSaveReloadAndDeleteKeepCapturePairTogether() async throws {
        let root = location(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalSavedLooksStore(directory: root)
        let before = Data([1,2,3]), after = Data([4,5,6])
        let item = try await store.save(referenceID: "douyin", before: before, after: after)
        let reopened = LocalSavedLooksStore(directory: root)
        let items = try await reopened.list()
        XCTAssertEqual(items, [item])
        let savedBefore = try await reopened.imageData(for: item.id, kind: .before)
        let savedAfter = try await reopened.imageData(for: item.id, kind: .after)
        XCTAssertEqual(savedBefore, before); XCTAssertEqual(savedAfter, after)
        try await reopened.delete(id: item.id)
        let empty = try await store.list(); XCTAssertTrue(empty.isEmpty)
    }
    func testEmptyCaptureRejectsSaveWithoutCreatingAResult() async throws {
        let root = location(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalSavedLooksStore(directory: root)
        do { _ = try await store.save(referenceID: "latte", before: Data(), after: Data([1])); XCTFail("Must reject incomplete captures") }
        catch { XCTAssertEqual(error as? SavedLooksError, .invalidCapture) }
        let items = try await store.list(); XCTAssertTrue(items.isEmpty)
    }
    func testIdentifierCannotEscapeStorageDirectory() async throws {
        let store = LocalSavedLooksStore(directory: location())
        do { _ = try await store.imageData(for: "../private", kind: .after); XCTFail("Must reject traversal") }
        catch { XCTAssertEqual(error as? SavedLooksError, .invalidIdentifier) }
    }
    func testCorruptMetadataIsReportedInsteadOfSilentDataLoss() async throws {
        let root = location(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: folder.appending(path: "metadata.json"))
        do { _ = try await LocalSavedLooksStore(directory: root).list(); XCTFail("Must report unreadable metadata") }
        catch { XCTAssertNotNil(error) }
    }
}
