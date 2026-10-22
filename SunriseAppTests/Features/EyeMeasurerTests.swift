import XCTest
@testable import SunriseApp

/// Eyes drawn as ellipses so every expected number is known exactly. Coordinates: x to the right, y up, face upright.
struct SyntheticEyes {
    var width: Float = 30
    var openness: Float = 0.3
    /// Degrees; positive lifts the outer corners.
    var tilt: Float = 4
    var spacing: Float = 1
    var irisDiameter: Float = 12
    /// Brow-to-lid gap in iris diameters.
    var lidSpace: Float = 1.2
    var lidPointCount = 16
    var browPointCount = 3

    func landmarks() -> EyeScanLandmarks {
        EyeScanLandmarks(first: eye(side: -1), second: eye(side: 1))
    }

    /// `side` is -1 for the eye on the left of the picture and 1 for the one on the right.
    private func eye(side: Float) -> EyeScanLandmarks.Eye {
        let radians = tilt * .pi / 180
        let inner = SIMD2<Float>(side * spacing * width / 2, 0)
        let axis = SIMD2<Float>(side * cos(radians), sin(radians))
        let outer = inner + axis * width
        let center = (inner + outer) / 2
        let normal = SIMD2<Float>(-axis.y, axis.x) * side
        let height = openness * width

        let lid = (0..<lidPointCount).map { step -> SIMD2<Float> in
            let angle = 2 * Float.pi * Float(step) / Float(lidPointCount)
            return center + axis * (width / 2 * cos(angle)) + normal * (height / 2 * sin(angle))
        }
        let iris = (0..<4).map { step -> SIMD2<Float> in
            let angle = Float.pi / 2 * Float(step)
            return center + SIMD2(cos(angle), sin(angle)) * (irisDiameter / 2)
        }
        let lidTop = lid.map(\.y).max() ?? 0
        let browY = lidTop + lidSpace * irisDiameter
        let brow = (0..<browPointCount).map { step -> SIMD2<Float> in
            SIMD2(center.x + Float(step - browPointCount / 2) * 4, browY)
        }
        return EyeScanLandmarks.Eye(innerCorner: inner, outerCorner: outer, lid: lid, iris: iris, brow: brow)
    }
}

final class EyeMeasurerTests: XCTestCase {
    private func transformed(_ landmarks: EyeScanLandmarks, _ transform: (SIMD2<Float>) -> SIMD2<Float>) -> EyeScanLandmarks {
        func eye(_ e: EyeScanLandmarks.Eye) -> EyeScanLandmarks.Eye {
            EyeScanLandmarks.Eye(innerCorner: transform(e.innerCorner), outerCorner: transform(e.outerCorner),
                             lid: e.lid.map(transform), iris: e.iris.map(transform), brow: e.brow.map(transform))
        }
        return EyeScanLandmarks(first: eye(landmarks.first), second: eye(landmarks.second))
    }

    private func assertMeasurements(_ landmarks: EyeScanLandmarks, openness: Float = 0.3, tilt: Float = 4, spacing: Float = 1,
                                    lidSpace: Float = 1.2, file: StaticString = #filePath, line: UInt = #line) throws {
        let measured = try XCTUnwrap(EyeMeasurer.measure(landmarks), file: file, line: line)
        XCTAssertEqual(measured.openness, openness, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(measured.tilt, tilt, accuracy: 1e-2, file: file, line: line)
        XCTAssertEqual(measured.spacing, spacing, accuracy: 1e-3, file: file, line: line)
        XCTAssertEqual(measured.lidSpace, lidSpace, accuracy: 1e-3, file: file, line: line)
    }

    func testMeasuresOpennessTiltSpacingAndLidSpace() throws {
        try assertMeasurements(SyntheticEyes().landmarks())
        try assertMeasurements(SyntheticEyes(width: 24, openness: 0.42, tilt: -6, spacing: 1.3, lidSpace: 0.7).landmarks(),
                               openness: 0.42, tilt: -6, spacing: 1.3, lidSpace: 0.7)
    }

    func testTiltIsPositiveForUpturnedAndNegativeForDownturned() throws {
        XCTAssertGreaterThan(try XCTUnwrap(EyeMeasurer.measure(SyntheticEyes(tilt: 10).landmarks())).tilt, 0)
        XCTAssertLessThan(try XCTUnwrap(EyeMeasurer.measure(SyntheticEyes(tilt: -10).landmarks())).tilt, 0)
    }

    func testIgnoresScaleRollPositionMirroringAndEyeOrder() throws {
        let eyes = SyntheticEyes().landmarks()
        let angle = Float.pi / 5
        try assertMeasurements(transformed(eyes) { p in
            (SIMD2(p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle)) * 3.7) + SIMD2(400, 300)
        })
        try assertMeasurements(transformed(eyes) { SIMD2(-$0.x, $0.y) })
        // Image coordinates grow downward, so "up" on the face is toward smaller y.
        try assertMeasurements(transformed(eyes) { SIMD2($0.x, -$0.y) })
        try assertMeasurements(EyeScanLandmarks(first: eyes.second, second: eyes.first))
    }

