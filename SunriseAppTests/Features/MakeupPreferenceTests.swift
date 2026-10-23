// -Nimah: Preference provenance, missing coverage and real mesh binding regression, not on-face acceptance.
import XCTest
import SceneKit
import UIKit
import ImageIO
import Metal
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
    // -Nimah: Sampling must ignore letterboxing and use upright pixels, not view coordinates directly.
    func testPalettePhotoSamplingUsesAspectFitAndPixelColours() throws {
        var pixels=[UInt8]()
        for _ in 0..<20 { for x in 0..<10 { pixels += x<5 ? [255,0,0,255] : [0,0,255,255] } }
        let provider=try XCTUnwrap(CGDataProvider(data:Data(pixels) as CFData))
        let image=try XCTUnwrap(CGImage(width:10,height:20,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:40,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let data=try XCTUnwrap(UIImage(cgImage:image).pngData())
        let photo=try XCTUnwrap(PalettePhoto.decode(data))
        let bounds=CGSize(width:200,height:200)
        XCTAssertNil(photo.sample(at:CGPoint(x:10,y:100),in:bounds),"Outside the fitted photo")
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        try XCTUnwrap(photo.sample(at:CGPoint(x:70,y:100),in:bounds)).getRed(&r,green:&g,blue:&b,alpha:&a)
        XCTAssertGreaterThan(r,0.95);XCTAssertLessThan(b,0.05)
        try XCTUnwrap(photo.sample(at:CGPoint(x:130,y:100),in:bounds)).getRed(&r,green:&g,blue:&b,alpha:&a)
        XCTAssertGreaterThan(b,0.95);XCTAssertLessThan(r,0.05)
        // -Nimah: A phone photo with EXIF rotation must display and sample the same upright raster.
        let rotatedData=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(rotatedData,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyOrientation:6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let rotated=try XCTUnwrap(PalettePhoto.decode(rotatedData as Data))
        XCTAssertEqual(rotated.width,20);XCTAssertEqual(rotated.height,10)
        XCTAssertNil(PalettePhoto.decode(Data([0,1,2])))
    }
    @MainActor func testCustomColourKeepsPlacementAndTransfersToTutorial() throws {
        let home=TryOnHomeModel(plan:MakeupPlan(shape:.heart),assessment:.init(shape:.heart,origin:.analysis),checker:MockFaceTrackingChecker(),hasLaunchFit:true)
        let assigned=try XCTUnwrap(home.brow.selectedBlush).id
        let shade=MakeupShade(id:"custom.test",name:"Custom colour",red:0.8,green:0.2,blue:0.4,opacity:0.36)
        home.choose(shade:shade);home.setIntensity(0.8)
        XCTAssertEqual(home.brow.selectedBlush?.id,assigned)
        XCTAssertEqual(home.liveConfiguration.blushLayer.tint,SIMD3<Float>(0.8,0.2,0.4))
        home.choose(.eyebrow)
        XCTAssertEqual(home.shades[.blush],shade)
        let tutorial=EyebrowViewModel(checker:MockFaceTrackingChecker(),assessment:.init(shape:.heart,origin:.analysis),initialRegion:.blush,
            initialShade:shade,initialIntensity:0.8,startTutorial:true)
        XCTAssertEqual(tutorial.phase,.tutorial)
        XCTAssertEqual(tutorial.configuration.shadeTint,SIMD3<Float>(0.8,0.2,0.4))
        XCTAssertEqual(tutorial.configuration.previewIntensity,0.8)
        XCTAssertEqual(tutorial.selectedBlush?.id,assigned)
        home.deactivate()
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
    // -Nimah: A combined request must retain both render inputs; hiding guides must not hide makeup.
    func testCombinedSnapshotContainsBrowAndBlush() async throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:Provider(result:f.detection()),requiredScanSamples:1)
        pipeline.reset(anchorID:f.anchor)
        pipeline.calibrate(input:try f.input(),style:.softArch,blushStyle:.apple)
        for _ in 0..<100 {
            if pipeline.snapshot(style:.softArch,includeBrow:true,blushStyle:.apple).ready { break }
            try await Task.sleep(for:.milliseconds(25))
        }
        var configuration=EyebrowConfiguration();configuration.layered=true;configuration.showGuide=false
        configuration.browLayer.on=true;configuration.blushLayer.on=true
        let snapshot=pipeline.snapshot(style:.softArch,includeBrow:configuration.needsBrow,blushStyle:configuration.needsBlush ? .apple : nil)
        XCTAssertNotNil(snapshot.guide);XCTAssertNotNil(snapshot.blushGuide)
        let renderer=FaceRegionPreviewRenderer()
        configuration.region = .blush;configuration.showMakeupPreview=true
        renderer.update(brow:nil,forehead:nil,blush:snapshot.blushGuide,vertices:f.vertices,triangles:try f.region().triangles,configuration:configuration)
        XCTAssertFalse(renderer.root.isHidden)
        XCTAssertFalse(renderer.root.childNodes.isEmpty)
        for node in renderer.root.childNodes {
            XCTAssertEqual(node.renderingOrder,1)
            XCTAssertEqual(try XCTUnwrap(node.geometry?.firstMaterial?.transparency),0.85,accuracy:0.00001)
        }
    }
    // -Nimah: Render the actual pigment mesh, not just assert that a node exists.
    @MainActor func testBlushRendersVisibleColourPixels() throws {
        guard let device=MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal renderer unavailable") }
        let f=BrowFixture(),region=try f.region()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.apple))
        let pigment=FaceRegionPreviewRenderer()
        var configuration=EyebrowConfiguration();configuration.region = .blush;configuration.showMakeupPreview=true
        configuration.shadeTint=SIMD3(1,0,0)
        pigment.update(brow:nil,forehead:nil,blush:guide,vertices:region.restVertices,triangles:region.triangles,configuration:configuration)
        let scene=SCNScene();scene.background.contents=UIColor.white;scene.rootNode.addChildNode(pigment.root)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true
        camera.camera?.orthographicScale=0.2;camera.camera?.zNear=0.01;camera.position=SCNVector3(0,0,1)
        scene.rootNode.addChildNode(camera)
        let renderer=SCNRenderer(device:device,options:nil);renderer.scene=scene;renderer.pointOfView=camera
        let image=renderer.snapshot(atTime:0,with:CGSize(width:256,height:256),antialiasingMode:.none)
        let photo=try XCTUnwrap(image.pngData().flatMap(PalettePhoto.decode))
        var coloured=0
        for offset in stride(from:0,to:photo.rgba.count,by:4) {
            if photo.rgba[offset]>photo.rgba[offset+1]+min(40,255-photo.rgba[offset+1]) && photo.rgba[offset+1]<200 { coloured += 1 }
        }
        XCTAssertGreaterThan(coloured,40,"Actual SceneKit output must contain visible blush pigment")
    }
    // -Nimah: Fit at launch once; try-on, tutorial and new anchors reuse it without calling Vision.
    func testLaunchFitSurvivesTryOnSessionRecreationWithoutAnotherScan() async throws {
        struct InitialProvider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        struct ForbiddenProvider:FaceLandmarkProviding {
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] {
                XCTFail("Try-on must not start a new landmark scan");return []
            }
        }
        let f=BrowFixture(),input=try f.input(),cache=LaunchMakeupFit()
        XCTAssertTrue(cache.prepare(input,provider:InitialProvider(result:f.detection())))
        let pipeline=EyebrowTrackingPipeline(provider:ForbiddenProvider())
        for anchor in [f.anchor,UUID()] {
            pipeline.reset(anchorID:anchor)
            pipeline.followLaunchFit(anchorID:anchor,vertices:input.vertices,triangles:input.triangles,
                timestamp:input.timestamp,style:.softArch,blushStyle:.apple,cache:cache)
            for _ in 0..<100 {
                if pipeline.snapshot(style:.softArch,includeBrow:true,blushStyle:.apple).guide != nil { break }
                try await Task.sleep(for:.milliseconds(25))
            }
            let snapshot=pipeline.snapshot(style:.softArch,includeBrow:true,blushStyle:.apple)
            XCTAssertNotNil(snapshot.guide);XCTAssertNotNil(snapshot.blushGuide)
        }
        XCTAssertNil(cache.fittedRegion(anchorID:f.anchor,vertices:[],triangles:[],timestamp:0))
        cache.clear()
        XCTAssertNil(cache.fittedRegion(anchorID:f.anchor,vertices:input.vertices,triangles:input.triangles,timestamp:0))
    }
    @MainActor func testTryOnEnablesAllAssignedToolsAndUsesLaunchFitting() {
        let eyes=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:1.5))
        let home=TryOnHomeModel(plan:MakeupPlan(shape:.heart,eyeScan:eyes),assessment:.init(shape:.heart,origin:.analysis),checker:MockFaceTrackingChecker(),hasLaunchFit:true)
        XCTAssertEqual(home.enabled,Set(TryOnTool.allCases))
        XCTAssertTrue(home.liveConfiguration.usesLaunchFit)
        XCTAssertTrue(home.liveConfiguration.browLayer.on);XCTAssertTrue(home.liveConfiguration.blushLayer.on)
        home.deactivate()
    }
    // -Nimah: Real brow contours can be fitted without pretending missing pupil/nose points exist.
    func testLaunchFitAcceptsMeasuredBrowsWithoutOptionalFormulaPoints() throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [result] }
        }
        let fixture=BrowFixture(),input=try fixture.input(),cache=LaunchMakeupFit()
        var detected=fixture.detection();detected.eyeScan=nil
        XCTAssertTrue(cache.prepare(input,provider:Provider(result:detected)))
        let region=try XCTUnwrap(cache.fittedRegion(anchorID:fixture.anchor,vertices:input.vertices,triangles:input.triangles,timestamp:0))
        XCTAssertTrue(region.brows.allSatisfy { $0.mapping == nil })
        XCTAssertNotNil(EyebrowGuideGenerator.make(region:region,style:.natural))
        struct Empty:FaceLandmarkProviding { func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { [] } }
        XCTAssertFalse(cache.prepare(input,provider:Empty()))
        XCTAssertTrue(cache.hasFit,"A later bad frame must not erase the successful initial fit")
    }
    // -Nimah: Retry a rejected early frame during the same launch scan, without queueing or erasing a valid fit.
    @MainActor func testLaunchCollectorRetriesFramesUntilOneFits() async throws {
        final class Provider:FaceLandmarkProviding,@unchecked Sendable {
            private let lock=NSLock()
            private var attempts=0
            let result:DetectedEyebrows
            init(_ result:DetectedEyebrows) { self.result=result }
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] {
                lock.lock();defer { lock.unlock() };attempts += 1
                return attempts==1 ? [] : [result]
            }
        }
        let fixture=BrowFixture(),input=try fixture.input(),cache=LaunchMakeupFit(),provider=Provider(fixture.detection())
        let collector=LaunchFitPreparation(cache:cache,provider:provider)
        collector.submit(input)
        let first=await collector.finish();XCTAssertFalse(first)
        collector.submit(input)
        let second=await collector.finish();XCTAssertTrue(second)
        XCTAssertTrue(cache.hasFit)
    }
    @MainActor func testMissingFitDisablesOnlyUnavailablePigment() {
        let eyes=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:1.5))
        let home=TryOnHomeModel(plan:MakeupPlan(shape:.heart,eyeScan:eyes),assessment:.init(shape:.heart,origin:.analysis),checker:MockFaceTrackingChecker(),hasLaunchFit:false)
        XCTAssertFalse(home.canTry(.eyebrow));XCTAssertFalse(home.canTry(.blush))
        XCTAssertTrue(home.canTry(.eyeliner))
        home.deactivate()
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
