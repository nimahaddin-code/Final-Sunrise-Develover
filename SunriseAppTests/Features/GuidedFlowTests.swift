// -Nimah: Phase 0 of the guided flow: each tool's info, and the routes between the new screens.
import XCTest
@testable import SunriseApp

final class GuidedFlowTests: XCTestCase {
    private func handoff(enabled: Set<TryOnTool>) -> TutorialHandoff {
        var value = TutorialHandoff(tool: .blush, shades: [:], intensities: [:])
        value.enabled = enabled
        value.blushStyle = BlushPlacementStyle.referenceLooks.first
        value.browOverlay = BrowOverlay.all.first
        return value
    }

    func testEveryToolGivesItsLookAndSomethingToPrepare() {
        let all = handoff(enabled: Set(TryOnTool.allCases))
        for tool in TryOnTool.allCases {
            let info = ToolInfo.of(tool, handoff: all)
            XCTAssertEqual(info.tool, tool)
            XCTAssertFalse(info.lookName.isEmpty, "\(tool)")
            XCTAssertFalse(info.lookDescription.isEmpty, "\(tool)")
            XCTAssertFalse(info.tools.isEmpty && info.products.isEmpty, "\(tool) lists nothing to prepare")
            XCTAssertGreaterThan(info.minutes, 0, "\(tool)")
            XCTAssertTrue((info.tools + info.products).contains(where: \.required), "\(tool) has nothing required")
            XCTAssertFalse(info.tools.contains(where: \.showsShade), "\(tool): only products show the shade")
            XCTAssertEqual(Set((info.tools + info.products).map(\.id)).count, info.tools.count + info.products.count,
                           "\(tool) repeats an item")
        }
        XCTAssertEqual(ToolInfo.of(.blush, handoff: all).lookName, all.blushStyle?.title)
        XCTAssertEqual(ToolInfo.of(.eyebrow, handoff: all).lookName, all.browOverlay?.title)
    }

    // MARK: Feedback v1: the blush target area on the result photo

    private let outline = BlushGuideSnapshot(cheeks: [
        .init(inner: [CGPoint(x: 40, y: 80), CGPoint(x: 60, y: 80), CGPoint(x: 60, y: 100)],
              outer: [CGPoint(x: 20, y: 60), CGPoint(x: 100, y: 60), CGPoint(x: 100, y: 140), CGPoint(x: 20, y: 140)],
              center: CGPoint(x: 50, y: 90), outward: CGPoint(x: 90, y: 70))
    ])

    func testBlushOutlineIsKeptInThePhotosOwnCoordinates() throws {
        let n = try XCTUnwrap(outline.normalized(in: CGSize(width: 200, height: 400)))
        XCTAssertEqual(n.cheeks[0].outer[2], CGPoint(x: 0.5, y: 0.35))
        XCTAssertEqual(n.cheeks[0].center, CGPoint(x: 0.25, y: 0.225))
        XCTAssertNil(outline.normalized(in: .zero), "no view size: no outline rather than a division by zero")
    }

    func testBlushOutlineIsDrawnOnThePictureAtAnySize() throws {
        let n = try XCTUnwrap(outline.normalized(in: CGSize(width: 200, height: 400)))
        // The photo shown at half size and moved: the outer line must land on the same part of the picture.
        let paths = n.paths(in: CGRect(x: 10, y: 20, width: 100, height: 200))
        XCTAssertEqual(paths.count, 2, "the small circle and the outer line")
        let box = paths[1].boundingRect
        XCTAssertEqual(box.minX, 20, accuracy: 0.001); XCTAssertEqual(box.maxX, 60, accuracy: 0.001)
        XCTAssertEqual(box.minY, 50, accuracy: 0.001); XCTAssertEqual(box.maxY, 90, accuracy: 0.001)
    }