    func testIrisPointOrderDoesNotMatter() throws {
        var eyes = SyntheticEyes().landmarks()
        eyes.first.iris = [eyes.first.iris[0], eyes.first.iris[2], eyes.first.iris[1], eyes.first.iris[3]]
        eyes.second.iris.reverse()
        try assertMeasurements(eyes)
    }

    func testFailsOnMissingOrDegenerateLandmarks() {
        var noIris = SyntheticEyes().landmarks()
        noIris.first.iris = []
        XCTAssertNil(EyeMeasurer.measure(noIris))

        var noBrow = SyntheticEyes().landmarks()
        noBrow.second.brow = []
        XCTAssertNil(EyeMeasurer.measure(noBrow))

        var sameSpot = SyntheticEyes().landmarks()
        sameSpot.second = sameSpot.first
        XCTAssertNil(EyeMeasurer.measure(sameSpot))

        var collapsed = SyntheticEyes().landmarks()
        collapsed.first.outerCorner = collapsed.first.innerCorner
        XCTAssertNil(EyeMeasurer.measure(collapsed))
    }

    // MARK: MediaPipe mesh mapping

    /// Puts the synthetic eyes where MediaPipe's topology expects them, in normalized image coordinates.
    private func mesh(of landmarks: EyeScanLandmarks, imageSize: SIMD2<Float>, irisRingsSwapped: Bool = false) -> [SIMD2<Float>] {
        var points = [SIMD2<Float>](repeating: SIMD2(0.5, 0.5), count: EyeScanLandmarks.MeshIndex.pointCount)
        func place(_ eye: EyeScanLandmarks.Eye, at index: EyeScanLandmarks.MeshIndex.Eye, irisRing: [Int]) {
            points[index.inner] = eye.innerCorner / imageSize
            points[index.outer] = eye.outerCorner / imageSize
            for (i, point) in zip(index.lid, eye.lid) { points[i] = point / imageSize }
            for (i, point) in zip(irisRing, eye.iris) { points[i] = point / imageSize }
            for (i, point) in zip(index.brow, eye.brow) { points[i] = point / imageSize }
        }
        let rings = EyeScanLandmarks.MeshIndex.irisRings
        place(landmarks.first, at: EyeScanLandmarks.MeshIndex.personRight, irisRing: irisRingsSwapped ? rings[1] : rings[0])
        place(landmarks.second, at: EyeScanLandmarks.MeshIndex.personLeft, irisRing: irisRingsSwapped ? rings[0] : rings[1])
        return points
    }

    func testMeshIndicesAreDistinctAndInRange() {
        let all = [EyeScanLandmarks.MeshIndex.personRight, EyeScanLandmarks.MeshIndex.personLeft].flatMap {
            [$0.inner, $0.outer] + $0.lid + $0.brow
        } + EyeScanLandmarks.MeshIndex.irisRings.flatMap { $0 }
        XCTAssertEqual(Set(all).count, all.count, "no index is used twice")
        XCTAssertTrue(all.allSatisfy { (0..<EyeScanLandmarks.MeshIndex.pointCount).contains($0) })
    }

    func testMeshLandmarksMeasureTheSameAsTheSourceEyes() throws {
        // Real mesh eyes have 14 lid points, 4 iris points and 5 brow points. A tall, narrow image checks that the
        // aspect ratio is restored: without it every ratio would be wrong.
        let eyes = SyntheticEyes(lidPointCount: 14, browPointCount: 5).landmarks()
        let size = SIMD2<Float>(720, 1280)
        let fromMesh = try XCTUnwrap(EyeScanLandmarks(normalizedMesh: mesh(of: eyes, imageSize: size), imageSize: size))
        let direct = try XCTUnwrap(EyeMeasurer.measure(eyes))
        let viaMesh = try XCTUnwrap(EyeMeasurer.measure(fromMesh))
        XCTAssertEqual(viaMesh.openness, direct.openness, accuracy: 1e-3)
        XCTAssertEqual(viaMesh.tilt, direct.tilt, accuracy: 1e-2)
        XCTAssertEqual(viaMesh.spacing, direct.spacing, accuracy: 1e-3)
        XCTAssertEqual(viaMesh.lidSpace, direct.lidSpace, accuracy: 1e-3)
    }

