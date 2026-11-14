// -Nimah: Phase 0 of the guided flow: each tool's info, and the switch for the entry screens.
import XCTest
import simd
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

// MARK: Capture position

extension GuidedFlowTests {
    func testMeshHomographyRecoversAPerspectiveShift() throws {
        let truth = FaceHomography(h: [1.04, 0.02, -6, -0.015, 0.98, 9, 0.00004, -0.00003])
        let source = (0..<60).map { i in CGPoint(x: 100 + Double(i % 10) * 20, y: 250 + Double(i / 10) * 30) }
        let target = source.map(truth.apply)
        let fitted = try XCTUnwrap(FaceHomography.fit(from: source, to: target))
        for (p, q) in zip(source, target) {
            let m = fitted.apply(p)
            XCTAssertEqual(m.x, q.x, accuracy: 0.01); XCTAssertEqual(m.y, q.y, accuracy: 0.01)
        }
        XCTAssertTrue(fitted.isGentle(for: CGSize(width: 402, height: 874)))
        XCTAssertNil(FaceHomography.fit(from: Array(source.prefix(5)), to: Array(target.prefix(5))))
    }

    func testResultPhotoIsLinedUpByTheEyes() throws {
        let target = EyePair(left: CGPoint(x: 150, y: 300), right: CGPoint(x: 250, y: 300))
        let shot = EyePair(left: CGPoint(x: 160, y: 320), right: CGPoint(x: 255, y: 324))
        let transform = try XCTUnwrap(shot.transform(onto: target))
        let left = shot.left.applying(transform), right = shot.right.applying(transform)
        XCTAssertEqual(left.x, target.left.x, accuracy: 0.01); XCTAssertEqual(left.y, target.left.y, accuracy: 0.01)
        XCTAssertEqual(right.x, target.right.x, accuracy: 0.01); XCTAssertEqual(right.y, target.right.y, accuracy: 0.01)
        // A very different pose is left alone rather than warped.
        XCTAssertNil(EyePair(left: CGPoint(x: 100, y: 300), right: CGPoint(x: 160, y: 300)).transform(onto: target))
    }
}

// MARK: Tutorial step pictures

extension GuidedFlowTests {
    func testEveryTutorialStepHasItsPicture() {
        let lessons: [(TutorialTab, Int)] = [(.brows, GuidedTutorialModel.browLessons.count),
                                             (.eyeliner, GuidedTutorialModel.linerLessons.count),
                                             (.blush, GuidedTutorialModel.blushLessons.count),
                                             (.lips, GuidedTutorialModel.lipLessons.count)]
        for (tab, count) in lessons {
            for step in 0..<count {
                let name = TutorialStepsSheet.imageName(tab: tab, step: step)
                XCTAssertNotNil(name.flatMap { UIImage(named: $0) }, "\(tab) step \(step + 1) has no picture")
            }
            XCTAssertNil(TutorialStepsSheet.imageName(tab: tab, step: count))
        }
    }
}

// MARK: Eyeliner tutorial, wing or no wing

extension GuidedFlowTests {
    private func guide(withTip: Bool) -> LinerGuide {
        let lash = (0..<8).map { CGPoint(x: 100 + Double($0) * 10, y: 200 - Double($0)) }
        let edge = lash.reversed().map { CGPoint(x: $0.x, y: $0.y - 6) }
        let tip = CGPoint(x: 200, y: 180)
        return LinerGuide(upperLiner: lash + edge, tightline: [], wing: withTip ? [lash[7], tip] : [], lowerLiner: [],
                          outlines: [lash + edge],
                          anchors: LinerAnchors(innerCorner: lash[0], outerCorner: lash[7], upperStart: lash[0],
                                                wingRoot: withTip ? lash[7] : nil, wingTip: withTip ? tip : nil))
    }

    func testEyelinerLooksAreGroupedByWing() {
        XCTAssertEqual(LinerLook.allCases.filter { !$0.hasWing }, [.arabian, .natural])
        XCTAssertEqual(LinerLook.offered, [.cat, .classic, .kitten, .puppy])
        XCTAssertTrue(LinerLook.offered.allSatisfy(\.hasWing))
    }

    func testWingedTutorialMarksOnlyTheWingTriangle() {
        let geometry = LinerStepGeometry(guide(withTip: true), wing: true)
        XCTAssertEqual(geometry.dots.count, 3)
        XCTAssertEqual(geometry.dots[1], CGPoint(x: 200, y: 180), "the wing's end")
        XCTAssertEqual(geometry.tipIndex, 1)
        // The outline follows the eye (curved edges), so it has more points than the three dots.
        XCTAssertGreaterThan(geometry.shapes[0].count, 3)
        XCTAssertEqual(geometry.shapes[0].first, geometry.dots[0])
    }

    func testNoWingTutorialMarksOnlyTheLashCurve() {
        let geometry = LinerStepGeometry(guide(withTip: true), wing: false)
        XCTAssertEqual(geometry.dots.count, 4)
        XCTAssertFalse(geometry.dots.contains(CGPoint(x: 200, y: 180)), "no dot toward a wing")
        XCTAssertNil(geometry.tipIndex)
    }

    /// -Nimah, device test 2026-11-13: the desired-look photo came out without the blush. Its shutter waits for a picture with
    /// the makeup on the face; a plain read (the result photo) takes the next picture.
    func testDesiredShutterWaitsForAPictureWithTheMakeup() {
        let desired = ScreenReader(needsMakeup: true) { _ in }
        let plain = ScreenReader { _ in }
        let early = ScreenReader.split([desired, plain], makeup: false)
        XCTAssertTrue(early.now.count == 1 && early.now[0] === plain)
        XCTAssertTrue(early.waiting.count == 1 && early.waiting[0] === desired)
        let drawn = ScreenReader.split(early.waiting, makeup: true)
        XCTAssertTrue(drawn.now.count == 1 && drawn.now[0] === desired)
        XCTAssertTrue(drawn.waiting.isEmpty)
    }
}
