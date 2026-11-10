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
    private func reading(in oval: CGRect, offAxis: Double = 0, roll: Double = 0, nose: CGVector = .zero,
                         gaze: Double = 0) -> CapturePoseReading {
        let outline = (0..<24).map { i -> CGPoint in
            let t = Double(i) / 24 * 2 * .pi
            return CGPoint(x: oval.midX + oval.width / 2 * cos(t), y: oval.midY + oval.height / 2 * sin(t))
        }
        return CapturePoseReading(outline: outline, offAxisDegrees: offAxis, rollDegrees: roll, noseOffset: nose, gazeDegrees: gaze,
                                  eyes: EyePair(left: CGPoint(x: oval.midX - 40, y: oval.midY), right: CGPoint(x: oval.midX + 40, y: oval.midY)))
    }

    func testCapturePositionAcceptsAFaceFillingTheOval() {
        let oval = CapturePoseCheck.oval(in: CGSize(width: 402, height: 874))
        let result = CapturePoseCheck.evaluate(reading(in: oval), oval: oval, wasAligned: false)
        XCTAssertTrue(result.aligned)
        XCTAssertEqual(result.hint, .ready)
    }

    func testCapturePositionTellsWhatToFix() {
        let oval = CapturePoseCheck.oval(in: CGSize(width: 402, height: 874))
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval.insetBy(dx: 40, dy: 50)), oval: oval, wasAligned: false).hint, .closer)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval.insetBy(dx: -40, dy: -50)), oval: oval, wasAligned: false).hint, .farther)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval.offsetBy(dx: 60, dy: 0)), oval: oval, wasAligned: false).hint, .left)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval, offAxis: 15, nose: CGVector(dx: -20, dy: 2)), oval: oval,
                                                 wasAligned: false).hint, .turnRight)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval, offAxis: 15, nose: CGVector(dx: 1, dy: 18)), oval: oval,
                                                 wasAligned: false).hint, .chinUp)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval, roll: 10), oval: oval, wasAligned: false).hint, .straighten)
        XCTAssertEqual(CapturePoseCheck.evaluate(reading(in: oval, gaze: 20), oval: oval, wasAligned: false).hint, .lookAtCamera)
    }

    func testCapturePositionDoesNotFlickerOnTheEdge() {
        let oval = CapturePoseCheck.oval(in: CGSize(width: 402, height: 874))
        let edge = reading(in: oval, offAxis: 5.5)
        XCTAssertFalse(CapturePoseCheck.evaluate(edge, oval: oval, wasAligned: false).aligned)
        XCTAssertTrue(CapturePoseCheck.evaluate(edge, oval: oval, wasAligned: true).aligned)
    }

    func testResultPhotoMustMatchTheDesiredPose() {
        let oval = CapturePoseCheck.oval(in: CGSize(width: 402, height: 874))
        var desired = reading(in: oval)
        desired.distance = 0.32; desired.centre = CGPoint(x: oval.midX, y: oval.midY)
        var same = desired
        XCTAssertTrue(CapturePoseCheck.evaluate(same, oval: oval, wasAligned: false, reference: desired).aligned)
        same.distance = 0.345 + 0.01
        XCTAssertEqual(CapturePoseCheck.evaluate(same, oval: oval, wasAligned: false, reference: desired).hint, .closer)
        var turned = desired
        turned.orientation = simd_quatf(angle: 6 * .pi / 180, axis: SIMD3(0, 1, 0))
        turned.noseOffset = CGVector(dx: -6, dy: 0)
        XCTAssertEqual(CapturePoseCheck.evaluate(turned, oval: oval, wasAligned: false, reference: desired).hint, .turnRight)
    }

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
                                             (.blush, GuidedTutorialModel.blushLessons.count)]
        for (tab, count) in lessons {
            for step in 0..<count {
                let name = TutorialStepsSheet.imageName(tab: tab, step: step)
                XCTAssertNotNil(name.flatMap { UIImage(named: $0) }, "\(tab) step \(step + 1) has no picture")
            }
            XCTAssertNil(TutorialStepsSheet.imageName(tab: tab, step: count))
        }
    }
}