    func testIrisRingsGoToTheNearestEyeWhicheverRingIsWhichSide() throws {
        let eyes = SyntheticEyes(lidPointCount: 14, browPointCount: 5).landmarks()
        let size = SIMD2<Float>(720, 1280)
        let direct = try XCTUnwrap(EyeMeasurer.measure(eyes))
        for swapped in [false, true] {
            let fromMesh = try XCTUnwrap(EyeScanLandmarks(normalizedMesh: mesh(of: eyes, imageSize: size, irisRingsSwapped: swapped),
                                                      imageSize: size))
            XCTAssertEqual(try XCTUnwrap(EyeMeasurer.measure(fromMesh)).lidSpace, direct.lidSpace, accuracy: 1e-3,
                           "iris diameter, and so lidSpace, is only right if each eye got its own ring (swapped: \(swapped))")
        }
    }

    func testMeshWithoutIrisPointsIsRejected() {
        let eyes = SyntheticEyes(lidPointCount: 14, browPointCount: 5).landmarks()
        let size = SIMD2<Float>(720, 1280)
        let faceOnly = Array(mesh(of: eyes, imageSize: size).prefix(468))
        XCTAssertNil(EyeScanLandmarks(normalizedMesh: faceOnly, imageSize: size))
        XCTAssertNil(EyeScanLandmarks(normalizedMesh: mesh(of: eyes, imageSize: size), imageSize: .zero))
    }

    func testHeadTurnIsZeroWhenFacingTheCameraAndGrowsAsTheNoseShifts() throws {
        let eyes = SyntheticEyes(lidPointCount: 14, browPointCount: 5).landmarks()
        let size = SIMD2<Float>(720, 1280)
        var points = mesh(of: eyes, imageSize: size)
        XCTAssertNil(try XCTUnwrap(EyeScanLandmarks(normalizedMesh: points, imageSize: size)).headTurn, "no nose or face edges yet")

        points[EyeScanLandmarks.MeshIndex.faceEdgeRight] = SIMD2(0.3, 0.5)
        points[EyeScanLandmarks.MeshIndex.faceEdgeLeft] = SIMD2(0.7, 0.5)
        points[EyeScanLandmarks.MeshIndex.noseTip] = SIMD2(0.5, 0.55)
        XCTAssertEqual(try XCTUnwrap(EyeScanLandmarks(normalizedMesh: points, imageSize: size)).headTurn ?? 1, 0, accuracy: 1e-4)

        points[EyeScanLandmarks.MeshIndex.noseTip] = SIMD2(0.56, 0.55)
        let turned = try XCTUnwrap(EyeScanLandmarks(normalizedMesh: points, imageSize: size)).headTurn
        XCTAssertEqual(try XCTUnwrap(turned), 0.3, accuracy: 1e-3, "nose 65% of the way across, so 30% toward the left edge")
    }

    // MARK: Sampler

    private func sample(openness: Float = 0.3, tilt: Float = 4) -> EyeMeasurements {
        EyeMeasurements(openness: openness, tilt: tilt, spacing: 1, lidSpace: 1)
    }

    func testSamplerSkipsClosedEyesAndReportsProgress() {
        var sampler = EyeMeasurementsSampler(requiredSamples: 4)
        XCTAssertFalse(sampler.add(sample(openness: 0.05)))
        XCTAssertEqual(sampler.progress, 0)
        XCTAssertTrue(sampler.add(sample()))
        XCTAssertTrue(sampler.add(sample()))
        XCTAssertEqual(sampler.progress, 0.5, accuracy: 1e-9)
        XCTAssertFalse(sampler.isComplete)
        sampler.add(sample()); sampler.add(sample())
        XCTAssertTrue(sampler.isComplete)
        XCTAssertFalse(sampler.add(sample()), "a full sampler keeps no more frames")
        sampler.reset()
        XCTAssertNil(sampler.median())
    }

    func testSamplerMedianIgnoresOutlierFrames() throws {
        var sampler = EyeMeasurementsSampler(requiredSamples: 5)
        for tilt: Float in [4, 5, 4, 40, 3] { sampler.add(sample(tilt: tilt)) }
        XCTAssertEqual(try XCTUnwrap(sampler.median()).tilt, 4, accuracy: 1e-6)
    }
}
