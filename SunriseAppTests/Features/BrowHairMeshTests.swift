// The 3D hair brow: the bundled ribbons, and how they are laid on a face from its tracked head, tail, normal and forehead direction.
import XCTest
import simd
@testable import SunriseApp

final class BrowHairMeshTests: XCTestCase {
    private func mesh() throws -> BrowHairMesh { try XCTUnwrap(BrowHairMesh.load(), "brow-hair-3d.obj is bundled and parses") }

    func testBundledRibbonsParse() throws {
        let m = try mesh()
        XCTAssertEqual(m.ribbons.count, 1850)
        XCTAssertLessThan(m.head.x, m.tail.x, "head on the left, tail on the right")
        XCTAssertEqual(m.vertices.count, 1850 * 6)
        XCTAssertTrue(m.ribbons.allSatisfy { $0.width > 0 && $0.width < 0.0005 && simd_distance($0.a, $0.b) > 0.0003 }, "thin ribbons, millimetres long")
        XCTAssertEqual(Set(m.ribbons.map(\.tone)), [0.7, 1.15, 1.7])
        let length = m.tail.x - m.head.x
        XCTAssertEqual(length, 0.054, accuracy: 0.003, "about 54 mm head to tail")
    }

    func testParseRejectsAnEmptyOrBrokenFile() {
        XCTAssertNil(BrowHairMesh.parse(""))
        XCTAssertNil(BrowHairMesh.parse("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n"), "too few ribbons")
        XCTAssertNil(BrowHairMesh.parse("v a b c\n"))
    }

    private let normal = SIMD3<Float>(0, 0, 1), forehead = SIMD3<Float>(0, 1, 0)

    func testChordEndsLandOnTheTrackedHeadAndTail() throws {
        let m = try mesh()
        let head = SIMD3<Float>(0.012, 0.030, 0.015), tail = SIMD3<Float>(0.060, 0.024, 0.012)
        let f = try XCTUnwrap(BrowHairPlacement.frame(mesh: m, head: head, tail: tail, normal: normal, forehead: forehead))
        func place(_ p: SIMD3<Float>) -> SIMD3<Float> { let r = f.matrix * SIMD4(p, 1); return SIMD3(r.x, r.y, r.z) }
        let chord = tail - head, lift = BrowHairPlacement.lift
        let atHead = place(SIMD3(m.head.x, m.surfaceY, m.head.z)), atTail = place(SIMD3(m.tail.x, m.surfaceY, m.tail.z))
        // The lift is along the brow's own outward axis, which leans with the chord, so it differs from the mesh normal by a fraction of a millimetre.
        XCTAssertLessThan(simd_distance(atHead, head + chord * BrowHairPlacement.headU + normal * lift), 0.0003)
        XCTAssertLessThan(simd_distance(atTail, head + chord * BrowHairPlacement.tailU + normal * lift), 0.0003)
        XCTAssertEqual(simd_distance(atTail, atHead), simd_length(chord) * (BrowHairPlacement.tailU - BrowHairPlacement.headU), accuracy: 1e-4)
        XCTAssertEqual(f.scale, simd_length(chord) * (BrowHairPlacement.tailU - BrowHairPlacement.headU) / (m.tail.x - m.head.x), accuracy: 0.01)
    }

    func testHairsStandOutOfTheSkinAndUpTowardsTheForehead() throws {
        let m = try mesh()
        let head = SIMD3<Float>(0.012, 0.030, 0.015), tail = SIMD3<Float>(0.060, 0.030, 0.015)
        let f = try XCTUnwrap(BrowHairPlacement.frame(mesh: m, head: head, tail: tail, normal: normal, forehead: forehead))
        func place(_ p: SIMD3<Float>) -> SIMD3<Float> { let r = f.matrix * SIMD4(p, 1); return SIMD3(r.x, r.y, r.z) }
        let ends = m.ribbons.flatMap { [$0.a, $0.b] }.map(place)
        XCTAssertGreaterThan(ends.map(\.z).min() ?? -1, 0.015, "every hair is out of the surface plane")
        let top = m.ribbons.flatMap { [$0.a, $0.b] }.max { $0.z < $1.z }!
        XCTAssertGreaterThan(place(top).y, 0.030 + 0.003, "the highest hair (the arch) is towards the forehead")
        let low = m.ribbons.flatMap { [$0.a, $0.b] }.min { $0.z < $1.z }!
        XCTAssertLessThan(place(low).y, place(top).y)
    }

