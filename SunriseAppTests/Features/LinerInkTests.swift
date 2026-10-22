import CoreVideo
import XCTest
@testable import SunriseApp

final class LinerInkTests: XCTestCase {
    func testYCbCrConversion() {
        let white = LinerInk.rgb(y: 1, cb: 0.5, cr: 0.5, fullRange: true)
        XCTAssertEqual(white.red, 1, accuracy: 0.01); XCTAssertEqual(white.blue, 1, accuracy: 0.01)
        // Video range: Y 16 is black, 235 white, chroma 128 neutral.
        let black = LinerInk.rgb(y: 16.0 / 255, cb: 128.0 / 255, cr: 128.0 / 255, fullRange: false)
        XCTAssertEqual(black.luma, 0, accuracy: 0.01)
        let white2 = LinerInk.rgb(y: 235.0 / 255, cb: 128.0 / 255, cr: 128.0 / 255, fullRange: false)
        XCTAssertEqual(white2.luma, 1, accuracy: 0.01)
        // Warm skin: more red than blue when Cr is high and Cb low.
        let warm = LinerInk.rgb(y: 0.6, cb: 0.45, cr: 0.6, fullRange: true)
        XCTAssertGreaterThan(warm.red, warm.blue)
    }

    func testInkWithoutSkinIsTheShade() {
        let ink = LinerInk.color(shade: MakeupPalette.black, skin: nil)
        XCTAssertEqual(ink, InkColor(red: MakeupPalette.black.red, green: MakeupPalette.black.green, blue: MakeupPalette.black.blue))
    }

    func testInkPicksUpSomeSkinTone() {
        let skin = InkColor(red: 0.8, green: 0.6, blue: 0.5)
        let ink = LinerInk.color(shade: MakeupPalette.black, skin: skin)
        XCTAssertEqual(ink.red, 0.08 + (0.8 - 0.08) * LinerInk.skinBleed, accuracy: 1e-9)
        XCTAssertGreaterThan(ink.red, MakeupPalette.black.red)
        XCTAssertLessThan(ink.red, skin.red)
    }

    func testSkinToneIgnoresOutliers() {
        let skin = InkColor(red: 0.8, green: 0.6, blue: 0.5)
        let tone = LinerInk.skinTone(of: [skin, skin, skin, InkColor(red: 0.05, green: 0.03, blue: 0.03)])
        let t = try? XCTUnwrap(tone)
        XCTAssertEqual(t?.red ?? 0, skin.red, accuracy: 1e-9)
        XCTAssertEqual(t?.green ?? 0, skin.green, accuracy: 1e-9)
        XCTAssertEqual(t?.blue ?? 0, skin.blue, accuracy: 1e-9)
        XCTAssertNil(LinerInk.skinTone(of: []))
    }

