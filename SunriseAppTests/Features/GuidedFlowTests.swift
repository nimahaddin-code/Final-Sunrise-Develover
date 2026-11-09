// -Nimah: Phase 0 of the guided flow: each tool's info, and the switch for the entry screens.
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

    /// A picture name with no asset would show an empty card instead of the symbol.
    func testEveryItemPictureIsInTheAssets() {
        for tool in TryOnTool.allCases {
            let info = ToolInfo.of(tool, handoff: handoff(enabled: Set(TryOnTool.allCases)))
            for name in (info.tools + info.products).compactMap(\.imageName) {
                XCTAssertNotNil(UIImage(named: name), "\(tool): no asset named \(name)")
            }
        }
    }

    /// The get-ready page's item pictures (`TryOnTool.mustHave` / `nearby`) are in the assets.
    func testEveryKitItemPictureIsInTheAssets() {
        for tool in TryOnTool.allCases {
            for item in tool.mustHave + tool.nearby {
                guard let name = item.info?.imageName else { continue }
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

    /// Device test 2026-11-09: the desired-look photo had no blush. `apply` ran while the brow model was still loading and
    /// dropped blush; the layer now turns on as soon as the placement is known.
    @MainActor func testDesiredLookKeepsBlushOnBeforeTheModelHasLoaded() {
        let home = TryOnHomeModel(tool: .blush, plan: MakeupPlan(shape: .heart), assessment: .init(shape: .heart, origin: .analysis),
                                  checker: MockFaceTrackingChecker())
        home.apply(TutorialHandoff(tool: .blush, shades: [:], intensities: [:], blushStyle: .lifted, enabled: [.blush]))
        XCTAssertTrue(home.enabled.contains(.blush))
        home.deactivate()
    }

    func testAPhoneHeldABitLowIsANoteNotARetake() throws {
        let database = try XCTUnwrap(FeedbackDatabase.load())
        let composer = FeedbackComposer(database: database, language: .en)
        func scan(pitch: Float) -> FaceScan {
            FaceScan(samples: [], yaw: 0, pitch: pitch, roll: 0, blink: 0, smile: 0, jawOpen: 0, browRaise: 0, ipd: 63, eyeY: 30,
                     outline: nil, viewport: .zero)
        }
        let slight = FeedbackPhotoCheck(before: scan(pitch: 0), after: scan(pitch: 9), tool: "blush", composer: composer)
        XCTAssertTrue(slight.blocking.isEmpty)
        XCTAssertEqual(slight.notes.map(\.rule), ["capture.tilted_up_down", "capture.pose_mismatch"])
        let steep = FeedbackPhotoCheck(before: scan(pitch: 0), after: scan(pitch: 20), tool: "blush", composer: composer)
        XCTAssertEqual(steep.blocking.map(\.rule), ["capture.tilted_up_down"])
    }

    func testOnlyToolsWithMakeupOnAreShownInTryOnOrder() {
        let chosen = ToolInfo.chosen(in: handoff(enabled: [.eyebrow, .blush]))
        XCTAssertEqual(chosen.map(\.tool), TryOnTool.allCases.filter { [.eyebrow, .blush].contains($0) })
        XCTAssertTrue(ToolInfo.chosen(in: handoff(enabled: [])).isEmpty)
    }

    func testNewFlowIsOffUnlessSwitchedOn() {
        XCTAssertFalse(UserDefaults(suiteName: "GuidedFlowTests.fresh")!.bool(forKey: NewFlow.key))
    }
}
