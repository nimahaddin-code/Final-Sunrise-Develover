// -Nimah: Regresi shape outline dan area forehead; fixture bukan bukti hairline atau live accuracy.
import XCTest
import ARKit
import SceneKit
@testable import SunriseApp

final class ForeheadGuideTests:XCTestCase {
    func testAllForeheadStylesProduceClosedAreasAboveBrows() throws {
        let fixture=BrowFixture(),region=try fixture.region()
        for style in ForeheadStyle.allCases {
            let guide=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:style,height:0.8),style.title)
            XCTAssertEqual(guide.areas.count,style == .temple ? 2 : 1)
            for area in guide.areas {
                let points=area.boundary.compactMap { $0.position(in:fixture.vertices) }
                XCTAssertEqual(points.count,area.boundary.count)
                XCTAssertLessThan(simd_distance(points.first!,points.last!),0.00001)
                XCTAssertTrue(points.allSatisfy { $0.y>=guide.lowerY && $0.y<=0.12 && abs($0.x)<0.07 })
            }
        }
    }
    func testHeightAdjustmentChangesTopLimitAndPreservesLowerClearance() throws {
        let f=BrowFixture(),region=try f.region()
        let low=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:.hairline,height:0.45))
        let high=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:.hairline,height:1))
        func top(_ guide:ForeheadGuide) -> Float { guide.areas.flatMap(\.boundary).compactMap { $0.position(in:f.vertices)?.y }.max()! }
        XCTAssertGreaterThan(top(high)-top(low),0.015)
        XCTAssertEqual(low.lowerY,high.lowerY)
        XCTAssertNil(ForeheadGuideGenerator.make(region:region,style:.hairline,height:.nan))
    }
    func testInsufficientForeheadMeshHidesAreaRatherThanProjectingOutside() throws {
        let f=BrowFixture(),base=try f.region()
        let vertices=f.vertices.map { SIMD3($0.x,min($0.y,0.065),$0.z) }
        let limited=EyebrowRegion(brows:base.brows,faceObservationConfidence:base.faceObservationConfidence,timestamp:1,
            anchorID:base.anchorID,restVertices:vertices,triangles:f.triangles)
        XCTAssertNil(ForeheadGuideGenerator.make(region:limited,style:.softSculpt,height:0.8))
    }
    func testContourAndHighlightHaveDifferentFootprints() throws {
        let f=BrowFixture(),region=try f.region()
        let contour=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:.softSculpt,height:0.8))
        let highlight=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:.centerHighlight,height:0.8))
        func span(_ guide:ForeheadGuide) -> Float {
            let x=guide.areas.flatMap(\.boundary).compactMap { $0.position(in:f.vertices)?.x }; return x.max()!-x.min()!
        }
        XCTAssertGreaterThan(span(contour),span(highlight)*2)
        XCTAssertEqual(ForeheadStyle.softGlow.category,.highlight)
    }
    func testBrowOutlineHasUpperLowerEdgesAndClosedTail() throws {
        let f=BrowFixture(),guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:try f.region(),style:.softNatural))
        for curve in guide.curves {
            let start=try XCTUnwrap(curve.outline[0]!.position(in:f.vertices))
            let end=try XCTUnwrap(curve.outline[curve.outline.count-1]!.position(in:f.vertices))
            XCTAssertLessThan(simd_distance(start,end),0.00001)
            let middle=try XCTUnwrap(curve.samples[20]?.position(in:f.vertices))
            let upper=try XCTUnwrap(curve.outline[20]?.position(in:f.vertices))
            let lower=try XCTUnwrap(curve.outline[61]?.position(in:f.vertices))
            XCTAssertGreaterThan(upper.y,middle.y); XCTAssertLessThan(lower.y,middle.y)
        }
    }
    @MainActor func testRegionStyleTutorialFlowAndStepSpecificGuides() async {
        struct Supported:FaceTrackingAvailabilityChecking { func availability() async -> FaceTrackingAvailability { .supported } }
        let model=EyebrowViewModel(checker:Supported())
        XCTAssertEqual(model.phase,.positionFace)
        model.phase = .tracking; XCTAssertTrue(model.liveConfiguration.showTrackingPoints)
        // -Nimah: Region/tutorial tests use a saved scan; missing scans no longer show makeup.
        model.applyAssessment(.init(shape:.oval,origin:.analysis))
        model.phase = .chooseRegion; XCTAssertTrue(model.liveConfiguration.showAllRegions)
        model.select(.forehead); XCTAssertEqual(model.phase,.chooseStyle)
        model.beginTutorial(); XCTAssertEqual(model.lessons.count,3); XCTAssertNil(model.liveConfiguration.tutorialStep)
        model.nextStep(); model.nextStep(); model.nextStep(); XCTAssertEqual(model.phase,.chooseStyle)
        model.select(.eyebrows); model.beginTutorial(); XCTAssertEqual(model.lessons.count,4)
        XCTAssertEqual(model.liveConfiguration.tutorialStep,0)
        model.nextStep(); XCTAssertEqual(model.liveConfiguration.tutorialStep,1)
        model.previousStep(); XCTAssertEqual(model.stepIndex,0)
    }
    func testForeheadRendererFollowsVerticesAndHidesOnLostGuide() throws {
        let f=BrowFixture(),guide=try XCTUnwrap(ForeheadGuideGenerator.make(region:try f.region(),style:.softGlow,height:0.8))
        let renderer=ForeheadSceneRenderer()
        renderer.update(guide:guide,vertices:f.vertices,configuration:.init(mode:.dots))
        let dot=try XCTUnwrap(renderer.root.childNodes.first(where: { $0.geometry is SCNSphere && !$0.isHidden }))
        let old=dot.simdPosition,delta=SIMD3<Float>(0.003,0.002,0.001)
        renderer.update(guide:guide,vertices:f.vertices.map { $0+delta },configuration:.init(mode:.dots))
        XCTAssertLessThan(simd_distance(dot.simdPosition,old+delta),0.00001)
        renderer.update(guide:nil,vertices:f.vertices,configuration:.init()); XCTAssertTrue(renderer.root.isHidden)
    }
    func testPipelineKeepsSelectedRegionSeparateAndDropsForeheadAfterReset() async throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:Provider(result:f.detection()),requiredScanSamples:1)
        pipeline.reset(anchorID:f.anchor)
        pipeline.calibrate(input:try f.input(),style:.flatStraight,foreheadStyle:.softSculpt,height:0.8)
        for _ in 0..<60 {
            if pipeline.snapshot(style:.flatStraight,foreheadStyle:.softSculpt).ready { break }
            try await Task.sleep(for:.milliseconds(25))
        }
        let forehead=pipeline.snapshot(style:.flatStraight,foreheadStyle:.softSculpt)
        XCTAssertNotNil(forehead.foreheadGuide); XCTAssertNil(forehead.guide)
        let all=pipeline.snapshot(style:.flatStraight,foreheadStyle:.softSculpt,includeBrow:true)
        XCTAssertNotNil(all.guide); XCTAssertNotNil(all.foreheadGuide)
        pipeline.trackingLost()
        XCTAssertFalse(pipeline.snapshot(style:.flatStraight,foreheadStyle:.softSculpt).ready)
    }
    @MainActor func testForeheadAreasBindToNativeNeutralMesh() throws {
        guard ARFaceTrackingConfiguration.isSupported else { throw XCTSkip("Native forehead mesh requires supported hardware") }
        let neutral=try XCTUnwrap(ARFaceGeometry(blendShapes:[:]))
        let vertices=Array(neutral.vertices),triangles=Array(neutral.triangleIndices)
        var brows:[EyebrowRegion.Brow]=[]
        for sign:Float in [-1,1] {
            let points:[SIMD2<Float>]=[.init(sign*0.017,0.045),.init(sign*0.032,0.05),.init(sign*0.05,0.045)]
            let attachments=points.compactMap { SurfaceAttachment.bind($0,vertices:vertices,triangles:triangles,minimumZ:-0.1) }
            XCTAssertEqual(attachments.count,3)
            brows.append(.init(side:sign<0 ? .left : .right,landmarks:attachments))
        }
        let region=EyebrowRegion(brows:brows,faceObservationConfidence:1,timestamp:0,anchorID:UUID(),restVertices:vertices,triangles:triangles)
        for style in ForeheadStyle.allCases {
            let guide=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:style,height:0.8),style.title)
            XCTAssertFalse(guide.areas.isEmpty)
        }
    }
}