    func testGrainIsDeterministicAndBounded() {
        let a = LinerInk.grainAlphas(), b = LinerInk.grainAlphas()
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, LinerInk.grainTileSize * LinerInk.grainTileSize)
        XCTAssertLessThanOrEqual(Double(a.max() ?? 0) / 255, LinerInk.grainDepth + 0.005)
        let mean = Double(a.reduce(0) { $0 + Int($1) }) / Double(a.count) / 255
        XCTAssertGreaterThan(mean, 0.03); XCTAssertLessThan(mean, 0.2)
        XCTAssertNotNil(LinerInk.grainTile)
    }

    func testGrainTilesCoverTheRectOnAnAnchoredGrid() {
        let rect = CGRect(x: 10, y: 20, width: 70, height: 30)
        let anchor = CGPoint(x: 5, y: 7)
        let tiles = LinerInk.grainTiles(covering: rect, anchoredAt: anchor)
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertTrue(tiles.reduce(CGRect.null) { $0.union($1) }.contains(rect))
        for tile in tiles {
            XCTAssertEqual((tile.minX - anchor.x).truncatingRemainder(dividingBy: 32), 0, accuracy: 1e-9)
        }
        XCTAssertTrue(LinerInk.grainTiles(covering: .zero, anchoredAt: .zero).isEmpty)
    }

    func testSampleSkinReadsABiplanarBuffer() throws {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 200, 200, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer)
        let pb = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pb, [])
        memset(CVPixelBufferGetBaseAddressOfPlane(pb, 0), 153, CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * 200)  // Y 0.6
        let chroma = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * 100 / 2) { chroma[i * 2] = 115; chroma[i * 2 + 1] = 153 }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let skin = try XCTUnwrap(LinerInk.sampleSkin(in: pb, aroundEyeFrom: CGPoint(x: 70, y: 100), to: CGPoint(x: 130, y: 100)))
        XCTAssertGreaterThan(skin.red, skin.blue)
        XCTAssertEqual(skin.luma, 0.6, accuracy: 0.1)
        // An eye off the image has nothing to read.
        XCTAssertNil(LinerInk.sampleSkin(in: pb, aroundEyeFrom: CGPoint(x: -900, y: -900), to: CGPoint(x: -800, y: -900)))
    }

    // MARK: Look (writes before/after pictures when LINER_RENDER_OUT is set)

    private func skinPhoto(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor(red: 0.86, green: 0.66, blue: 0.55, alpha: 1).cgColor,
                          UIColor(red: 0.70, green: 0.50, blue: 0.41, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
                                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            // Eyeball: sclera and iris, clipped to a lens shape; a lid crease above.
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let w = size.width * 0.5
            cg.setStrokeColor(UIColor(red: 0.55, green: 0.36, blue: 0.3, alpha: 0.5).cgColor)
            cg.setLineWidth(3)
            cg.addEllipse(in: CGRect(x: c.x - w * 0.5, y: c.y - w * 0.36, width: w, height: w * 0.2)); cg.strokePath()
            let eye = CGMutablePath()
            eye.move(to: CGPoint(x: c.x - w / 2, y: c.y))
            eye.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y), control: CGPoint(x: c.x, y: c.y - w * 0.34))
            eye.addQuadCurve(to: CGPoint(x: c.x - w / 2, y: c.y), control: CGPoint(x: c.x, y: c.y + w * 0.3))
            cg.saveGState(); cg.addPath(eye); cg.clip()
            cg.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor); cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(UIColor(red: 0.25, green: 0.15, blue: 0.1, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - w * 0.16, y: c.y - w * 0.2, width: w * 0.32, height: w * 0.32))
            cg.restoreGState()
            // Camera noise.
            var g = SystemRandomNumberGenerator()
            for _ in 0..<(Int(size.width * size.height) / 3) {
                let x = CGFloat.random(in: 0..<size.width, using: &g), y = CGFloat.random(in: 0..<size.height, using: &g)
                cg.setFillColor(UIColor(white: Bool.random() ? 0 : 1, alpha: 0.05).cgColor)
                cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    func testRenderBeforeAndAfter() throws {
        let size = CGSize(width: 480, height: 360)
        let photo = skinPhoto(size: size)
        let eyeLandmarks = SyntheticEye.landmarks(center: CGPoint(x: 240, y: 180), width: 240)
        let shade = MakeupPalette.black
        for (name, spec) in [("wing", LinerSpec(upperThickness: [0.03, 0.05, 0.07], wingAngleDeg: 20, wingLength: 0.25))] {
            let guide = try XCTUnwrap(LinerPathBuilder.build(landmarks: eyeLandmarks, spec: spec, options: LinerBuildOptions()))
            let frame = LinerOverlayFrame(eyes: [RenderedEye(side: .subjectRight, guide: guide, alpha: 1)],
                                          mapping: ImageToViewMapping(transform: .identity, source: .displayTransform),
                                          receivedAt: CACurrentMediaTime(), skin: InkColor(red: 0.78, green: 0.58, blue: 0.48))
            let after = LinerOverlayRenderer.compose(photo, overlay: frame, shade: shade, intensity: 1)
            XCTAssertNotEqual(after.pngData(), photo.pngData())
            // The old look: a flat blurred alpha fill, for comparison.
            let before = UIGraphicsImageRenderer(size: size, format: photo.imageRendererFormat).image { ctx in
                photo.draw(at: .zero)
                let path = CGMutablePath()
                for o in guide.outlines { path.addLines(between: o); path.closeSubpath() }
                ctx.cgContext.setFillColor(red: shade.red, green: shade.green, blue: shade.blue, alpha: 0.88)
                ctx.cgContext.addPath(path); ctx.cgContext.fillPath()
            }
            if let dir = ProcessInfo.processInfo.environment["LINER_RENDER_OUT"] {
                try? before.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-before.png"))
                try? after.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-after.png"))
            }
        }
    }
}
