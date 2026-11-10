// -Nimah: blush feedback v2 on synthetic faces: a flat grid of skin samples, the target drawn as two cheek ellipses,
// and blush added where a test puts it. Real photos and thresholds still need calibrating on a device.
import XCTest
import simd
import SwiftUI
@testable import SunriseApp

final class BlushFeedbackTests: XCTestCase {
    private let skin = Lab(65, 14, 17)
    /// Target centres (face-local mm): x > 0 is the person's own left cheek.
    private let targets = [SIMD2<Float>(45, -20), SIMD2<Float>(-45, -20)]
    private let outerRadius: Float = 15
    private let pink = SIMD3<Double>(0.91, 0.29, 0.38)

    private func database() throws -> FeedbackDatabase { try XCTUnwrap(FeedbackDatabase.load(), "database is in the app bundle") }

    private func screen(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: 200 - CGFloat(p.x) * 2, y: 420 - CGFloat(p.y) * 2) }

    private var outline: BlushGuideSnapshot {
        BlushGuideSnapshot(cheeks: targets.map { c in
            func ring(_ r: Float) -> [CGPoint] {
                (0..<36).map { k in
                    let a = Float(k) / 36 * 2 * .pi
                    return screen(c + SIMD2(cos(a), sin(a)) * r)
                }
            }
            return .init(inner: ring(outerRadius * 0.38 / 0.82), outer: ring(outerRadius), center: screen(c),
                         outward: screen(c + SIMD2(c.x > 0 ? 10 : -10, 0)))
        })
    }

    /// The colour change a blush of `strength` makes at `p` when centred on `centres` with `radius`.
    private func blush(at p: SIMD2<Float>, centres: [SIMD2<Float>], radius: Float, strength: Float) -> Lab {
        let shade = FeedbackColor.lab(sRGB: pink.x, pink.y, pink.z)
        let direction = simd_normalize(SIMD2(shade.y, shade.z))
        let w = centres.map { c -> Float in
            let d = simd_distance(p, c) / radius
            return d < 0.8 ? 1 : d < 1.2 ? (1.2 - d) / 0.4 : 0
        }.max() ?? 0
        return Lab(-3 * w, direction.x * strength * w, direction.y * strength * w)
    }

    private func scan(blushCentres: [SIMD2<Float>] = [], radius: Float = 15, strength: Float = 0, rendered: Bool = false,
                      withOutline: Bool = true, smile: Float = 0, leftLight: Lab = .zero) -> FaceScan {
        var samples: [FaceScan.Sample] = []
        for y in stride(from: Float(-115), through: 70, by: 2) {
            for x in stride(from: Float(-75), through: 75, by: 2) {
                let p = SIMD2(x, y)
                let lab = skin + blush(at: p, centres: blushCentres, radius: radius, strength: strength) + (x > 20 ? leftLight : .zero)
                let shown = rendered ? skin + blush(at: p, centres: targets, radius: outerRadius, strength: 12) : nil
                samples.append(.init(position: SIMD3(x, y, 0), area: 4, lab: lab, rendered: shown, screen: screen(p), visible: true))
            }
        }
        return FaceScan(samples: samples, yaw: 0, pitch: 0, roll: 0, blink: 0, smile: smile, jawOpen: 0, browRaise: 0,
                        ipd: 63, eyeY: 30, outline: withOutline ? outline : nil, viewport: CGSize(width: 400, height: 800))
    }

    private func evaluate(after: FaceScan, before: FaceScan? = nil, hadBefore: Bool = true) throws -> MakeupFeedback {
        let input = BlushFeedbackInput(before: before ?? scan(rendered: true), hadBeforePhoto: hadBefore, after: after,
                                       style: .youthful, shade: pink)
        return BlushFeedback.evaluate(input, database: try database(), language: .en)
    }

    func testBlushOnTargetGetsPraiseAndAHighScore() throws {
        let feedback = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 12))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(feedback.score), 0.9)
        XCTAssertTrue(feedback.items.allSatisfy { $0.band == .ok }, "\(feedback.items.map(\.title))")
        XCTAssertTrue(feedback.items.contains { $0.title == "Blush placement is right" })
    }

    func testBlushTooHighOnBothCheeksIsOneMessage() throws {
        let raised = targets.map { $0 + SIMD2(0, 8) }
        let feedback = try evaluate(after: scan(blushCentres: raised, radius: outerRadius, strength: 12))
        let high = feedback.items.filter { $0.title.localizedCaseInsensitiveContains("high") }
        XCTAssertEqual(high.count, 1, "\(feedback.items.map(\.title))")
        XCTAssertTrue(high[0].say.contains("both cheeks"), high[0].say)
        XCTAssertLessThan(try XCTUnwrap(feedback.score), 0.9)
    }

    /// The design's two cards, scored with `makeup-score.database.json`: label and meaning for that exact percentage.
    func testPlacementAndShadeCardsComeFromTheScoreDatabase() throws {
        let raised = targets.map { $0 + SIMD2(0, 8) }
        let feedback = try evaluate(after: scan(blushCentres: raised, radius: outerRadius, strength: 12))
        XCTAssertEqual(feedback.categories.map(\.id), ["placement", "shade"])
        let placement = try XCTUnwrap(feedback.categories.first)
        XCTAssertLessThan(placement.percent, 0.9)
        XCTAssertTrue(placement.items.contains { $0.rule == "blush.offset.too_high" })
        let scores = try XCTUnwrap(FeedbackDatabase.load()?.scores)
        let row = try XCTUnwrap(scores.tools["blush"]?["placement"]?.percent.first { $0.percent == Int((placement.percent * 100).rounded()) })
        XCTAssertTrue(placement.label.hasSuffix("high"), "the card says which way: \(placement.label)")
        XCTAssertEqual(placement.description, row.description.en)
        XCTAssertEqual(feedback.categories.last?.label, "Spot on")
        XCTAssertTrue(feedback.summary.hasPrefix("Your shade is spot on. Placement is "), feedback.summary)
        XCTAssertEqual(feedback.placement?.value, placement.percent, "Hanum's Placement part follows the card")
        XCTAssertEqual(try XCTUnwrap(feedback.score), feedback.categories.map(\.percent).reduce(0, +) / 2, accuracy: 0.0001)

        let onTarget = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 12))
        XCTAssertTrue(onTarget.categories.allSatisfy { $0.percent >= 0.9 && $0.items.isEmpty }, "\(onTarget.categories.map(\.label))")
        let none = try evaluate(after: scan())
        XCTAssertEqual(none.categories.map(\.percent), [0.01, 0.01], "nothing applied: 1% for both")
    }

    func testCardNotesSayWhichWay() {
        XCTAssertEqual(FeedbackNote.text(rule: "blush.offset.too_high", band: .slight, language: .en), "A little high")
        XCTAssertEqual(FeedbackNote.text(rule: "blush.intensity.too_heavy", band: .clear, language: .en), "Too heavy")
        XCTAssertEqual(FeedbackNote.text(rule: "brow.tail.too_short", band: .large, language: .id), "Jauh terlalu pendek")
        XCTAssertEqual(FeedbackNote.text(rule: "blush.spill.eye", band: .clear, language: .en), "Past the line")
        XCTAssertEqual(FeedbackNote.text(rule: "eyeliner.none", band: .large, language: .id), "Belum terlihat")
        XCTAssertNil(FeedbackNote.text(rule: "brow.arch.too_inner", band: .clear, language: .en), "no word: the score label is used")
    }

    /// The After photo is moved, scaled and turned so its eyes land on the Before photo's eyes.
    func testAlignmentPutsTheEyesOnTheEyes() throws {
        let t = try XCTUnwrap(PhotoAlignment.transform(from: (CGPoint(x: 100, y: 200), CGPoint(x: 160, y: 200)),
                                                       to: (CGPoint(x: 120, y: 260), CGPoint(x: 240, y: 260))))
        let left = CGPoint(x: 100, y: 200).applying(t), right = CGPoint(x: 160, y: 200).applying(t)
        XCTAssertEqual(left.x, 120, accuracy: 0.001); XCTAssertEqual(left.y, 260, accuracy: 0.001)
        XCTAssertEqual(right.x, 240, accuracy: 0.001); XCTAssertEqual(right.y, 260, accuracy: 0.001)
        XCTAssertNil(PhotoAlignment.transform(from: (.zero, .zero), to: (.zero, CGPoint(x: 10, y: 0))))

        let picture = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80)).image { _ in }
        var before = scan(), after = scan()
        before.leftEye = CGPoint(x: 150, y: 300); before.rightEye = CGPoint(x: 250, y: 300)
        after.leftEye = CGPoint(x: 140, y: 310); after.rightEye = CGPoint(x: 240, y: 310)
        let aligned = PhotoAlignment.align(after: picture, afterScan: after, to: picture, beforeScan: before)
        XCTAssertEqual(aligned.size, picture.size)
        XCTAssertFalse(aligned === picture, "moved: a new picture")
        after.rightEye = CGPoint(x: 400, y: 310)   // 2.6x wider: implausible, left as it is
        XCTAssertTrue(PhotoAlignment.align(after: picture, afterScan: after, to: picture, beforeScan: before) === picture)
    }

    func testScoreCurveMatchesTheDatabaseDescription() {
        XCTAssertEqual(ScoreDatabase.score(0, ok: 3, slight: 6, clear: 10), 100)
        XCTAssertEqual(ScoreDatabase.score(3, ok: 3, slight: 6, clear: 10), 90)
        XCTAssertEqual(ScoreDatabase.score(6, ok: 3, slight: 6, clear: 10), 75)
        XCTAssertEqual(ScoreDatabase.score(10, ok: 3, slight: 6, clear: 10), 55)
        XCTAssertEqual(ScoreDatabase.score(20, ok: 3, slight: 6, clear: 10), 20)
        XCTAssertEqual(ScoreDatabase.score(8.8, ok: 3, slight: 6, clear: 10), 61, accuracy: 0.01, "61% = 8.8 mm, as the page says")
        XCTAssertEqual(ScoreDatabase.score(99, ok: 3, slight: 6, clear: 10), 1)
    }

    func testOneCheekLowNamesThatCheek() throws {
        let feedback = try evaluate(after: scan(blushCentres: [targets[0] + SIMD2(0, -9), targets[1]], radius: outerRadius, strength: 12))
        let low = try XCTUnwrap(feedback.items.first { $0.title.localizedCaseInsensitiveContains("low") }, "\(feedback.items.map(\.title))")
        XCTAssertTrue(low.say.contains("left cheek"), "x > 0 is the person's own left: \(low.say)")
    }

    /// -Nimah: beginners cannot measure millimetres or degrees on their own face; the photo crop shows where instead.
    func testNoMessageShowsMeasurements() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "makeup-feedback.database", withExtension: "json"))
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        var says: [String] = []
        func walk(_ x: Any) {
            if let d = x as? [String: Any] {
                for (k, v) in d { if k == "say", let s = v as? String { says.append(s) } else { walk(v) } }
            } else if let a = x as? [Any] { a.forEach(walk) }
        }
        walk(try XCTUnwrap(root?["tools"])); walk(try XCTUnwrap(root?["capture"]))
        XCTAssertGreaterThan(says.count, 400)
        for say in says {
            for number in ["{delta}", "{value}", "{target}", " mm", "°", "%"] {
                XCTAssertFalse(say.contains(number), say)
            }
        }
    }

    @MainActor func testFirstFixIsMarkedOnItsCheek() throws {
        let feedback = try evaluate(after: scan(blushCentres: [targets[0] + SIMD2(0, -9), targets[1]], radius: outerRadius, strength: 12))
        let first = try XCTUnwrap(feedback.fixes.first, "\(feedback.items.map(\.rule))")
        XCTAssertEqual(first.side, .left, first.rule)
        let mark = try XCTUnwrap(feedback.mark(for: first))
        XCTAssertFalse(mark.target.isEmpty)
        XCTAssertFalse(mark.add.isEmpty, "the upper part of the target is bare")
        XCTAssertFalse(mark.remove.isEmpty, "blush went below the line")
        // The person's left cheek (x > 0) is on the photo's left half in the test's screen mapping.
        XCTAssertLessThan(mark.target.map(\.x).reduce(0, +) / CGFloat(mark.target.count), 0.5)
        XCTAssertTrue(feedback.praise.isEmpty || feedback.praise.allSatisfy { $0.band == .ok })
        try render(feedback, after: [targets[0] + SIMD2(0, -9), targets[1]], name: "blush")
    }

    /// Draws the fixes with a plain synthetic photo for a look at the layout (saved next to the test logs; not compared).
    @MainActor private func render(_ feedback: MakeupFeedback, after centres: [SIMD2<Float>], name: String) throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { context in
            UIColor(red: 0.88, green: 0.72, blue: 0.62, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
            UIColor(red: 0.93, green: 0.5, blue: 0.58, alpha: 0.8).setFill()
            for c in centres {
                let p = screen(c), r = CGFloat(outerRadius) * 2
                context.cgContext.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
        }
        let renderer = ImageRenderer(content: FeedbackFixes(feedback: feedback, photo: photo).frame(width: 362).padding(16)
            .background(Color(white: 0.97)))
        renderer.scale = 2
        let data = try XCTUnwrap(renderer.uiImage?.pngData())
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("feedback-fixes-\(name).png")
        try data.write(to: url)
        print("FIXES-RENDER \(url.path)")
    }

    func testNoBlushSaysSo() throws {
        let feedback = try evaluate(after: scan())
        XCTAssertEqual(feedback.items.first?.title, "No blush found")
        XCTAssertTrue(feedback.items.first?.say.contains("both cheeks") ?? false)
    }

    /// Device test 2026-11-09: no blush worn, the head tilted and one cheek lit warmer; that cheek read as blush.
    func testABareCheekInWarmerLightIsNotBlush() throws {
        let feedback = try evaluate(after: scan(leftLight: Lab(-3, 4, 4)))
        XCTAssertEqual(feedback.items.first?.rule, "blush.none")
        XCTAssertTrue(feedback.items.first?.say.contains("both cheeks") ?? false, feedback.items.first?.say ?? "")
    }

    func testTooHeavyBlushIsCalledHeavy() throws {
        let feedback = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 30))
        XCTAssertTrue(feedback.items.contains { $0.title.localizedCaseInsensitiveContains("heavy") }, "\(feedback.items.map(\.title))")
    }

    func testEveryMessageHasItsPlaceholdersFilled() throws {
        for after in [scan(blushCentres: targets.map { $0 + SIMD2(6, 9) }, radius: 22, strength: 30),
                      scan(blushCentres: [targets[0]], radius: 8, strength: 6), scan()] {
            for item in try evaluate(after: after).items {
                XCTAssertFalse(item.say.contains("{") || item.title.contains("{"), item.say)
            }
        }
    }

    func testSmilingStopsTheCheckAndAsksForARetake() throws {
        let feedback = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 12, smile: 0.6))
        XCTAssertNil(feedback.score)
        XCTAssertEqual(feedback.items.map(\.title), ["Smiling"])
    }

    func testNoDesiredPhotoExplainsWhy() throws {
        let feedback = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 12), hadBefore: false)
        XCTAssertNil(feedback.score)
        XCTAssertEqual(feedback.items.first?.title, "No Try On photo")
    }

    func testIndonesianTextsComeFromTheDatabase() throws {
        let input = BlushFeedbackInput(before: scan(rendered: true), hadBeforePhoto: true, after: scan(), style: .youthful, shade: pink)
        let feedback = BlushFeedback.evaluate(input, database: try database(), language: .id)
        XCTAssertEqual(feedback.items.first?.title, "Blush belum terlihat")
        XCTAssertTrue(feedback.items.first?.say.contains("kedua pipi") ?? false)
    }

    func testColourDifferenceMatchesThePublishedCIEDE2000Pair() {
        // Sharma, Wu and Dalal (2005), pair 1.
        XCTAssertEqual(FeedbackColor.deltaE2000(Lab(50, 2.6772, -79.7751), Lab(50, 0, -82.7485)), 2.0425, accuracy: 0.001)
    }

    func testBandsReadThresholdsAsTheDatabaseSays() {
        let t = FeedbackDatabase.Thresholds(ok: 3, slight: 6, clear: 10)
        XCTAssertEqual(FeedbackBand.of(-2, kind: "abs", t), .ok)
        XCTAssertEqual(FeedbackBand.of(7, kind: "abs", t), .clear)
        XCTAssertEqual(FeedbackBand.of(7, kind: "abs", t, scale: 1.5), .slight, "ipd-scaled")
        XCTAssertEqual(FeedbackBand.of(0.5, kind: "ratio", FeedbackDatabase.Thresholds(ok: 1.25, slight: 1.5, clear: 2)), .clear)
        XCTAssertEqual(FeedbackBand.of(40, kind: "min", FeedbackDatabase.Thresholds(ok: 85, slight: 70, clear: 50)), .large)
    }
}