    @MainActor func testPhotoMeasuresTheBlushAreaWithoutDrawingBlush() {
        let model = GuidedTutorialModel(checker: MockFaceTrackingChecker(), assessment: .init(shape: .heart, origin: .analysis),
            plan: MakeupPlan(shape: .heart),
            handoff: .init(tool: .eyeliner, shades: [:], intensities: [:], blushStyle: .lifted, enabled: [.blush, .eyeliner]))
        XCTAssertTrue(model.measuresBlushInPhoto, "blush was on and has a placement: from any tab, here the eyeliner")
        model.enterPhoto()
        let photo = model.liveConfiguration
        XCTAssertEqual(photo.pigmentHalf, PigmentHalf.none, "the photo is the plain camera: no blush pigment")
        XCTAssertTrue(photo.showGuide && photo.showMakeupPreview, "the engine keeps measuring the target outlines")
        XCTAssertEqual(photo.region, .blush); XCTAssertEqual(photo.blushStyle, .lifted)
        XCTAssertFalse(photo.browLayer.on || photo.blushLayer.on); XCTAssertNil(photo.browOverlay)
        model.deactivate()
    }

    @MainActor func testPhotoWithoutBlushStaysAPlainCamera() {
        let model = GuidedTutorialModel(checker: MockFaceTrackingChecker(), assessment: .init(shape: .heart, origin: .analysis),
            plan: MakeupPlan(shape: .heart),
            handoff: .init(tool: .eyebrow, shades: [:], intensities: [:], enabled: [.eyebrow]))
        model.enterPhoto()
        XCTAssertFalse(model.measuresBlushInPhoto)
        XCTAssertFalse(model.liveConfiguration.showMakeupPreview, "no blush on Try On: the photo does not run the makeup engine")
        model.deactivate()
    }

    /// A picture name with no asset would show an empty card instead of the symbol.
    func testEveryItemPictureIsInTheAssets() {
        for tool in TryOnTool.allCases {
            let info = ToolInfo.of(tool, handoff: handoff(enabled: Set(TryOnTool.allCases)))
            for name in (info.tools + info.products).compactMap(\.imageName) {
                XCTAssertNotNil(UIImage(named: name), "\(tool): no asset named \(name)")
            }
        }
    }

    func testEachBlushLookHasItsOwnDescription() {
        let descriptions = BlushPlacementStyle.referenceLooks.map { style -> String in
            var value = handoff(enabled: [.blush])
            value.blushStyle = style
            return ToolInfo.of(.blush, handoff: value).lookDescription
        }
        XCTAssertEqual(Set(descriptions).count, BlushPlacementStyle.referenceLooks.count)
    }

    func testOnlyToolsWithMakeupOnAreShownInTryOnOrder() {
        let chosen = ToolInfo.chosen(in: handoff(enabled: [.eyebrow, .blush]))
        XCTAssertEqual(chosen.map(\.tool), TryOnTool.allCases.filter { [.eyebrow, .blush].contains($0) })
        XCTAssertTrue(ToolInfo.chosen(in: handoff(enabled: [])).isEmpty)
    }

    @MainActor func testNewFlowRoutesStackInOrderAndReturnToTryOn() {
        let navigator = AppNavigator(defaults: UserDefaults(suiteName: "GuidedFlowTests")!)
        let value = handoff(enabled: [.blush])
        let feedback = AppRoute.feedback(FeedbackInput(handoff: value, photo: TutorialPhoto(image: UIImage(), blushOutline: nil)))
        for route in [AppRoute.comparison(value), .preparation(value), .recommendedTutorial(value), feedback] {
            navigator.open(route, in: .tryOn)
        }
        XCTAssertEqual(navigator.tryOnPath.count, 4)
        XCTAssertEqual(navigator.tryOnPath.last, feedback)
        navigator.returnToRoot(of: .tryOn)
        XCTAssertTrue(navigator.tryOnPath.isEmpty)
    }

    func testNewFlowIsOffUnlessSwitchedOn() {
        XCTAssertFalse(UserDefaults(suiteName: "GuidedFlowTests.fresh")!.bool(forKey: NewFlow.key))
    }
}
