// ARKit-pose brow stabilizer on a synthetic face: a curved mesh patch, a camera with intrinsics, a head that moves, landmarks with noise.
// These check the maths, not how ARKit's pose behaves on a real face (that needs a device).
import XCTest
import simd
@testable import SunriseApp

final class BrowFaceStabilizerTests: XCTestCase {
    private let intrinsics = simd_float3x3(columns: (SIMD3(1500, 0, 0), SIMD3(0, 1500, 0), SIMD3(960, 720, 1)))
    private let imageSize = SIMD2<Float>(1920, 1440)
    private let id = UUID()

    /// A gently domed patch 16 cm square, +z out of the face, 21 x 21 vertices.
    private func mesh() -> (vertices: [SIMD3<Float>], triangles: [UInt16]) {
        let n = 21
        var vertices: [SIMD3<Float>] = [], triangles: [UInt16] = []
        for j in 0..<n { for i in 0..<n {
            let x = -0.08 + 0.16 * Float(i) / Float(n - 1), y = -0.08 + 0.16 * Float(j) / Float(n - 1)
            vertices.append(SIMD3(x, y, Self.surface(x, y)))
        } }
        for j in 0..<n - 1 { for i in 0..<n - 1 {
            let a = UInt16(j * n + i), b = a + 1, c = a + UInt16(n), d = c + 1
            triangles += [a, b, c, b, d, c]
        } }
        return (vertices, triangles)
    }
    private static func surface(_ x: Float, _ y: Float) -> Float { 0.02 - 1.5 * (x * x + y * y) }

    /// The head's pose at time `t`: it sits 35 cm in front of the camera and drifts and turns a little.
    private func face(at t: Double, still: Bool = false) -> BrowFaceFrame {
        let m = mesh()
        let a = still ? 0 : Float(sin(t * 2.1)) * 0.09, b = still ? 0 : Float(sin(t * 1.3 + 1)) * 0.06
        let rotation = simd_float4x4(simd_quatf(angle: a, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: b, axis: SIMD3(1, 0, 0)))
        var faceToWorld = rotation
        let shift = still ? SIMD3<Float>.zero : SIMD3(Float(sin(t * 1.7)) * 0.012, Float(cos(t * 1.1)) * 0.01, 0)
        faceToWorld.columns.3 = SIMD4(shift.x, shift.y, -0.35 + shift.z, 1)
        return BrowFaceFrame(anchorID: id, vertices: m.vertices, triangles: m.triangles, intrinsics: intrinsics, imageSize: imageSize,
                             faceToWorld: faceToWorld, cameraToWorld: matrix_identity_float4x4)
    }

    /// The landmarks' true places on the face (face-local x, y; z follows the surface).
    private let layout: [SIMD2<Float>] = {
        func brow(_ side: Float) -> ([SIMD2<Float>], [SIMD2<Float>]) {
            var upper: [SIMD2<Float>] = [], lower: [SIMD2<Float>] = []
            for i in 0..<5 {
                let t = Float(i) / 4, x = side * (0.012 + 0.045 * t), y = 0.03 + 0.012 * sin(.pi * t)
                upper.append(SIMD2(x, y + 0.004)); lower.append(SIMD2(x, y - 0.004))
            }
            return (upper, lower)
        }
        let r = brow(-1), l = brow(1)
        func eye(_ side: Float) -> [SIMD2<Float>] { [SIMD2(side * 0.015, 0.0), SIMD2(side * 0.045, 0.0), SIMD2(side * 0.012, -0.03)] }
        // noseBridge, right: upper, lower, inner, outer, ala; left: the same (the order `flattened` uses).
        return [SIMD2(0, 0.01)] + r.0 + r.1 + eye(-1) + l.0 + l.1 + eye(1)
    }()

    private func observation(pixels: [SIMD2<Float>], at t: Double) -> BrowObservation {
        var i = 1
        func take(_ n: Int) -> [SIMD2<Float>] { defer { i += n }; return Array(pixels[i..<i + n]) }
        let rightUpper = take(5), rightLower = take(5), rightEye = take(3)
        let leftUpper = take(5), leftLower = take(5), leftEye = take(3)
        func marks(_ e: [SIMD2<Float>]) -> BrowEyeMarks { BrowEyeMarks(inner: e[0], outer: e[1], iris: nil, ala: e[2]) }
        return BrowObservation(imageSize: CGSize(width: 1920, height: 1440), timestamp: t,
                               brows: [.subjectRight: BrowContour(upper: rightUpper, lower: rightLower), .subjectLeft: BrowContour(upper: leftUpper, lower: leftLower)],
                               eyes: [.subjectRight: marks(rightEye), .subjectLeft: marks(leftEye)], noseBridge: pixels[0], pose: .frontal)
    }

    private func truth(_ layout: [SIMD2<Float>], _ f: BrowFaceFrame, shift: SIMD3<Float> = .zero) -> [SIMD2<Float>] {
        layout.map { f.pixel(of: SIMD3($0.x, $0.y, Self.surface($0.x, $0.y)) + shift)! }
    }

    /// Deterministic noise in [-1, 1].
    private struct Noise { var state: UInt64 = 12345
        mutating func next() -> Float { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1 } }

