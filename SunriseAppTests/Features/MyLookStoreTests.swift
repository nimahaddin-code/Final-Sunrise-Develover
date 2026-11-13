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
        XCTAssertEqual(draft.rules.map(\.kind), [.fix, .praise])
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

    // MARK: Prompt 2: target, feedback told again, Try again

    private func scan() -> FaceScan {
        let samples = (0..<50).map { i in
            FaceScan.Sample(position: SIMD3(Float(i), -Float(i), 1), area: 0.5, lab: Lab(60, 12, 14),
                            rendered: i.isMultiple(of: 2) ? Lab(50, 30, 10) : nil, screen: CGPoint(x: Double(i) * 2, y: 300.5),
                            visible: i != 3)
        }
        let outline = BlushGuideSnapshot(cheeks: [.init(inner: [CGPoint(x: 1, y: 2)], outer: [CGPoint(x: 3, y: 4)],
                                                        center: CGPoint(x: 5, y: 6), outward: CGPoint(x: 7, y: 8))])
        return FaceScan(samples: samples, yaw: 2, pitch: -1, roll: 0.5, blink: 0, smile: 0.1, jawOpen: 0, browRaise: 0,
                        ipd: 63, eyeY: 30, outline: outline, viewport: CGSize(width: 400, height: 800),
                        leftEye: CGPoint(x: 150, y: 300), rightEye: CGPoint(x: 250, y: 300))
    }

    func testTargetIsSavedAndReadBack() async throws {
        let store = store()
        var withTarget = draft()
        withTarget.targetScan = scan()
        let look = try await store.save(withTarget)
        let read = await store.target(look)
        let target = try XCTUnwrap(read)
        let original = scan()
        XCTAssertEqual(target.samples.count, original.samples.count)
        XCTAssertEqual(target.samples[4].position, original.samples[4].position)
        XCTAssertEqual(target.samples[4].rendered, original.samples[4].rendered)
        XCTAssertNil(target.samples[5].rendered)
        XCTAssertFalse(target.samples[3].visible)
        XCTAssertEqual(target.samples[7].screen, original.samples[7].screen)
        XCTAssertEqual(target.outline, original.outline)
        XCTAssertEqual(target.leftEye, original.leftEye)
        XCTAssertEqual(target.viewport, original.viewport)
        // A retry with no new target keeps the saved one.
        let again = try await store.save(draft())
        let kept = await store.target(again)
        XCTAssertNotNil(kept)
    }

    private func savedLook(language: String) -> MyLook {
        var look = MyLook(tool: "eyeliner", lookId: "cat", title: "Cat eyeliner", createdAt: Date(),
                          score: MyLook.Score(overall: 0.6, placement: 0.5, shade: 0.7, date: Date()))
        look.language = language
        look.rules = [
            MyLook.Rule(id: "eyeliner.lash_gap", band: "slight", side: "left", kind: .fix, values: ["zone": "outer third"],
                        cards: ["placement"], top: true),
            MyLook.Rule(id: "eyeliner.none", band: "large", side: "right", kind: .fix, cards: ["placement", "shade"]),
        ]
        look.marks = [MyLook.Mark(side: "left", target: [CGPoint(x: 0.4, y: 0.4)], add: [], remove: [])]
        return look
    }

    func testSavedFeedbackIsToldAgain() throws {
        let database = try XCTUnwrap(FeedbackDatabase.load())
        let feedback = MyLookFeedback.feedback(for: savedLook(language: "en"), database: database, language: .en)
        XCTAssertEqual(feedback.score, 0.6)
        XCTAssertEqual(feedback.items.first?.rule, "eyeliner.lash_gap")
        XCTAssertEqual(feedback.fixes.first?.side, .left)
        XCTAssertTrue(try XCTUnwrap(feedback.items.first).say.contains("outer third"))
        XCTAssertEqual(feedback.categories.map(\.id), ["placement", "shade"])
        XCTAssertEqual(feedback.categories.first?.items.count, 2, "nothing found is told on both cards")
        XCTAssertEqual(feedback.categories.last?.items.map(\.rule), ["eyeliner.none"])
        XCTAssertEqual(feedback.marks.count, 1)
        for item in feedback.categories.flatMap(\.items) { XCTAssertFalse(item.say.contains("{"), item.say) }
    }

    func testSavedFeedbackFollowsTheCurrentLanguage() throws {
        let database = try XCTUnwrap(FeedbackDatabase.load())
        let feedback = MyLookFeedback.feedback(for: savedLook(language: "en"), database: database, language: .id)
        let say = try XCTUnwrap(feedback.items.first).say
        XCTAssertTrue(say.contains("sepertiga luar"), say)
        XCTAssertFalse(say.contains("outer third"), say)
    }

    func testDraftKeepsTopCardsAndWords() {
        var feedback = MakeupFeedback(score: 0.5, headline: "", comments: [])
        let gap = MakeupFeedback.Item(title: "", say: "", steps: [], band: .slight, rule: "eyeliner.lash_gap", side: .left,
                                      values: ["zone": "outer third"])
        let none = MakeupFeedback.Item(title: "", say: "", steps: [], band: .large, rule: "eyeliner.none", side: .right)
        feedback.items = [gap]
        feedback.categories = [.init(id: "placement", title: "", symbol: "", percent: 0.5, label: "", items: [gap, none]),
                               .init(id: "shade", title: "", symbol: "", percent: 0.5, label: "", items: [none])]
        let rules = MyLookDraft.rules(feedback)
        XCTAssertEqual(rules.map(\.id), ["eyeliner.lash_gap", "eyeliner.none"])
        XCTAssertEqual(rules[0].top, true)
        XCTAssertEqual(rules[0].values?["zone"], "outer third")
        XCTAssertEqual(rules[1].cards, ["placement", "shade"])
    }

    func testTryAgainUsesTheSameChoices() throws {
        var look = MyLook(tool: "blush", lookId: BlushPlacementStyle.sunkissed.rawValue, title: "Sunkissed blush",
                          createdAt: Date(), score: MyLook.Score(date: Date()))
        let palette = try XCTUnwrap(MakeupPalette.shades(for: .blush).first)
        look.shades = [MyLook.Shade(palette)]
        look.intensity = 0.35
        let handoff = try XCTUnwrap(MyLookFeedback.handoff(for: look))
        XCTAssertEqual(handoff.tool, .blush)
        XCTAssertEqual(handoff.blushStyle, .sunkissed)
        XCTAssertEqual(handoff.shades[.blush]?.id, palette.id)
        XCTAssertEqual(handoff.intensities[.blush], 0.35)
        XCTAssertEqual(handoff.enabled, [.blush])
        XCTAssertEqual(handoff.lookId, look.lookId, "the retry's feedback updates this same look")

        var custom = look
        custom.shades = [MyLook.Shade(id: "custom.x", name: "Custom colour", hex: "#FF8000", source: .product, opacity: 0.6)]
        let made = try XCTUnwrap(MyLookFeedback.handoff(for: custom)?.shades[.blush])
        XCTAssertEqual(made.red, 1, accuracy: 0.01)
        XCTAssertEqual(made.green, 128.0 / 255, accuracy: 0.01)
        XCTAssertEqual(made.opacity, 0.6)
    }

    func testCardShowsWhichWayTheScoreWent() {
        var look = MyLook(tool: "blush", lookId: "a", title: "A", createdAt: Date(), score: MyLook.Score(overall: 0.8, date: Date()))
        XCTAssertEqual(MyLookCard.trend(look), 0)
        look.previousScores = [MyLook.Score(overall: 0.6, date: Date())]
        XCTAssertEqual(MyLookCard.trend(look), 1)
        look.previousScores = [MyLook.Score(overall: 0.9, date: Date())]
        XCTAssertEqual(MyLookCard.trend(look), -1)
    }
}
