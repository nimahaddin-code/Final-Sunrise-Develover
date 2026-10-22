// -Nimah: Preference provenance, missing coverage and real mesh binding regression, not on-face acceptance.
import XCTest
import SceneKit
@testable import SunriseApp

final class MakeupPreferenceTests:XCTestCase {
    func testReferenceCoverageDoesNotInventRectanglePearOrUnknownRecommendations() {
        for shape:MakeupFaceShape in [.rectangle,.pear,.unknown] {
            XCTAssertTrue(MakeupPreferenceCatalog.browOptions(for:shape).isEmpty)
            XCTAssertTrue(MakeupPreferenceCatalog.blushOptions(for:shape).isEmpty)
        }
        XCTAssertEqual(MakeupFaceShape.allCases.count,9)
        XCTAssertEqual(Set(MakeupPreferenceCatalog.brows.map(\.id)).count,MakeupPreferenceCatalog.brows.count)
        XCTAssertEqual(Set(MakeupPreferenceCatalog.blush.map(\.id)).count,MakeupPreferenceCatalog.blush.count)
        XCTAssertTrue(MakeupPreferenceCatalog.blush.filter { $0.source.hasPrefix("E") }.allSatisfy { $0.evidence == .cheekOnlyInterpretation })
    }
    func testOvalAndSquareExposeDifferentSourcePlacements() {
        let oval=MakeupPreferenceCatalog.blushOptions(for:.oval)
        XCTAssertEqual(oval.first(where:{ $0.source=="A" })?.style,.outerSweep)
        XCTAssertEqual(oval.first(where:{ $0.source=="B" })?.style,.cheekbone)
        XCTAssertEqual(oval.first(where:{ $0.source=="D" })?.style,.apple)
        let square=MakeupPreferenceCatalog.blushOptions(for:.square)
        XCTAssertEqual(square.first(where:{ $0.source=="B" })?.style,.apple)
        XCTAssertEqual(square.first(where:{ $0.source=="D" })?.style,.diagonalBlend)
        for shape in MakeupFaceShape.allCases {
            let options=MakeupPreferenceCatalog.blushOptions(for:shape)
            if let b=options.first(where:{ $0.source=="B" }),let c=options.first(where:{ $0.source=="C" }) { XCTAssertEqual(b.style,c.style) }
        }
    }
    // -Nimah: Scan assignment is authoritative, including stale catalog actions and missing coverage.
    @MainActor func testScanAssignsOneReferenceAndRejectsOtherStyles() throws {
        for shape in [MakeupFaceShape.oval,.round,.square,.oblong,.heart,.diamond] {
            let model=EyebrowViewModel(checker:MockFaceTrackingChecker(),assessment:.init(shape:shape,origin:.analysis),initialRegion:.blush)
            XCTAssertEqual(model.browOptions.count,1)
            XCTAssertEqual(model.blushOptions.count,1)
            XCTAssertEqual(model.selectedBrow?.shape,shape)
            XCTAssertEqual(model.selectedBlush?.shape,shape)
            let assigned=try XCTUnwrap(model.selectedBlush)
            for other in MakeupPreferenceCatalog.blush where other.id != assigned.id { model.choose(other) }
            model.explore(BlushPlacementStyle.templeSweep)
            XCTAssertEqual(model.selectedBlush?.id,assigned.id)
            XCTAssertEqual(model.configuration.blushStyle,assigned.style)
        }
        let model=EyebrowViewModel(checker:MockFaceTrackingChecker(),assessment:.init(shape:.pear,origin:.analysis),initialRegion:.blush)
        XCTAssertNil(model.selectedBrow); XCTAssertNil(model.selectedBlush)
        XCTAssertFalse(model.liveConfiguration.showMakeupPreview)
        model.beginTutorial(); XCTAssertEqual(model.phase,.chooseStyle)
        model.applyAssessment(.init(shape:.oval))
        XCTAssertFalse(model.hasRecommendation,"Manual labels are not saved scan outputs")
    }
    func testAllBlushStylesStayOnCheeksAndClosedAreasFollowMesh() throws {
        let f=BrowFixture(),region=try f.region()
        var footprints:[BlushPlacementStyle:[SIMD3<Float>]]=[:]
        for style in BlushPlacementStyle.allCases {
            let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:style),style.title)
            XCTAssertEqual(guide.areas.count,style == .placementDots ? 8 : 2)
            for area in guide.areas {
                let points=area.boundary.compactMap { $0.position(in:region.restVertices) }
                XCTAssertEqual(points.count,area.boundary.count)
                XCTAssertLessThan(simd_distance(points.first!,points.last!),0.00001)
                XCTAssertTrue(points.allSatisfy { abs($0.x)>0.019 && $0.y<0.024 })
                let moved=region.restVertices.map { $0+SIMD3<Float>(0.001,0.002,0.003) }
                let before=try XCTUnwrap(area.boundary[0].position(in:region.restVertices))
                let after=try XCTUnwrap(area.boundary[0].position(in:moved))
                XCTAssertLessThan(simd_distance(after,before+SIMD3(0.001,0.002,0.003)),0.00001)
            }
            footprints[style]=guide.areas.flatMap(\.boundary).compactMap { $0.position(in:region.restVertices) }
        }
        func averageY(_ style:BlushPlacementStyle) -> Float { let p=footprints[style]!;return p.map(\.y).reduce(0,+)/Float(p.count) }
        XCTAssertGreaterThan(averageY(.highLift),averageY(.apple))
        XCTAssertNotEqual(footprints[.wideHorizontal],footprints[.diagonalBlend])
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.wideHorizontal))
        XCTAssertFalse(guide.blendArrows.isEmpty)
    }
    func testBlushRendererBeforeAndNoGuideClearStaleLayers() throws {
        let f=BrowFixture(),region=try f.region()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.apple))
        let renderer=FaceRegionPreviewRenderer()
        var configuration=EyebrowConfiguration();configuration.region = .blush;configuration.showMakeupPreview=true
        renderer.update(brow:nil,forehead:nil,blush:guide,vertices:region.restVertices,triangles:region.triangles,configuration:configuration)
        XCTAssertFalse(renderer.root.isHidden)
        XCTAssertEqual(renderer.root.childNodes.count,2)
        configuration.previewAfter=false
        renderer.update(brow:nil,forehead:nil,blush:guide,vertices:region.restVertices,triangles:region.triangles,configuration:configuration)
        XCTAssertTrue(renderer.root.isHidden)
        configuration.previewAfter=true
        renderer.update(brow:nil,forehead:nil,blush:nil,vertices:region.restVertices,triangles:region.triangles,configuration:configuration)
        XCTAssertTrue(renderer.root.isHidden)
    }
    func testBlushPipelineOnlyPublishesSelectedPlacementAndDropsItAfterLoss() async throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:Provider(result:f.detection()),requiredScanSamples:1)
        pipeline.reset(anchorID:f.anchor)
        pipeline.calibrate(input:try f.input(),style:.softArch,blushStyle:.apple)
        for _ in 0..<100 {
            if pipeline.snapshot(style:.softArch,blushStyle:.apple).ready { break }
            try await Task.sleep(for:.milliseconds(25))
        }
        let snapshot=pipeline.snapshot(style:.softArch,blushStyle:.apple)
        XCTAssertNotNil(snapshot.blushGuide);XCTAssertNil(snapshot.guide);XCTAssertNil(snapshot.foreheadGuide)
        XCTAssertFalse(pipeline.snapshot(style:.softArch,blushStyle:.templeSweep).ready)
        pipeline.trackingLost();XCTAssertFalse(pipeline.snapshot(style:.softArch,blushStyle:.apple).ready)
    }
    // -Nimah: Repeated mapping must recover after loss/reset, not just the first successful scan.
    func testRepeatedScanAfterLossAndRefit() async throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:Provider(result:f.detection()),requiredScanSamples:1)
        for style in [BlushPlacementStyle.apple,.cheekbone,.templeSweep,.apple] {
            pipeline.reset(anchorID:f.anchor)
            pipeline.calibrate(input:try f.input(),style:.natural,blushStyle:style)
            for _ in 0..<100 {
                if pipeline.snapshot(style:.natural,blushStyle:style).ready { break }
                try await Task.sleep(for:.milliseconds(25))
            }
            XCTAssertNotNil(pipeline.snapshot(style:.natural,blushStyle:style).blushGuide)
            pipeline.trackingLost(timestamp:10)
            XCTAssertFalse(pipeline.snapshot(style:.natural,blushStyle:style).ready)
            pipeline.resumeTracking(anchorID:f.anchor)
            XCTAssertTrue(pipeline.snapshot(style:.natural,blushStyle:style).ready, "Brief dropout must resume without a new scan")
            pipeline.trackingLost(timestamp:20)
            pipeline.trackingLost(timestamp:21.1)
            pipeline.resumeTracking(anchorID:f.anchor)
            XCTAssertFalse(pipeline.snapshot(style:.natural,blushStyle:style).ready, "Long loss must require fresh mapping")
        }
    }
    @MainActor func testScanInstructionsExplainDistanceAndMissingFace() {
        let camera=FaceCameraState()
        XCTAssertTrue(camera.scanInstruction.contains("kedua mata"))
        camera.tracked=true; camera.distanceMeters=0.20
        XCTAssertTrue(camera.scanInstruction.contains("Mundurkan"))
        camera.distanceMeters=0.75
        XCTAssertTrue(camera.scanInstruction.contains("Dekatkan"))
        camera.distanceMeters=0.40;camera.eyebrowMessage="Keep still"
        XCTAssertEqual(camera.scanInstruction,"Keep still")
    }

    // -Nimah: Reproduce a second try after the user viewed Before or hid the guide.
    @MainActor func testNewTryRestoresVisiblePreview() {
        let model=EyebrowViewModel(checker:MockFaceTrackingChecker())
        model.applyAssessment(.init(shape:.oval,origin:.analysis))
        model.configuration.previewAfter=false;model.configuration.showGuide=false;model.configuration.previewIntensity=0
        model.select(.blush)
        XCTAssertTrue(model.liveConfiguration.showMakeupPreview)
        XCTAssertTrue(model.liveConfiguration.showGuide)
        model.configuration.previewAfter=false;model.configuration.showGuide=false
        model.choose(model.blushOptions[0])
        XCTAssertTrue(model.liveConfiguration.showMakeupPreview)
        XCTAssertTrue(model.liveConfiguration.showGuide)
        model.configuration.previewAfter=false
        model.explore(EyebrowStyle.natural);model.select(.eyebrows)
        XCTAssertTrue(model.liveConfiguration.showMakeupPreview)
    }

}
