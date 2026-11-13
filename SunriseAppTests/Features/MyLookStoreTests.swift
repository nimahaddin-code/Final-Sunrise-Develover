// -Nimah: My Looks storage in a temporary folder: one entry per tool and look, attempts, titles, deleting, old files.
import XCTest
import UIKit
@testable import SunriseApp

final class MyLookStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MyLookStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A store whose clock moves one minute per save, so the order is clear.
    private func store() -> MyLookStore {
        let clock = Clock()
        return MyLookStore(root: root, now: { clock.tick() })
    }

    private final class Clock: @unchecked Sendable {
        private var minutes = 0.0
        private let lock = NSLock()
        func tick() -> Date {
            lock.lock(); defer { lock.unlock() }
            minutes += 1
            return Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60)
        }
    }

    private func draft(tool: String = "blush", look: String = "sunkissed", title: String = "Sunkissed blush",
                       score: Double = 0.7, photo: Bool = true) -> MyLookDraft {
        let jpeg = photo ? MyLookDraft.jpeg(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }) : nil
        return MyLookDraft(tool: tool, lookId: look, title: title,
                           shades: [MyLook.Shade(id: "blush.peach", name: "Peach", hex: "#F2A68C", source: .palette)],
                           intensity: 0.6,
                           score: MyLook.Score(overall: score, placement: score, shade: score, date: Date()),
                           rules: [MyLook.Rule(id: "blush.offset.too_high", band: "slight", side: "left")],
                           marks: [MyLook.Mark(side: "left", target: [CGPoint(x: 0.3, y: 0.5)], add: [], remove: [])],
                           expectedJPEG: jpeg, resultJPEG: jpeg)
    }

    func testFirstSaveIsOneLook() async throws {
        let store = store()
        let look = try await store.save(draft())
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(look.attemptCount, 1)
        XCTAssertEqual(look.title, "Sunkissed blush")
        XCTAssertEqual(look.rules.first?.id, "blush.offset.too_high")
        let url = await store.photoURL(look, expected: true)
        let expected = try XCTUnwrap(url)
        XCTAssertNotNil(UIImage(contentsOfFile: expected.path))
    }

    func testSameLookAgainUpdatesItsEntry() async throws {
        let store = store()
        let first = try await store.save(draft(score: 0.5))
        _ = try await store.rename(first.id, to: "My date look")
        let second = try await store.save(draft(title: "Another title", score: 0.8))
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.attemptCount, 2)
        XCTAssertEqual(second.previousScores.map(\.overall), [0.5])
        XCTAssertEqual(second.score.overall, 0.8)
        XCTAssertEqual(second.title, "My date look", "the title stays")
        XCTAssertEqual(second.createdAt, first.createdAt)
        XCTAssertGreaterThan(second.updatedAt, first.updatedAt)
    }

    func testDifferentLooksAreSeparateNewestFirst() async throws {
        let store = store()
        try await store.save(draft(look: "sunkissed"))
        try await store.save(draft(tool: "lips", look: "gradient", title: "Gradient lips"))
        let all = await store.all()
        XCTAssertEqual(all.map(\.lookId), ["gradient", "sunkissed"])
    }

    func testTitlesAreTrimmedCutAndNeverEmpty() async throws {
        let store = store()
        let look = try await store.save(draft())
        let empty = try await store.rename(look.id, to: "   ")
        XCTAssertEqual(empty.title, "Sunkissed blush")
        let long = try await store.rename(look.id, to: "  " + String(repeating: "a", count: 40))
        XCTAssertEqual(long.title.count, MyLook.titleLimit)
        let reread = await store.get(look.id)
        XCTAssertEqual(reread?.title, long.title)
    }

    func testDeleteRemovesTheFolder() async throws {
        let store = store()
        let look = try await store.save(draft())
        try await store.delete(look.id)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(look.id.uuidString).path))
    }

    func testNoPhotoSavesWithoutFiles() async throws {
        let store = store()
        let look = try await store.save(draft(photo: false))
        XCTAssertNil(look.expectedPhoto)
        let url = await store.photoURL(look, expected: false)
        XCTAssertNil(url)
    }

    func testStoreIsLeftOutOfBackups() async throws {
        let store = store()
        try await store.save(draft())
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    /// A file from an older version, with only the first fields, still reads; the rest take defaults.
    func testOlderFileStillReads() async throws {
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = """
        {"id":"\(id.uuidString)","tool":"eyeliner","lookId":"cat","title":"Cat eyeliner","createdAt":"2026-11-01T10:00:00Z"}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent(MyLookStore.lookFile))
        let read = await store().get(id)
        let look = try XCTUnwrap(read)
        XCTAssertEqual(look.schemaVersion, 0)
        XCTAssertEqual(look.attemptCount, 1)
        XCTAssertEqual(look.defaultTitle, "Cat eyeliner")
        XCTAssertTrue(look.previousScores.isEmpty)
        XCTAssertNil(look.score.overall)
    }

    func testDraftFromFeedbackKeepsIdsNotText() {
        var feedback = MakeupFeedback(score: 0.62, headline: "", comments: [])
        feedback.items = [.init(title: "A little high", say: "text", steps: [], band: .slight, rule: "blush.offset.too_high", side: .left)]
        feedback.praise = [.init(title: "Good", say: "text", steps: [], band: .ok, rule: "blush.praise.shade")]
        feedback.categories = [.init(id: "placement", title: "", symbol: "", percent: 0.55, label: "", items: []),
                               .init(id: "shade", title: "", symbol: "", percent: 0.8, label: "", items: [])]
        let shade = MakeupShade(id: "custom.1", name: "Custom colour", red: 1, green: 0.5, blue: 0, opacity: 0.7)
        let handoff = TutorialHandoff(tool: .blush, shades: [.blush: shade], intensities: [.blush: 0.4],
                                      blushStyle: BlushPlacementStyle.allCases.first)
        let draft = MyLookDraft(feedback: feedback, handoff: handoff, date: Date(), expectedJPEG: nil, resultJPEG: nil)
        XCTAssertEqual(draft.tool, "blush")
        XCTAssertEqual(draft.lookId, BlushPlacementStyle.allCases.first?.rawValue)
        XCTAssertEqual(draft.rules.map(\.id), ["blush.offset.too_high", "blush.praise.shade"])
        XCTAssertEqual(draft.rules.first?.band, "slight")
        XCTAssertEqual(draft.score.placement, 0.55)
        XCTAssertEqual(draft.shades.first?.hex, "#FF8000")
        XCTAssertEqual(draft.shades.first?.source, .product)
        XCTAssertEqual(draft.intensity, 0.4)
    }

    func testPhotoIsShrunkForTheStore() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 2400), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).image { context in UIColor.gray.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 2400)) }
        let data = try XCTUnwrap(MyLookDraft.jpeg(big))
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(image.size.width * image.scale, image.size.height * image.scale), 1280, accuracy: 1)
        XCTAssertLessThan(data.count, 1_000_000)
    }
}