    func testPixelAndFaceLocalRoundTrip() throws {
        let f = face(at: 0.4)
        for p in layout {
            let q = SIMD3(p.x, p.y, Self.surface(p.x, p.y))
            let back = try XCTUnwrap(f.faceLocal(at: try XCTUnwrap(f.pixel(of: q))))
            XCTAssertLessThan(simd_distance(back, q), 0.0005, "a mesh point seen in the image lifts back to itself (the mesh is faceted, so within half a millimetre)")
        }
    }

    func testARayThatMissesTheMeshStillLandsOnTheFace() throws {
        let f = face(at: 0, still: true)
        let outside = try XCTUnwrap(f.pixel(of: SIMD3(0.1, 0.03, 0.0)))
        let q = try XCTUnwrap(f.faceLocal(at: outside))
        XCTAssertLessThan(abs(q.y - 0.03), 0.01)
        XCTAssertLessThan(simd_distance(try XCTUnwrap(f.pixel(of: q)), outside), 0.01, "the lifted point projects back onto the same pixel")
    }

    func testAMovingHeadAddsNoErrorAndNoLag() throws {
        var stabilizer = BrowFaceStabilizer()
        var worst: Float = 0
        for k in 0..<90 {
            let t = Double(k) / 30, f = face(at: t)
            let exact = truth(layout, f)
            let out = try XCTUnwrap(stabilizer.stabilize(observation(pixels: exact, at: t), face: f))
            if k > 2 { worst = max(worst, zip(out.flattened, exact).map { simd_distance($0, $1) }.max() ?? 0) }
        }
        XCTAssertLessThan(worst, 0.6, "head motion is taken from the pose, so exact landmarks stay put to a fraction of a pixel (was \(worst) px)")
    }

    func testNoisyLandmarksAreMuchSteadier() throws {
        var stabilizer = BrowFaceStabilizer(), noise = Noise()
        var rawError: Float = 0, steadyError: Float = 0, count: Float = 0
        for k in 0..<150 {
            let t = Double(k) / 30, f = face(at: t)
            let exact = truth(layout, f)
            let noisy = exact.map { $0 + SIMD2(noise.next(), noise.next()) * 1.5 }
            let out = try XCTUnwrap(stabilizer.stabilize(observation(pixels: noisy, at: t), face: f))
            guard k >= 30 else { continue }
            rawError += zip(noisy, exact).map { simd_distance_squared($0, $1) }.reduce(0, +)
            steadyError += zip(out.flattened, exact).map { simd_distance_squared($0, $1) }.reduce(0, +)
            count += Float(exact.count)
        }
        let raw = (rawError / count).squareRoot(), steady = (steadyError / count).squareRoot()
        XCTAssertLessThan(steady, raw * 0.5, "RMS error \(steady) px against \(raw) px unfiltered")
    }

    func testARealMovementOfTheBrowIsFollowed() throws {
        var stabilizer = BrowFaceStabilizer()
        var last: [SIMD2<Float>] = [], exactAtEnd: [SIMD2<Float>] = []
        for k in 0..<60 {
            let t = Double(k) / 30, f = face(at: t, still: true)
            // From frame 20 the brow is raised 4 mm on the face.
            let raised = k >= 20
            let moved = layout.enumerated().map { i, p -> SIMD3<Float> in
                let isBrow = (1...10).contains(i) || (14...23).contains(i)
                return SIMD3(p.x, p.y + (raised && isBrow ? 0.004 : 0), Self.surface(p.x, p.y))
            }
            let exact = moved.map { f.pixel(of: $0)! }
            let out = try XCTUnwrap(stabilizer.stabilize(observation(pixels: exact, at: t), face: f))
            last = out.flattened; exactAtEnd = exact
        }
        let error = zip(last, exactAtEnd).map { simd_distance($0, $1) }.max() ?? 0
        XCTAssertLessThan(error, 1.5, "two seconds after a 4 mm raise the brow has caught up to within \(error) px")
    }

    func testANewFaceOrALongGapRestartsWithoutGliding() throws {
        var stabilizer = BrowFaceStabilizer()
        let f = face(at: 0, still: true)
        _ = stabilizer.stabilize(observation(pixels: truth(layout, f), at: 0), face: f)
        // A second later, the face is somewhere else: the first output is the landmarks as seen.
        let elsewhere = truth(layout, f, shift: SIMD3(0.02, 0.01, 0))
        let out = try XCTUnwrap(stabilizer.stabilize(observation(pixels: elsewhere, at: 1), face: f))
        XCTAssertLessThan(zip(out.flattened, elsewhere).map { simd_distance($0, $1) }.max() ?? 0, 0.5)
    }

    func testAFaceThatDisagreesWithTheLandmarksIsNotTrusted() throws {
        // The landmarks jump 3 cm on the face in one frame while the pose stays put: the steadied brow would sit far from what was
        // seen, so the stabilizer gives up (the caller then uses the image-space smoother) and starts afresh.
        var stabilizer = BrowFaceStabilizer()
        let f = face(at: 0, still: true)
        XCTAssertNotNil(stabilizer.stabilize(observation(pixels: truth(layout, f), at: 0), face: f))
        let jumped = truth(layout, f, shift: SIMD3(0.03, 0, 0))
        XCTAssertNil(stabilizer.stabilize(observation(pixels: jumped, at: 1.0 / 30), face: f))
        // The next frame starts a new run from the landmarks as seen.
        let next = try XCTUnwrap(stabilizer.stabilize(observation(pixels: jumped, at: 2.0 / 30), face: f))
        XCTAssertLessThan(zip(next.flattened, jumped).map { simd_distance($0, $1) }.max() ?? 0, 0.5)
    }
}
