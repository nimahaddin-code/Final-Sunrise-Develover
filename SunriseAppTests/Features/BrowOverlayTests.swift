// Brow overlay pictures: baking a PNG into brow space and laying it on an observed brow. These check the maths on
// synthetic images and the bundled assets, not how it looks on a face (that needs a device).
import XCTest
import CoreGraphics
import simd
@testable import SunriseApp

final class BrowOverlayTests: XCTestCase {
    private let extent = BeautyBlushEngine.browExtent

    /// A 400 x 100 transparent picture with an opaque rectangle `x`, `y` in pixels (y down), of one colour.
    private func picture(x: ClosedRange<Int>, y: ClosedRange<Int>, gray: UInt8 = 80) throws -> CGImage {
        let w = 400, h = 100
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for row in y { for column in x { let o = (row * w + column) * 4; bytes[o] = gray; bytes[o + 1] = gray; bytes[o + 2] = gray; bytes[o + 3] = 255 } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func texel(_ baked: BakedBrowSprite, u: Float, w: Float) -> SIMD4<Float> {
        let tx = Int((u - extent.x) / (extent.y - extent.x) * Float(baked.width)), ty = Int((extent.z - w) / (2 * extent.z) * Float(baked.height))
        let o = (min(max(ty, 0), baked.height - 1) * baked.width + min(max(tx, 0), baked.width - 1)) * 4
        return SIMD4((0..<4).map { Float(Float16(bitPattern: baked.texels[o + $0])) })
    }

    func testPictureSpansTheBrowFromHeadToTail() throws {
        let baked = try XCTUnwrap(BrowSpriteBaker.bake(try picture(x: 50...349, y: 40...59), extent: extent))
        XCTAssertEqual(baked.texels.count, baked.width * baked.height * 4)
        XCTAssertGreaterThan(texel(baked, u: 0.5, w: 0).x, 0.99, "the brow body is on the chord")
        XCTAssertGreaterThan(texel(baked, u: BrowSpriteBaker.headU + 0.03, w: 0).x, 0.9, "head")
        XCTAssertGreaterThan(texel(baked, u: BrowSpriteBaker.tailU - 0.03, w: 0).x, 0.9, "tail")
        XCTAssertEqual(texel(baked, u: BrowSpriteBaker.headU - 0.05, w: 0).x, 0, accuracy: 0.001, "nothing before the head")
        XCTAssertEqual(texel(baked, u: BrowSpriteBaker.tailU + 0.05, w: 0).x, 0, accuracy: 0.001, "nothing past the tail")
        // 20 px of 300 is 0.067 brow widths thick: well clear of it at 0.2.
        XCTAssertEqual(texel(baked, u: 0.5, w: 0.2).x, 0, accuracy: 0.001)
        XCTAssertEqual(texel(baked, u: 0.5, w: -0.2).x, 0, accuracy: 0.001)
        XCTAssertEqual(texel(baked, u: 0.5, w: 0).y, texel(baked, u: 0.5, w: 0).x, "strand density equals coverage")
    }

    func testDetailIsAverageForAFlatPictureAndOneOutside() throws {
        let baked = try XCTUnwrap(BrowSpriteBaker.bake(try picture(x: 50...349, y: 40...59), extent: extent))
        XCTAssertEqual(texel(baked, u: 0.5, w: 0).w, 1, accuracy: 0.02)
        XCTAssertEqual(texel(baked, u: 0.5, w: 0.3).w, 1, accuracy: 0.001)
    }

    func testPictureIsPlacedRelativeToItsOwnChord() throws {
        // A thin band that climbs from the head (y 70) to the tail (y 30): the chord follows it, so the band is still on w = 0.
        let w = 400, h = 100
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for x in 50..<350 {
            let y = 70 - 40 * (x - 50) / 300
            for row in (y - 3)...(y + 3) { let o = (row * w + x) * 4; bytes[o] = 60; bytes[o + 1] = 60; bytes[o + 2] = 60; bytes[o + 3] = 255 }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                                          shouldInterpolate: false, intent: .defaultIntent))
        let baked = try XCTUnwrap(BrowSpriteBaker.bake(image, extent: extent))
        for u in [Float(0.2), 0.5, 0.8] { XCTAssertGreaterThan(texel(baked, u: u, w: 0).x, 0.9, "u = \(u)") }
    }

    func testArchedPictureKeepsItsArchAboveTheChord() throws {
        // Head and tail at y 70, the middle raised to y 30: the arch is 40 px above the chord, 40 / 300 widths.
        let w = 400, h = 100
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for x in 50..<350 {
            let t = Float(x - 50) / 300, y = 70 - Int(40 * sin(.pi * t))
            for row in (y - 3)...(y + 3) { let o = (row * w + x) * 4; bytes[o] = 60; bytes[o + 1] = 60; bytes[o + 2] = 60; bytes[o + 3] = 255 }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                                          shouldInterpolate: false, intent: .defaultIntent))
        let baked = try XCTUnwrap(BrowSpriteBaker.bake(image, extent: extent))
        XCTAssertGreaterThan(texel(baked, u: 0.5, w: 40.0 / 300 * (BrowSpriteBaker.tailU - BrowSpriteBaker.headU)).x, 0.7)
        XCTAssertEqual(texel(baked, u: 0.5, w: 0).x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(texel(baked, u: BrowSpriteBaker.headU + 0.02, w: 0).x, 0.5)
    }

    func testEmptyPictureDoesNotBake() throws {
        let empty = try picture(x: 0...0, y: 0...0)
        // One opaque pixel is not a brow.
        XCTAssertNil(BrowSpriteBaker.bake(empty, extent: extent))
    }

    func testBundledOverlaysBake() throws {
        for overlay in BrowOverlay.all {
            let image = try XCTUnwrap(UIImage(named: overlay.assetName)?.cgImage, overlay.assetName)
            let baked = try XCTUnwrap(BrowSpriteBaker.bake(image, extent: extent), overlay.id)
            var covered = 0
            for i in stride(from: 0, to: baked.texels.count, by: 4) where Float(Float16(bitPattern: baked.texels[i])) > 0.5 { covered += 1 }
            let share = Float(covered) / Float(baked.width * baked.height)
            XCTAssertGreaterThan(share, 0.04, "\(overlay.id) covers part of the texture"); XCTAssertLessThan(share, 0.5, overlay.id)
            XCTAssertEqual(texel(baked, u: -0.2, w: 0).x, 0, accuracy: 0.001, overlay.id)
        }
        XCTAssertEqual(Set(BrowOverlay.all.map(\.id)).count, BrowOverlay.all.count)
    }

    func testStoreBakesInTheBackground() throws {
        let overlay = BrowOverlay.standard
        BrowSpriteStore.shared.prepare(overlay)
        let deadline = Date().addingTimeInterval(20)
        while BrowSpriteStore.shared.baked(overlay) == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertNotNil(BrowSpriteStore.shared.baked(overlay))
        XCTAssertFalse(BrowSpriteStore.shared.hasFailed(overlay))
    }

    func testChordOffsetIsTheArchAboveTheHeadTailLine() throws {
        // Both brows: heads near the nose, an arch 8 px above the head-tail line, about 100 px long.
        func contour(_ side: Float) -> BrowContour {
            var upper: [SIMD2<Float>] = [], lower: [SIMD2<Float>] = []
            for i in 0..<5 {
                let t = Float(i) / 4, x = 500 + side * (80 + 100 * t), y = 300 - 5 * t - 8 * sin(.pi * t)
                upper.append(SIMD2(x, y - 6)); lower.append(SIMD2(x, y + 6))
            }
            return BrowContour(upper: upper, lower: lower)
        }
        for side in [Float(-1), 1] {
            let g = try XCTUnwrap(BrowGeometry(contour: contour(side)))
            XCTAssertEqual(g.chordOffset(0), 0, accuracy: 0.005)
            XCTAssertEqual(g.chordOffset(1), 0, accuracy: 0.005)
            XCTAssertEqual(g.chordOffset(0.5), 8 / g.across, accuracy: 0.02, "side \(side): the arch is above the chord")
            XCTAssertGreaterThan(g.chordOffset(0.5), 0)
        }
    }

    func testChordOffsetIsZeroForAStraightBrow() throws {
        let upper = (0..<5).map { SIMD2<Float>(100 + 25 * Float($0), 94) }, lower = (0..<5).map { SIMD2<Float>(100 + 25 * Float($0), 106) }
        let g = try XCTUnwrap(BrowGeometry(contour: BrowContour(upper: upper, lower: lower)))
        for u in [Float(-0.2), 0, 0.5, 1, 1.1] { XCTAssertEqual(g.chordOffset(u), 0, accuracy: 0.001) }
    }

    @MainActor func testNoOverlayOptionOnlyRemovesThePictureNotTheNaturalBrowHiding() {
        let home = TryOnHomeModel(plan: MakeupPlan(shape: .heart), assessment: .init(shape: .heart, origin: .analysis), checker: MockFaceTrackingChecker())
        home.choose(.eyebrow)
        XCTAssertEqual(home.liveConfiguration.browOverlay, .standard, "starts on the first picture")
        XCTAssertTrue(home.liveConfiguration.hideNaturalBrow)
        home.choose(browOverlay: nil)
        XCTAssertNil(home.liveConfiguration.browOverlay)
        XCTAssertTrue(home.liveConfiguration.hideNaturalBrow, "the natural brow stays hidden")
        XCTAssertTrue(home.liveConfiguration.browLayer.on, "the eyebrow tool stays on")
        home.choose(browOverlay: BrowOverlay.all[1])
        XCTAssertEqual(home.liveConfiguration.browOverlay, BrowOverlay.all[1])
        home.deactivate()
    }

    func testBrowFramesAreLimitedToTheMaximumRate() {
        // A 60 Hz camera: every other frame is handed on at 30 fps, and a slower cap drops more.
        var last = -Double.infinity, kept = 0
        for i in 0..<60 {
            let t = Double(i) / 60
            if BeautyBlushEngine.browFrameDue(timestamp: t, last: last, maxFPS: 30) { last = t; kept += 1 }
        }
        XCTAssertEqual(kept, 30)
        last = -.infinity; kept = 0
        for i in 0..<60 {
            let t = Double(i) / 60
            if BeautyBlushEngine.browFrameDue(timestamp: t, last: last, maxFPS: 24) { last = t; kept += 1 }
        }
        XCTAssertEqual(kept, 24, "one frame per 1/24 s slot, not one per whole 50 ms of 60 Hz frames")
        XCTAssertTrue(BeautyBlushEngine.browFrameDue(timestamp: 0, last: -.infinity))
        XCTAssertTrue(BeautyBlushEngine.browFrameDue(timestamp: 1.001, last: 1, maxFPS: nil), "no cap: every frame is due")
        // Uncapped until the phone is hot; then drawing and MediaPipe slow down.
        XCTAssertNil(BeautyBlushEngine.BrowLoad.current(.nominal).drawFPS)
        XCTAssertNil(BeautyBlushEngine.BrowLoad.current(.nominal).trackerFPS)
        XCTAssertEqual(BeautyBlushEngine.BrowLoad.current(.serious).drawFPS, 30)
    }
}
