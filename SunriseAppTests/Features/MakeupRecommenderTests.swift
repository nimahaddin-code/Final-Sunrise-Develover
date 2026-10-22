import XCTest
@testable import SunriseApp

final class MakeupRecommenderTests: XCTestCase {
    func testEveryShapeGetsEyebrowBlushAndEyelinerOnly() {
        for shape in FaceShape.allCases {
            let recommendations = MakeupRecommender.recommendations(for: shape)
            XCTAssertEqual(Set(recommendations.map(\.category)), Set(MakeupCategory.allCases), "\(shape)")
            for category in MakeupCategory.allCases {
                XCTAssertGreaterThanOrEqual(MakeupRecommender.recommendations(for: shape, in: category).count, 2)
            }
        }
    }

    func testRecommendationsAreGroupedByCategoryWithoutDuplicates() {
        for shape in FaceShape.allCases {
            let recommendations = MakeupRecommender.recommendations(for: shape)
            XCTAssertEqual(Set(recommendations.map(\.id)).count, recommendations.count, "\(shape)")
            let order = recommendations.map(\.category).map { MakeupCategory.allCases.firstIndex(of: $0)! }
            XCTAssertEqual(order, order.sorted(), "\(shape)")
        }
    }

    func testBestMatchFollowsFaceShapeGuidance() {
        XCTAssertEqual(MakeupRecommender.recommendations(for: .round, in: .eyebrow).first?.id, "brow.highArch")
        XCTAssertEqual(MakeupRecommender.recommendations(for: .oblong, in: .blush).first?.id, "blush.horizontal")
        XCTAssertEqual(MakeupRecommender.recommendations(for: .square, in: .blush).first?.id, "blush.apples")
    }

    @MainActor func testTryOnStartsWithRequestedLooksOnePerCategory() {
        let blush = MakeupRecommender.recommendations(for: .heart, in: .blush)
        let brow = MakeupRecommender.recommendations(for: .heart, in: .eyebrow)[0]
        let model = MakeupTryOnViewModel(plan: MakeupPlan(shape: .heart), applied: [blush[0], brow, blush[1]])
        XCTAssertEqual(model.selection[.blush], blush[1])
        XCTAssertEqual(model.selection[.eyebrow], brow)
        XCTAssertNil(model.selection[.eyeliner])
        model.select(nil, in: .blush)
        XCTAssertNil(model.selection[.blush])
    }

    func testEveryRecommendedShadeIsInItsCategoryPalette() {
        for shape in FaceShape.allCases {
            for recommendation in MakeupRecommender.recommendations(for: shape) {
                XCTAssertTrue(MakeupPalette.shades(for: recommendation.category).contains(recommendation.style.shade),
                              recommendation.id)
            }
        }
    }

    func testChangingShadeKeepsTheStyleShape() {
        let style = MakeupRecommender.recommendations(for: .oval, in: .eyebrow)[0].style
        let recoloured = style.with(shade: MakeupPalette.darkBrown)
        XCTAssertEqual(recoloured.shade, MakeupPalette.darkBrown)
        guard case .eyebrow(let before) = style, case .eyebrow(let after) = recoloured else {
            return XCTFail("Expected eyebrow styles")
        }
        XCTAssertEqual(after.archHeight, before.archHeight)
        XCTAssertEqual(after.archPosition, before.archPosition)
    }

    @MainActor func testChosenShadeOutlivesSwitchingStyles() {
        let liners = MakeupRecommender.recommendations(for: .round, in: .eyeliner)
        let model = MakeupTryOnViewModel(plan: MakeupPlan(shape: .round), applied: [liners[0]])
        XCTAssertEqual(model.shade(for: .eyeliner), liners[0].style.shade)
        model.select(MakeupPalette.navy, in: .eyeliner)
        model.select(liners[1], in: .eyeliner)
        XCTAssertEqual(model.shade(for: .eyeliner), MakeupPalette.navy)
        XCTAssertNil(model.shade(for: .blush))
    }

    @MainActor func testIntensityDefaultsAndIsClamped() {
        let model = MakeupTryOnViewModel(plan: MakeupPlan(shape: .oval), applied: [])
        XCTAssertEqual(model.intensity(for: .blush), MakeupTextureRenderer.defaultIntensity)
        model.setIntensity(1.4, for: .blush)
        XCTAssertEqual(model.intensity(for: .blush), 1)
        model.setIntensity(-1, for: .eyebrow)
        XCTAssertEqual(model.intensity(for: .eyebrow), 0)
        XCTAssertFalse(model.hasMakeup, "Nothing is drawn before the face is located")
    }
}
