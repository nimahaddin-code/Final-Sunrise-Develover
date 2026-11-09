// -Nimah: blush feedback v2 on synthetic faces: a flat grid of skin samples, the target drawn as two cheek ellipses,
// and blush added where a test puts it. Real photos and thresholds still need calibrating on a device.
import XCTest
import simd
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

    func testCardsScoreEachCategoryAndHoldItsAdvice() throws {
        let raised = targets.map { $0 + SIMD2(0, 8) }
        let feedback = try evaluate(after: scan(blushCentres: raised, radius: outerRadius, strength: 12))
        let placement = try XCTUnwrap(feedback.categories.first { $0.id == "placement" })
        XCTAssertLessThan(placement.percent, 1)
        XCTAssertTrue(placement.items.contains { $0.rule == "blush.offset.too_high" })
        XCTAssertEqual(placement.label, placement.items.first?.title)
        XCTAssertTrue(feedback.summary.hasSuffix("."))
        let onTarget = try evaluate(after: scan(blushCentres: targets, radius: outerRadius, strength: 12))
        XCTAssertTrue(onTarget.categories.allSatisfy { $0.items.isEmpty && $0.label == "Spot on" }, "\(onTarget.categories.map(\.label))")
    }

    func testOneCheekLowNamesThatCheek() throws {
        let feedback = try evaluate(after: scan(blushCentres: [targets[0] + SIMD2(0, -9), targets[1]], radius: outerRadius, strength: 12))
        let low = try XCTUnwrap(feedback.items.first { $0.title.localizedCaseInsensitiveContains("low") }, "\(feedback.items.map(\.title))")
        XCTAssertTrue(low.say.contains("left cheek"), "x > 0 is the person's own left: \(low.say)")
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
