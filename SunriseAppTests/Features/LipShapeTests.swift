import XCTest
@testable import SunriseApp

/// The lipstick shapes on a synthetic mouth: what each style covers. No camera needed.
final class LipShapeTests: XCTestCase {
    /// A mouth 100 points wide at (200, 300): both rings are ellipses, starting at the left end of the screen, upper lip first.
    private func frame() -> LipOverlayFrame {
        func ring(_ halfWidth: CGFloat, _ halfHeight: CGFloat) -> [CGPoint] {
            (0..<LipLandmarks.ringCount).map { index in
                let angle = CGFloat.pi + 2 * CGFloat.pi * CGFloat(index) / CGFloat(LipLandmarks.ringCount)
                return CGPoint(x: 200 + halfWidth * cos(angle), y: 300 + halfHeight * sin(angle))
            }
        }
        return LipOverlayFrame(outer: ring(50, 20), inner: ring(40, 4), receivedAt: 0)
    }

    private let shade = MakeupPalette.lipShades[0]

    func testProviderRingsMatchTheRingLayout() {
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipOuterIndices.count, LipLandmarks.ringCount)
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipInnerIndices.count, LipLandmarks.ringCount)
        // The corners, the cupid's bow's dip and the lower lip's middle sit where the overlay expects them.
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipOuterIndices[LipOverlayFrame.rightCorner], 61)
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipOuterIndices[LipOverlayFrame.upperMiddle], 0)
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipOuterIndices[LipOverlayFrame.leftCorner], 291)
        XCTAssertEqual(MediaPipeEyeLandmarkProvider.lipOuterIndices[LipOverlayFrame.lowerMiddle], 17)
        XCTAssertEqual(Set(MediaPipeEyeLandmarkProvider.lipOuterIndices + MediaPipeEyeLandmarkProvider.lipInnerIndices).count, 40)
    }

    func testNaturalCoversTheLipsAndLeavesTheMouthOpen() {
        let layers = LipShape.layers(frame(), style: .natural, shade: shade, intensity: 1)
        XCTAssertEqual(layers.count, 1)
        let lips = layers[0].path
        XCTAssertTrue(lips.contains(CGPoint(x: 200, y: 288), using: .evenOdd), "upper lip")
        XCTAssertTrue(lips.contains(CGPoint(x: 200, y: 312), using: .evenOdd), "lower lip")
        XCTAssertFalse(lips.contains(CGPoint(x: 200, y: 300), using: .evenOdd), "mouth opening")
        XCTAssertFalse(lips.contains(CGPoint(x: 200, y: 325), using: .evenOdd), "below the lips")
    }

    func testFullReachesPastTheLipLineInTheMiddleOnly() {
        let frame = frame()
        let natural = LipShape.edge(frame, style: .natural), full = LipShape.edge(frame, style: .full)
        XCTAssertEqual(natural, frame.outer)
        XCTAssertLessThan(full[LipOverlayFrame.upperMiddle].y, natural[LipOverlayFrame.upperMiddle].y - 2)
        XCTAssertGreaterThan(full[LipOverlayFrame.lowerMiddle].y, natural[LipOverlayFrame.lowerMiddle].y + 2)
        XCTAssertEqual(full[LipOverlayFrame.rightCorner].x, natural[LipOverlayFrame.rightCorner].x, accuracy: 0.01)
        XCTAssertEqual(full[LipOverlayFrame.leftCorner].y, natural[LipOverlayFrame.leftCorner].y, accuracy: 0.01)
    }

    func testGradientIsStrongInTheMiddleAndFaintAtTheEdge() {
        let layers = LipShape.layers(frame(), style: .gradient, shade: shade, intensity: 1)
        XCTAssertEqual(layers.count, 2)
        XCTAssertLessThan(layers[0].alpha, layers[1].alpha * 0.5)
        // The strong middle stops short of the lip's edge, and is kept inside the lips.
        XCTAssertTrue(layers[1].path.contains(CGPoint(x: 200, y: 308), using: .evenOdd))
        XCTAssertFalse(layers[1].path.contains(CGPoint(x: 200, y: 317), using: .evenOdd))
        XCTAssertNotNil(layers[1].clip)
    }

    func testNothingIsDrawnAtZeroStrength() {
        XCTAssertTrue(LipShape.layers(frame(), style: .natural, shade: shade, intensity: 0).isEmpty)
    }

    func testLipsFollowTheHeadBetweenDetectorResults() {
        let lips = LipLandmarks(outer: frame().outer, inner: frame().inner)
        let from = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 10)]
        let moved = LipOverlayModel.moved(lips, from: from, to: from.map { CGPoint(x: $0.x + 7, y: $0.y - 3) })
        XCTAssertEqual(moved.outer[0].x, lips.outer[0].x + 7, accuracy: 0.001)
        XCTAssertEqual(moved.inner[5].y, lips.inner[5].y - 3, accuracy: 0.001)
        // A broken reading (the head ten times bigger) leaves the lips where they were.
        XCTAssertEqual(LipOverlayModel.moved(lips, from: from, to: from.map { CGPoint(x: $0.x * 10, y: $0.y * 10) }), lips)
    }

    func testTheSplitRunsThroughTheMiddleOfTheLips() {
        XCTAssertEqual(frame().splitX, 200, accuracy: 0.001)
        XCTAssertEqual(frame().width, 100, accuracy: 0.001)
    }

    @MainActor func testLipsRunThroughTheFlowLikeTheOtherTools() {
        XCTAssertEqual(TutorialTab(tool: .lips), .lips)
        XCTAssertEqual(TutorialTab.lips.tool, .lips)
        XCTAssertEqual(GuidedTutorialModel.lipLessons.count, 3)
        var handoff = TutorialHandoff(tool: .lips, shades: [:], intensities: [:])
        handoff.lipStyle = .gradient
        XCTAssertEqual(ToolInfo.of(.lips, handoff: handoff).lookName, LipStyle.gradient.title)
        XCTAssertTrue(handoff.styleTitle.contains(LipStyle.gradient.title))
        XCTAssertEqual(MakeupPalette.shades(for: .lips), MakeupPalette.lipShades)
    }
}
