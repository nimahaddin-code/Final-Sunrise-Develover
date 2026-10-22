import XCTest
import simd
@testable import SunriseApp

final class MakeupTextureGeometryTests: XCTestCase {
    func testBarycentricWeightsReproduceThePoint() throws {
        let a = SIMD2<Float>(0, 0), b = SIMD2<Float>(4, 0), c = SIMD2<Float>(0, 4)
        let weights = try XCTUnwrap(ProjectedFaceMesh.barycentric(SIMD2(1, 1), a, b, c))
        XCTAssertEqual(weights.x + weights.y + weights.z, 1, accuracy: 1e-6)
        let point = weights.x * a + weights.y * b + weights.z * c
        XCTAssertEqual(point.x, 1, accuracy: 1e-6)
        XCTAssertEqual(point.y, 1, accuracy: 1e-6)
        XCTAssertNil(ProjectedFaceMesh.barycentric(SIMD2(1, 1), a, a, a))
    }

    /// Two triangles covering a 100×100 image square, mapped onto the UV square 0...1.
    private let square = ProjectedFaceMesh(
        points: [SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(0, 100)],
        depths: [0.3, 0.3, 0.3, 0.3],
        textureCoordinates: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)],
        triangleIndices: [0, 1, 2, 0, 2, 3])

    func testImagePointMapsToInterpolatedTextureCoordinate() throws {
        let uv = try XCTUnwrap(square.textureCoordinate(at: SIMD2(25, 60)))
        XCTAssertEqual(uv.x, 0.25, accuracy: 1e-5)
        XCTAssertEqual(uv.y, 0.6, accuracy: 1e-5)
    }

    func testPointOutsideMeshIsExtrapolated() throws {
        let uv = try XCTUnwrap(square.textureCoordinate(at: SIMD2(110, 50)))
        XCTAssertEqual(uv.x, 1.1, accuracy: 1e-5)
        XCTAssertEqual(uv.y, 0.5, accuracy: 1e-5)
    }

    /// A 3x3 grid of 30-pixel squares whose centre square is missing, like the eye opening in the face mesh.
    func testPointInsideAHoleInterpolatesAcrossIt() throws {
        let columns = 4
        let points = (0..<16).map { SIMD2<Float>(Float($0 % columns) * 30, Float($0 / columns) * 30) }
        var triangles: [Int16] = []
        for row in 0..<3 {
            for column in 0..<3 where !(row == 1 && column == 1) {
                let a = Int16(row * columns + column), b = a + 1, c = a + Int16(columns), d = c + 1
                triangles += [a, b, d, a, d, c]
            }
        }
        let mesh = ProjectedFaceMesh(points: points, depths: Array(repeating: 0.3, count: 16),
                                     textureCoordinates: points.map { $0 / 90 }, triangleIndices: triangles)
        for probe in [SIMD2<Float>(45, 45), SIMD2(38, 52), SIMD2(52, 40)] {
            let uv = try XCTUnwrap(mesh.textureCoordinate(at: probe))
            XCTAssertEqual(uv.x, probe.x / 90, accuracy: 1e-3)
            XCTAssertEqual(uv.y, probe.y / 90, accuracy: 1e-3)
        }
    }

    func testOverlappingSurfacePrefersTheOneNearestTheCamera() throws {
        let mesh = ProjectedFaceMesh(
            points: [SIMD2(0, 0), SIMD2(10, 0), SIMD2(0, 10), SIMD2(0, 0), SIMD2(10, 0), SIMD2(0, 10)],
            depths: [0.5, 0.5, 0.5, 0.2, 0.2, 0.2],
            textureCoordinates: [SIMD2(0, 0), SIMD2(0, 0), SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 1), SIMD2(1, 1)],
            triangleIndices: [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(mesh.textureCoordinate(at: SIMD2(2, 2)), SIMD2(1, 1))
    }

    private func side(eyeX: Float) -> FaceFeatureMap.Side {
        // Texture v grows downward, so the brow has a smaller y than the eye.
        FaceFeatureMap.Side(brow: [SIMD2(eyeX - 0.06, 0.32), SIMD2(eyeX, 0.30), SIMD2(eyeX + 0.06, 0.33)],
                            eye: [SIMD2(eyeX - 0.04, 0.40), SIMD2(eyeX, 0.38), SIMD2(eyeX + 0.04, 0.40),
                                  SIMD2(eyeX, 0.42)])
    }

    private var map: FaceFeatureMap { FaceFeatureMap(left: side(eyeX: 0.65), right: side(eyeX: 0.35)) }

    func testFeatureFramePointsAwayFromTheNoseAndTowardTheBrow() {
        let left = FeatureFrame(side: map.left, in: map), right = FeatureFrame(side: map.right, in: map)
        XCTAssertEqual(left.outward.x, 1, accuracy: 1e-5)
        XCTAssertEqual(right.outward.x, -1, accuracy: 1e-5)
        XCTAssertEqual(left.up.y, -1, accuracy: 1e-5)
        XCTAssertEqual(right.up.y, -1, accuracy: 1e-5)
        XCTAssertEqual(left.unit, 0.3, accuracy: 1e-5)
    }

    func testAverageRequiresMatchingLayouts() throws {
        var shifted = map
        shifted.left.eye = shifted.left.eye.map { $0 + SIMD2(0.02, 0) }
        let average = try XCTUnwrap(FaceFeatureMap.average([map, shifted]))
        XCTAssertEqual(average.left.eyeCenter.x, 0.66, accuracy: 1e-5)
        var missing = map
        missing.right.brow.removeLast()
        XCTAssertNil(FaceFeatureMap.average([map, missing]))
    }

    func testHigherArchLiftsTheBrowPeak() {
        let frame = FeatureFrame(side: map.left, in: map)
        let shade = MakeupPalette.black
        func highestPoint(_ archHeight: Float) -> Float {
            let style = BrowStyle(archPosition: 0.6, archHeight: archHeight, thickness: 0.15, tailExtension: 0,
                                  angularity: 0.5, shade: shade)
            return MakeupTextureRenderer.browOutline(style, brow: map.left.brow, frame: frame).map(\.y).min()!
        }
        XCTAssertLessThan(highestPoint(0.2), highestPoint(0.05))
    }

    func testLinerWingReachesPastTheOuterCorner() {
        let frame = FeatureFrame(side: map.left, in: map)
        let shade = MakeupPalette.black
        let style = LinerStyle(innerWidth: 0.02, outerWidth: 0.06, start: 0, wingLength: 0.3, wingAngle: 20,
                               shade: shade)
        let outline = MakeupTextureRenderer.linerOutlines(style, eye: map.left.eye, brow: map.left.brow, frame: frame)
            .flatMap { $0 }
        let outerCorner: Float = 0.69
        let tip = outline.max { $0.x < $1.x }!
        XCTAssertGreaterThan(tip.x, outerCorner)
        XCTAssertLessThan(tip.y, 0.40, "Wing should lift toward the brow")
        // The liner sits on the upper lid, never below the eye's lower edge.
        XCTAssertTrue(outline.allSatisfy { $0.y < 0.42 })
    }
}