    func testTheOtherBrowIsAMirrorImage() throws {
        let m = try mesh()
        let right = try XCTUnwrap(BrowHairPlacement.frame(mesh: m, head: SIMD3(0.012, 0.03, 0.015), tail: SIMD3(0.060, 0.03, 0.015), normal: normal, forehead: forehead))
        let left = try XCTUnwrap(BrowHairPlacement.frame(mesh: m, head: SIMD3(-0.012, 0.03, 0.015), tail: SIMD3(-0.060, 0.03, 0.015), normal: normal, forehead: forehead))
        func det(_ f: BrowHairPlacement.Frame) -> Float {
            simd_determinant(simd_float3x3(SIMD3(f.matrix.columns.0.x, f.matrix.columns.0.y, f.matrix.columns.0.z),
                                           SIMD3(f.matrix.columns.1.x, f.matrix.columns.1.y, f.matrix.columns.1.z),
                                           SIMD3(f.matrix.columns.2.x, f.matrix.columns.2.y, f.matrix.columns.2.z)))
        }
        XCTAssertGreaterThan(det(right), 0)
        XCTAssertLessThan(det(left), 0, "a reflection, so the pattern is mirrored and the arch still points up")
        let p = SIMD4<Float>(m.ribbons[10].a, 1)
        let a = right.matrix * p, b = left.matrix * p
        XCTAssertEqual(a.x, -b.x, accuracy: 1e-5); XCTAssertEqual(a.y, b.y, accuracy: 1e-5); XCTAssertEqual(a.z, b.z, accuracy: 1e-5)
    }

    func testPlacementRefusesDegenerateInput() throws {
        let m = try mesh()
        XCTAssertNil(BrowHairPlacement.frame(mesh: m, head: .zero, tail: .zero, normal: normal, forehead: forehead))
        XCTAssertNil(BrowHairPlacement.frame(mesh: m, head: .zero, tail: SIMD3(0.05, 0, 0), normal: .zero, forehead: forehead))
        XCTAssertNil(BrowHairPlacement.frame(mesh: m, head: .zero, tail: SIMD3(0.05, 0, 0), normal: SIMD3(1, 0, 0), forehead: forehead), "normal along the chord")
    }

    // MARK: Metal

    private func changed(_ pixels: Data, from base: Data) -> [Int] {
        (0..<pixels.count / 4).filter { i in (0..<3).contains { pixels[i * 4 + $0] != base[i * 4 + $0] } }
    }

    func testHairPipelineDrawsTheBrowWhereItBelongs() throws {
        let base = try BeautyBlushEngine.renderBrowHairFixture(intensity: 0)
        let hairy = try BeautyBlushEngine.renderBrowHairFixture(intensity: 1)
        let drawn = changed(hairy, from: base)
        XCTAssertGreaterThan(drawn.count, 400, "the strands darken a good part of the brow's area")
        // The brow is 54 mm wide at 30 cm in a 128 px frame (about 0.54 of the half width) and above the axis.
        let rows = drawn.map { $0 / 128 }, columns = drawn.map { $0 % 128 }
        XCTAssertLessThan(rows.max() ?? 999, 64, "above the middle of the frame")
        XCTAssertGreaterThan(columns.min() ?? 0, 20); XCTAssertLessThan(columns.max() ?? 999, 108)
        XCTAssertGreaterThan(columns.max()! - columns.min()!, 50, "most of the brow's width")
        // Hairs are dark against the grey frame.
        let dark = drawn.filter { Int(hairy[$0 * 4]) < Int(base[$0 * 4]) }.count
        XCTAssertGreaterThan(Double(dark) / Double(drawn.count), 0.95)
    }

    func testHairsBehindTheFaceAreHidden() throws {
        let base = try BeautyBlushEngine.renderBrowHairFixture(intensity: 0, occluderInFront: true)
        let covered = try BeautyBlushEngine.renderBrowHairFixture(intensity: 1, occluderInFront: true)
        XCTAssertEqual(changed(covered, from: base).count, 0, "a face surface in front of the hairs hides them (depth test)")
    }

    func testAHandOverTheBrowHidesTheHairs() throws {
        let base = try BeautyBlushEngine.renderBrowHairFixture(intensity: 0, handCovers: true)
        let covered = try BeautyBlushEngine.renderBrowHairFixture(intensity: 1, handCovers: true)
        XCTAssertEqual(changed(covered, from: base).count, 0, "the face-skin mask rejecting the area (a hand) stops the hairs drawing")
    }

    func testIntensityScalesTheHairs() throws {
        let base = try BeautyBlushEngine.renderBrowHairFixture(intensity: 0)
        func darkness(_ p: Data) -> Int { changed(p, from: base).reduce(0) { $0 + Int(base[$1 * 4]) - Int(p[$1 * 4]) } }
        let full = darkness(try BeautyBlushEngine.renderBrowHairFixture(intensity: 1)), half = darkness(try BeautyBlushEngine.renderBrowHairFixture(intensity: 0.5))
        XCTAssertGreaterThan(half, 0)
        XCTAssertLessThan(Double(half), Double(full) * 0.7)
    }
}
