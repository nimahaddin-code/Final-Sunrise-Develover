// -Nimah: Ownership routing regressions replace removed Khalish brow/blush catalog expectations.
import XCTest
@testable import SunriseApp
final class MakeupRecommenderTests:XCTestCase {
    func testHanumCatalogContainsOnlyEyeliner() {
        for shape in FaceShape.allCases {
            let items=MakeupRecommender.recommendations(for:shape)
            XCTAssertFalse(items.isEmpty)
            XCTAssertTrue(items.allSatisfy { $0.category == .eyeliner })
            XCTAssertEqual(Set(items.map(\.id)).count,items.count)
            XCTAssertTrue(MakeupRecommender.recommendations(for:shape,in:.eyebrow).isEmpty)
            XCTAssertTrue(MakeupRecommender.recommendations(for:shape,in:.blush).isEmpty)
            XCTAssertTrue(MakeupPlan(shape:shape).recommendations.allSatisfy { $0.category == .eyeliner })
        }
    }
    func testEyelinerDoesNotDependOnFaceShape() {
        let ids=FaceShape.allCases.map { MakeupRecommender.recommendations(for:$0,in:.eyeliner).map(\.id) }
        XCTAssertEqual(Set(ids).count,1)
        XCTAssertEqual(ids[0],EyeShape.allCases.map { "liner.eye.\($0.rawValue)" }+["liner.eye.neutral"])
    }
    @MainActor func testStaleLegacyRequestCannotActivateBrowBlush() {
        let old=MakeupRecommendation(id:"old.brow",name:"Old",detail:"",style:.eyebrow(BrowStyle(archPosition:0.6,archHeight:0.1,thickness:0.2,tailExtension:0,angularity:0,shade:MakeupPalette.taupe)))
        let model=MakeupTryOnViewModel(plan:MakeupPlan(shape:.oval),applied:[old])
        XCTAssertTrue(model.selection.isEmpty)
        model.select(old,in:.eyebrow)
        XCTAssertTrue(model.selection.isEmpty)
    }
    @MainActor func testNimahStudioReusesScanAndOpensRequestedRegion() {
        let model=EyebrowViewModel(checker:MockFaceTrackingChecker(),assessment:.init(shape:.oval,origin:.analysis,confidence:0.8),initialRegion:.blush)
        model.nextAfterScan()
        XCTAssertEqual(model.phase,.chooseStyle)
        XCTAssertEqual(model.configuration.region,.blush)
        XCTAssertFalse(model.blushOptions.isEmpty)
        XCTAssertEqual(model.assessment.origin,.analysis)
        model.chooseFaceShape(.round)
        XCTAssertEqual(model.phase,.chooseStyle)
        XCTAssertEqual(model.configuration.region,.blush)
        XCTAssertEqual(model.assessment.origin,.manual)
    }
    @MainActor func testChosenShadeOutlivesSwitchingLinerStyles() {
        let items=MakeupRecommender.recommendations(for:.round,in:.eyeliner)
        let model=MakeupTryOnViewModel(plan:MakeupPlan(shape:.round),applied:[])
        model.select(MakeupPalette.navy,in:.eyeliner)
        model.select(items[1],in:.eyeliner)
        XCTAssertEqual(model.shade(for:.eyeliner),MakeupPalette.navy)
        model.stop()
    }
    func testLinerRecoloringKeepsShape() {
        let style=EyelinerPlanner.catalog[0].style
        XCTAssertEqual(style.with(shade:MakeupPalette.navy).with(shade:style.shade),style)
    }
}
