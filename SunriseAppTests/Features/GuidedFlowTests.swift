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

    func testBlushGetReadyPageListsTheBlushKitWithPictures() {
        let info = ToolInfo.blush(TutorialHandoff(tool: .blush, shades: [:], intensities: [:]))
        let kit = TryOnTool.blush.kit
        XCTAssertEqual(kit.map(\.id), (info.tools + info.products).map(\.id))
        XCTAssertEqual(kit.compactMap(\.imageName), ["kit-blush-sponge", "kit-blush-blush", "kit-blush-powder"])
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

    func testNewFlowIsOffUnlessSwitchedOn() {
        XCTAssertFalse(UserDefaults(suiteName: "GuidedFlowTests.fresh")!.bool(forKey: NewFlow.key))
    }
}
