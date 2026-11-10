// -Nimah: brow and eyeliner feedback on synthetic faces. Skin is a flat L* 65; the target is drawn dark into the
// desired-look photo's shown colours, the result into the result photo. Real photos still need calibrating on a device.
import XCTest
import simd
@testable import SunriseApp

final class LineFeedbackTests: XCTestCase {
    private let skin = Lab(65, 12, 16)
    private let eyeY: Float = 30

    private func database() throws -> FeedbackDatabase { try XCTUnwrap(FeedbackDatabase.load()) }

    /// A dark shape: is face-local point `p` (mm) inside it, for either side (mirrored on x).
    typealias Shape = (SIMD2<Float>) -> Bool

    private func scan(shown: Shape? = nil, worn: Shape? = nil, darkness: Float = 30, wornDarkness: Float = 30, wornAB: SIMD2<Float>? = nil,
                      smile: Float = 0) -> FaceScan {
        var samples: [FaceScan.Sample] = []
        func add(_ x: Float, _ y: Float, _ step: Float) {
            let p = SIMD2(x, y)
            var lab = skin
            if let worn, worn(p) { lab.x -= wornDarkness; if let wornAB { lab.y = wornAB.x; lab.z = wornAB.y } }
            var rendered: Lab?
            if let shown { rendered = skin; if shown(p) { rendered!.x -= darkness } }
            samples.append(.init(position: SIMD3(x, y, 0), area: step * step, lab: lab, rendered: rendered,
                                 screen: CGPoint(x: Double(200 - x * 2), y: Double(420 - y * 2)), visible: true))
        }
        for y in stride(from: Float(-115), through: 75, by: 1) where abs(y - eyeY) >= 10 {
            for x in stride(from: Float(-75), through: 75, by: 1) { add(x, y, 1) }
        }
        for y in stride(from: eyeY - 9.75, to: eyeY + 10, by: 0.5) {
            for x in stride(from: Float(-70), through: 70, by: 0.5) { add(x, y, 0.5) }
        }
        return FaceScan(samples: samples, yaw: 0, pitch: 0, roll: 0, blink: 0, smile: smile, jawOpen: 0, browRaise: 0,
                        ipd: 63, eyeY: eyeY, outline: nil, viewport: CGSize(width: 400, height: 800))
    }

    // MARK: Brows

    /// A brow from head (|x| = 15) over an arch (|x| = 40) to the tail, thickness tapering from 7 to 3 mm.
    private func brow(headX: Float = 15, tailX: Float = 58, lift: Float = 0, thick: Float = 1) -> Shape {
        { p in
            let x = abs(p.x)
            guard x >= headX, x <= tailX else { return false }
            let t = (x - headX) / (tailX - headX)
            let centre = self.eyeY + 15 + lift + (t < 0.6 ? 7 * t / 0.6 : 7 - 9 * (t - 0.6) / 0.4)
            let half = (3.5 - 2 * t) * thick
            return abs(p.y - centre) <= half
        }
    }

    private func browFeedback(_ worn: Shape?, wornDarkness: Float = 30) throws -> MakeupFeedback {
        let input = LineFeedbackInput(before: scan(shown: brow()), hadBeforePhoto: true,
                                      after: scan(worn: worn, wornDarkness: wornDarkness), look: nil)
        return BrowFeedback.evaluate(input, database: try database(), language: .en)
    }

