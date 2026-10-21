import XCTest
@testable import SunriseApp

final class EyelinerPlannerTests: XCTestCase {
    private func eyes(tilt: Float = 4, spacing: Float = 1, openness: Float = 0.25,
                      lid: LidType = .neither) -> EyeScan {
        EyeScan(tiltLeft: tilt, tiltRight: tilt, spacing: spacing, openness: openness, samples: 8, lidType: lid)
    }

    private let classifier = FaceShapeClassifier(reference: FaceProportions(length: 1.2, forehead: 0.85, jaw: 0.8, chin: 0.5))

    // MARK: Choice by eye shape

    func testPlainEyesGetTheAlmondLiner() {
        let plan = EyelinerPlanner.plan(for: eyes())
        XCTAssertEqual(plan.primary, .almond)
        XCTAssertFalse(plan.isNeutral)
        XCTAssertEqual(plan.style, EyelinerPlanner.variant(for: .almond))
    }

    func testEachChosenLidTypeLeadsWhenNothingElseIsPresent() {
        XCTAssertEqual(EyelinerPlanner.plan(for: eyes(lid: .hooded)).primary, .hooded)
        XCTAssertEqual(EyelinerPlanner.plan(for: eyes(lid: .monolid)).primary, .monolid)
        XCTAssertTrue(EyelinerPlanner.plan(for: eyes(lid: .hooded)).style.tightline)
    }

    func testDownturnedWingFollowsTheLowerLashLineWithoutExtraAngle() {
        let style = EyelinerPlanner.variant(for: .downturned)
        XCTAssertEqual(style.wingAngle, 0)
        XCTAssertEqual(style.wingBase, .lowerLidTangent)
    }

    func testEveryVariantIsDrawnWithinTheResearchRanges() {
        for shape in EyeShape.allCases where shape != .wideSet {
            let style = EyelinerPlanner.variant(for: shape)
            XCTAssertGreaterThan(style.wingLength, 0, "\(shape)")
            XCTAssertLessThanOrEqual(style.wingLength, 0.40, "\(shape)")
            XCTAssertLessThanOrEqual(style.wingAngle, 20, "\(shape)")
        }
        XCTAssertEqual(EyelinerPlanner.variant(for: .wideSet).wingLength, 0)
    }

    // MARK: Combination rules

    func testContinuousValuesAreWeightedAndCategoricalValuesFollowThePrimary() {
        // Close-set (1.0) leads upturned (0.5 after the research confidence): weights 2/3 and 1/3.
        let plan = EyelinerPlanner.plan(for: eyes(tilt: 12, spacing: 0.85))
        XCTAssertEqual(plan.blend.map(\.shape), [.closeSet, .upturned])
        XCTAssertEqual(plan.blend[0].weight, 2.0 / 3, accuracy: 1e-5)
        let close = EyelinerPlanner.variant(for: .closeSet), up = EyelinerPlanner.variant(for: .upturned)
        XCTAssertEqual(plan.style.wingAngle, close.wingAngle * 2 / 3 + up.wingAngle / 3, accuracy: 1e-5)
        XCTAssertEqual(plan.style.wingLength, close.wingLength * 2 / 3 + up.wingLength / 3, accuracy: 1e-5)
        XCTAssertEqual(plan.style.wingBase, close.wingBase)
        XCTAssertTrue(plan.style.wingTargetsBrowTail)
        XCTAssertFalse(plan.style.lowerLine.enabled, "Categorical: the primary shape has no lower line")
    }

    func testR4WideSetPrimaryRemovesTheWing() {
        let plan = EyelinerPlanner.plan(for: eyes(spacing: 1.15))
        XCTAssertEqual(plan.primary, .wideSet)
        XCTAssertEqual(plan.style.wingLength, 0)
        XCTAssertEqual(plan.style.wingAngle, 0)
    }

    func testR4StrongWideSetRemovesTheWingEvenWhenAnotherShapeLeads() {
        // Monolid (0.8) leads wide-set (0.67 raw), but wide-set is present at 0.5 or more.
        let plan = EyelinerPlanner.plan(for: eyes(spacing: 1.1, lid: .monolid))
        XCTAssertEqual(plan.primary, .monolid)
        XCTAssertTrue(plan.wingRemoved)
        XCTAssertEqual(plan.style.wingLength, 0)
        XCTAssertEqual(plan.style.wingAngle, 0)
    }

    func testR4WeakWideSetKeepsTheWing() {
        // Slightly wide-set (score .33) next to clearly downturned eyes: the wing stays.
        let plan = EyelinerPlanner.plan(for: eyes(tilt: -4, spacing: 1.05))
        XCTAssertEqual(plan.primary, .downturned)
        XCTAssertFalse(plan.wingRemoved)
        XCTAssertGreaterThan(plan.style.wingLength, 0)
    }

    func testR7UnclearReadingsUseTheNaturalLine() {
        for scan in [nil, eyes(openness: 0.10), EyeScan(tiltLeft: 9, tiltRight: 1, spacing: 1, openness: 0.25, samples: 8)] {
            let plan = EyelinerPlanner.plan(for: scan)
            XCTAssertTrue(plan.isNeutral)
            XCTAssertEqual(plan.style, EyelinerPlanner.naturalLine)
            XCTAssertEqual(plan.style.wingLength, 0)
            XCTAssertTrue(plan.blend.isEmpty)
        }
    }

    // MARK: In the plan

    func testMadeForYouEyelinerComesFromTheScansEyes() {
        var scan = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
        scan.eyes = eyes(spacing: 0.85)
        let plan = MakeupPlan(scan: scan)
        let liner = plan.recommendations(in: .eyeliner)
        XCTAssertTrue(MakeupPlan.isMadeForYou(liner[0]))
        XCTAssertEqual(liner[0].style, .eyeliner(EyelinerPlanner.plan(for: scan.eyes).style))
        XCTAssertEqual(liner.count, 1 + 9, "Made for you plus one liner per eye shape and the natural line")
    }

    func testFaceShapeDoesNotChangeTheEyeliner() {
        var scan = classifier.classify(FaceProportions(length: 1.15, forehead: 0.85, jaw: 0.8, chin: 0.47))
        scan.eyes = eyes(tilt: -3)
        let first = MakeupPlan(scan: scan, chosenShape: .round).recommendations(in: .eyeliner)
        let second = MakeupPlan(scan: scan, chosenShape: .oblong).recommendations(in: .eyeliner)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.style), second.map(\.style))
    }

    func testScansWithoutEyesGetTheNaturalLine() {
        let plan = MakeupPlan(shape: .oval)
        XCTAssertTrue(plan.eyeliner.isNeutral)
        XCTAssertEqual(plan.madeForYou.last?.style, .eyeliner(EyelinerPlanner.naturalLine))
    }
}