// -Nimah: Verify original mode, concave masks and skin deformation rather than UI labels alone.
extension ForeheadGuideTests {
    func testPreviewCoverageRespectsConcaveRegionAndSoftEdge() {
        let shape:[SIMD2<Float>]=[.init(0,0),.init(3,0),.init(3,1),.init(1,1),.init(1,3),.init(0,3)]
        XCTAssertEqual(FaceRegionPreviewRenderer.coverage(.init(2,2),polygon:shape,feather:0.2),0)
        XCTAssertEqual(FaceRegionPreviewRenderer.coverage(.init(0.5,2),polygon:shape,feather:0.2),1)
        let edge=FaceRegionPreviewRenderer.coverage(.init(0.05,2),polygon:shape,feather:0.2)
        XCTAssertGreaterThan(edge,0); XCTAssertLessThan(edge,1)
    }
    @MainActor func testBeforeHidesEffectsGuideAndDebugWithoutLosingSelection() {
        let model=EyebrowViewModel(checker:MockFaceTrackingChecker())
        model.select(.forehead); model.configuration.foreheadStyle = .softGlow
        model.configuration.debugMesh=true; model.configuration.previewAfter=false
        XCTAssertFalse(model.liveConfiguration.showMakeupPreview)
        XCTAssertFalse(model.liveConfiguration.showGuide)
        XCTAssertFalse(model.liveConfiguration.debugMesh)
        model.configuration.previewAfter=true
        XCTAssertTrue(model.liveConfiguration.showMakeupPreview)
        XCTAssertEqual(model.liveConfiguration.foreheadStyle,.softGlow)
    }
    func testLivePreviewFollowsMeshAndBeforeHidesEveryPatch() throws {
        let fixture=BrowFixture(),region=try fixture.region()
        let guide=try XCTUnwrap(ForeheadGuideGenerator.make(region:region,style:.softGlow,height:0.8))
        let renderer=FaceRegionPreviewRenderer()
        var options=EyebrowConfiguration(); options.region = .forehead; options.showMakeupPreview=true
        renderer.update(brow:nil,forehead:guide,vertices:region.restVertices,triangles:region.triangles,configuration:options)
        XCTAssertFalse(renderer.root.isHidden)
        let initial=try XCTUnwrap(renderer.root.childNodes.first?.geometry)
        XCTAssertGreaterThan(initial.sources(for:.color).first?.vectorCount ?? 0,0)
        let source=try XCTUnwrap(initial.sources(for:.vertex).first)
        let initialData=source.data
        // -Nimah: Per-frame mesh updates reuse immutable topology/color buffers.
        let cachedColor=try XCTUnwrap(initial.sources(for:.color).first)
        let cachedElement=try XCTUnwrap(initial.elements.first)
        options.previewIntensity=0.3
        let moved=region.restVertices.map { $0+SIMD3<Float>(0,0.01,0) }
        renderer.update(brow:nil,forehead:guide,vertices:moved,triangles:region.triangles,configuration:options)
        let updated=try XCTUnwrap(renderer.root.childNodes.first?.geometry)
        XCTAssertNotEqual(initialData,updated.sources(for:.vertex).first?.data)
        XCTAssertTrue(cachedColor === updated.sources(for:.color).first)
        XCTAssertTrue(cachedElement === updated.elements.first)
        XCTAssertEqual(updated.firstMaterial?.transparency ?? -1,0.3,accuracy:0.001)
        options.previewAfter=false
        renderer.update(brow:nil,forehead:guide,vertices:moved,triangles:region.triangles,configuration:options)
        XCTAssertTrue(renderer.root.isHidden)
    }
}