    func testBrowOnTargetIsPraised() throws {
        let feedback = try browFeedback(brow())
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(feedback.score), 0.9, "\(feedback.items.map(\.rule))")
        XCTAssertTrue(feedback.items.contains { $0.rule == "brow.praise.shape" }, "\(feedback.items.map(\.rule))")
    }

    func testBrowAndLinerGetTheTwoCards() throws {
        for feedback in [try browFeedback(brow(tailX: 50)), try linerFeedback(liner(wing: 2))] {
            XCTAssertEqual(feedback.categories.map(\.id), ["placement", "shade"])
            XCTAssertLessThan(try XCTUnwrap(feedback.categories.first).percent, 1)
            XCTAssertFalse(try XCTUnwrap(feedback.categories.first).description.isEmpty)
        }
    }

    func testShortBrowTailIsNamed() throws {
        let feedback = try browFeedback(brow(tailX: 50))
        let tail = try XCTUnwrap(feedback.items.first { $0.rule == "brow.tail.too_short" }, "\(feedback.items.map(\.rule))")
        XCTAssertTrue(tail.say.contains("both brows"), tail.say)
    }

    func testShortBrowTailIsMarkedWhereToAdd() throws {
        let feedback = try browFeedback(brow(tailX: 50))
        let first = try XCTUnwrap(feedback.fixes.first, "\(feedback.items.map(\.rule))")
        let mark = try XCTUnwrap(feedback.mark(for: first), first.rule)
        XCTAssertFalse(mark.add.isEmpty, "the end of the tail is bare")
        XCTAssertEqual(feedback.marks.count, 2)
    }

    func testBrowDrawnTooHighIsNamed() throws {
        let feedback = try browFeedback(brow(lift: 4))
        XCTAssertTrue(feedback.items.contains { $0.rule.hasPrefix("brow.head.too_high") || $0.rule.hasPrefix("brow.tail.too_high") },
                      "\(feedback.items.map(\.rule))")
    }

    func testNoBrowProductSaysSo() throws {
        let feedback = try browFeedback(nil)
        XCTAssertEqual(feedback.items.first?.rule, "brow.none")
    }

    /// B202 Brown, the shade chosen on Try On in these tests.
    private let brown = SIMD3<Double>(0.38, 0.27, 0.20)

    private func browColour(_ ab: SIMD2<Float>) throws -> MakeupFeedback {
        let input = LineFeedbackInput(before: scan(shown: brow()), hadBeforePhoto: true,
                                      after: scan(worn: brow(), wornAB: ab), look: nil, shade: brown)
        return BrowFeedback.evaluate(input, database: try database(), language: .en)
    }

    func testBrowInTheChosenShadeHasNoColourMessage() throws {
        let shade = FeedbackColor.lab(sRGB: brown.x, brown.y, brown.z)
        let feedback = try browColour(SIMD2(shade.y, shade.z))
        XCTAssertFalse(feedback.categories.flatMap(\.items).contains { $0.rule.hasPrefix("brow.hue") }, "\(feedback.items.map(\.rule))")
    }

    func testRedderBrowIsCalledWarmer() throws {
        let feedback = try browColour(SIMD2(22, 8))   // hue about 20°: red-brown
        XCTAssertTrue(feedback.categories.flatMap(\.items).contains { $0.rule == "brow.hue.warmer" }, "\(feedback.items.map(\.rule))")
    }

    func testAshyBrowIsCalledCooler() throws {
        let feedback = try browColour(SIMD2(1, 10))   // hue about 85°: grey-yellow
        XCTAssertTrue(feedback.categories.flatMap(\.items).contains { $0.rule == "brow.hue.cooler" }, "\(feedback.items.map(\.rule))")
    }

    func testLightBrowIsCalledLight() throws {
        let feedback = try browFeedback(brow(), wornDarkness: 14)
        XCTAssertTrue(feedback.items.contains { $0.rule == "brow.darkness.too_light" }, "\(feedback.items.map(\.rule))")
    }

    // MARK: Eyeliner

    /// An upper line from |x| = 18 to 46 just above the eye, 1.5 mm thick, then a wing rising to |x| = 46 + wing.
    private func liner(start: Float = 18, wing: Float = 7, thickness: Float = 1.5) -> Shape {
        { p in
            let x = abs(p.x)
            guard x >= start, x <= 46 + wing else { return false }
            if x <= 46 { return abs(p.y - (self.eyeY + 3)) <= thickness / 2 }
            let t = (x - 46) / 7
            return abs(p.y - (self.eyeY + 3 + 4 * t)) <= thickness / 2 * (1 - 0.5 * t)
        }
    }

    private func linerFeedback(_ worn: Shape?, look: LinerLook = .cat) throws -> MakeupFeedback {
        let input = LineFeedbackInput(before: scan(shown: liner(), darkness: 40), hadBeforePhoto: true,
                                      after: scan(worn: worn, wornDarkness: 40), look: look.rawValue)
        return EyelinerFeedback.evaluate(input, database: try database(), language: .en)
    }

    func testLinerOnTargetIsPraised() throws {
        let feedback = try linerFeedback(liner())
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(feedback.score), 0.9, "\(feedback.items.map(\.rule))")
        XCTAssertTrue(feedback.items.contains { $0.rule == "eyeliner.praise.line" }, "\(feedback.items.map(\.rule))")
    }

    func testShortWingIsNamed() throws {
        let feedback = try linerFeedback(liner(wing: 2))
        XCTAssertTrue(feedback.items.contains { $0.rule == "eyeliner.wing.too_short" }, "\(feedback.items.map(\.rule))")
    }

    func testThickLinerIsNamed() throws {
        let feedback = try linerFeedback(liner(thickness: 4))
        XCTAssertTrue(feedback.items.contains { $0.rule == "eyeliner.thickness.too_thick" }, "\(feedback.items.map(\.rule))")
    }

    func testNoLinerSaysSo() throws {
        XCTAssertEqual(try linerFeedback(nil).items.first?.rule, "eyeliner.none")
    }

    func testNaturalLookHasNoWingRules() throws {
        let feedback = try linerFeedback(liner(wing: 2), look: .natural)
        XCTAssertFalse(feedback.items.contains { $0.rule.hasPrefix("eyeliner.wing") }, "\(feedback.items.map(\.rule))")
    }

    func testClosedEyesStopTheLinerCheck() throws {
        var after = scan(worn: liner(), wornDarkness: 40)
        after.blink = 0.8
        let input = LineFeedbackInput(before: scan(shown: liner(), darkness: 40), hadBeforePhoto: true, after: after, look: "cat")
        let feedback = EyelinerFeedback.evaluate(input, database: try database(), language: .en)
        XCTAssertNil(feedback.score)
        XCTAssertEqual(feedback.items.map(\.rule), ["capture.eyes_closed"])
    }

    func testEveryLineMessageHasItsPlaceholdersFilled() throws {
        for worn in [brow(headX: 10, tailX: 64, lift: 3, thick: 1.6), brow(tailX: 45, thick: 0.6)] {
            for item in try browFeedback(worn).items { XCTAssertFalse(item.say.contains("{"), item.say) }
        }
        for worn in [liner(start: 24, wing: 1, thickness: 3), liner(start: 14, wing: 11, thickness: 0.8)] {
            for item in try linerFeedback(worn).items { XCTAssertFalse(item.say.contains("{"), item.say) }
        }
    }
}
