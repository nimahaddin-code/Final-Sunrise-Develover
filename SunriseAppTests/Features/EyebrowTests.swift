// -Nimah: Geometri sintetis, Vision fixture dan lifecycle regression; bukan klaim akurasi wajah nyata.
import XCTest
import ARKit
import AVFoundation
import SceneKit
import UIKit
import CoreImage
@testable import SunriseApp

// -Nimah: Fixture bersama untuk regresi brow dan forehead.
struct BrowFixture {
    var vertices:[SIMD3<Float>]=[]
    var triangles:[Int16]=[]
    let projection:FaceLandmarkProjection
    let anchor=UUID()
    let leftEye=SIMD3<Float>(0.032,0.03,0.04),rightEye=SIMD3<Float>(-0.032,0.03,0.04)
    init() {
        let columns=32,rows=44
        for row in 0...rows { for column in 0...columns {
            vertices.append(SIMD3(-0.08+Float(column)*0.005,-0.1+Float(row)*0.005,0.04))
        } }
        for row in 0..<rows { for column in 0..<columns {
            let a=row*(columns+1)+column,b=a+1,c=a+columns+1,d=c+1
            triangles.append(contentsOf:[a,b,c,b,d,c].map(Int16.init))
        } }
        var transform=matrix_identity_float4x4; transform.columns.3=SIMD4(0,0,-0.4,1)
        projection=FaceLandmarkProjection(intrinsics:simd_float3x3(columns:(SIMD3(800,0,0),SIMD3(0,800,0),SIMD3(640,360,1))),
            cameraFromFace:transform,imageWidth:1280,imageHeight:720)
    }
    func detection(offsetY:Float=0) -> DetectedEyebrows {
        func points(_ sign:Float) -> [SIMD2<Float>] {
            (0...6).map { i in
                let t=Float(i)/6
                return projection.project(SIMD3(sign*(0.017+t*0.035),0.055+sin(t*Float.pi)*0.006+offsetY,0.04))!
            }
        }
        // -Nimah: Urutan Vision sengaja berbeda dari nama eye transform untuk mendeteksi swap kiri/kanan.
        func projected(_ p:SIMD3<Float>) -> SIMD2<Float> { projection.project(p)! }
        let eyes:[DetectedEyeScan.Eye]=[-Float(1),Float(1)].map { sign in
            .init(contour:(0..<8).map { i in
                let angle=Float(i)*2*Float.pi/8
                return projected(.init(sign*0.032+0.013*cos(angle),0.03+0.005*sin(angle),0.04))
            },pupil:projected(.init(sign*0.032,0.03,0.04)))
        }
        return DetectedEyebrows(first:points(-1),second:points(1),faceObservationConfidence:0.95,
            eyeScan:.init(eyes:eyes,nose:[projected(.init(-0.017,-0.015,0.04)),projected(.init(0,-0.005,0.04)),projected(.init(0.017,-0.015,0.04))]))
    }
    func region(offsetY:Float=0) throws -> EyebrowRegion {
        try XCTUnwrap(EyebrowRegionMapper.map(detection(offsetY:offsetY),projection:projection,vertices:vertices,triangles:triangles,
            leftEye:leftEye,rightEye:rightEye,timestamp:1,anchorID:anchor))
    }
    func input(timestamp:TimeInterval = 1) throws -> FaceLandmarkFrame {
        var buffer:CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil,32,32,kCVPixelFormatType_32BGRA,nil,&buffer),kCVReturnSuccess)
        return FaceLandmarkFrame(pixelBuffer:try XCTUnwrap(buffer),projection:projection,orientation:.up,timestamp:timestamp,anchorID:anchor,
            vertices:vertices,triangles:triangles,leftEye:leftEye,rightEye:rightEye)
    }
}
private struct FixtureLandmarks: FaceLandmarkProviding {
    let result:[DetectedEyebrows]
    func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { result }
}
private final class DelayedLandmarks: FaceLandmarkProviding, @unchecked Sendable {
    let started=DispatchSemaphore(value:0),resume=DispatchSemaphore(value:0)
    let result:[DetectedEyebrows]
    init(_ result:[DetectedEyebrows]) { self.result=result }
    func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] {
        started.signal(); _=resume.wait(timeout:.now()+2); return result
    }
}
final class EyebrowTests:XCTestCase {
    func testVisionOrientationInverseForAllEightEXIFOrientations() {
        let p=SIMD2<Float>(0.2,0.7)
        let cases:[(CGImagePropertyOrientation,SIMD2<Float>)]=[
            (.up,.init(0.2,0.7)),(.upMirrored,.init(0.8,0.7)),(.down,.init(0.8,0.3)),(.downMirrored,.init(0.2,0.3)),
            (.left,.init(0.3,0.2)),(.right,.init(0.7,0.8)),(.leftMirrored,.init(0.7,0.2)),(.rightMirrored,.init(0.3,0.8))]
        for (orientation,expected) in cases {
            let actual=FaceLandmarkProjection.rawPoint(fromOriented:p,orientation:orientation)
            XCTAssertEqual(actual.x,expected.x,accuracy:0.00001); XCTAssertEqual(actual.y,expected.y,accuracy:0.00001)
        }
        let raw=FaceLandmarkProjection.landmarkToRaw(CGPoint(x:0.25,y:0.75),faceBox:CGRect(x:0.1,y:0.2,width:0.4,height:0.6),orientation:.up)
        XCTAssertEqual(raw.x,0.2,accuracy:0.00001); XCTAssertEqual(raw.y,0.35,accuracy:0.00001)
    }
    func testRayBindingRoundTripsThroughPoseAndPerspective() throws {
        let fixture=BrowFixture()
        var transform=simd_float4x4(simd_quatf(angle:0.35,axis:simd_normalize(SIMD3<Float>(0.2,1,0.4))))
        transform.columns.3=SIMD4(0.02,-0.01,-0.4,1)
        let projection=FaceLandmarkProjection(intrinsics:fixture.projection.intrinsics,cameraFromFace:transform,imageWidth:1280,imageHeight:720)
        for p:SIMD3<Float> in [.init(-0.04,0.06,0.04),.init(0.03,0.07,0.04)] {
            let raw=try XCTUnwrap(projection.project(p))
            let attachment=try XCTUnwrap(projection.attachment(for:raw,vertices:fixture.vertices,triangles:fixture.triangles))
            let hit=try XCTUnwrap(attachment.position(in:fixture.vertices))
            XCTAssertLessThan(simd_distance(hit,p),0.00001)
        }
        XCTAssertNil(projection.attachment(for:.init(-1,0),vertices:fixture.vertices,triangles:fixture.triangles))
    }
    func testMapperUsesPersonalBrowPointsAndEyeTransformsForSideIdentity() throws {
        let fixture=BrowFixture(),region=try fixture.region()
        XCTAssertEqual(region.brows.count,2)
        for brow in region.brows {
            let points=brow.landmarks.compactMap { $0.position(in:fixture.vertices) }
            XCTAssertTrue(points.allSatisfy { $0.y>0.05 })
            if brow.side == .left { XCTAssertTrue(points.allSatisfy { $0.x>0 }) }
            else { XCTAssertTrue(points.allSatisfy { $0.x<0 }) }
        }
        let shifted=try fixture.region(offsetY:0.01)
        let a=region.brows[0].landmarks[0].position(in:fixture.vertices)!
        let b=shifted.brows[0].landmarks[0].position(in:fixture.vertices)!
        XCTAssertEqual(b.y-a.y,0.01,accuracy:0.00001)
    }
    func testMapperRejectsMissingLowConfidenceOrWrongRegion() {
        let f=BrowFixture(),d=f.detection()
        for detection in [DetectedEyebrows(first:[],second:d.second,faceObservationConfidence:0.9),
                          DetectedEyebrows(first:d.first,second:d.second,faceObservationConfidence:0.1),
                          DetectedEyebrows(first:d.first,second:d.first,faceObservationConfidence:0.9)] {
            XCTAssertNil(EyebrowRegionMapper.map(detection,projection:f.projection,vertices:f.vertices,triangles:f.triangles,
                leftEye:f.leftEye,rightEye:f.rightEye,timestamp:1,anchorID:f.anchor))
        }
    }
    func testStylesChangeActualCurvesAndFeatheredAddsStrokes() throws {
        let f=BrowFixture(),region=try f.region()
        var peaks:[EyebrowStyle:Float]=[:]
        for style in EyebrowStyle.allCases {
            let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:style))
            XCTAssertEqual(guide.curves.count,2)
            peaks[style]=guide.curves.flatMap(\.samples).compactMap { $0?.position(in:f.vertices)?.y }.max()
            if style == .softNatural { XCTAssertGreaterThan(guide.curves[0].strokes.count,0) }
            else { XCTAssertTrue(guide.curves[0].strokes.isEmpty) }
        }
        XCTAssertGreaterThan(peaks[.boldArch]!,peaks[.softNatural]!)
        XCTAssertGreaterThan(peaks[.softNatural]!,peaks[.flatStraight]!)
    }
    func testGuideRendererModesAndTrackingLossHideNodes() throws {
        let f=BrowFixture(),guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:try f.region(),style:.flatStraight))
        let renderer=EyebrowSceneRenderer()
        renderer.update(guide:guide,vertices:f.vertices,configuration:.init(style:.flatStraight,mode:.dots))
        XCTAssertFalse(renderer.root.isHidden)
        XCTAssertTrue(renderer.root.childNodes.filter { $0.geometry is SCNCapsule }.allSatisfy(\.isHidden))
        XCTAssertTrue(renderer.root.childNodes.filter { $0.geometry is SCNSphere && !$0.isHidden }.allSatisfy { $0.position.y>0.05 })
        renderer.update(guide:guide,vertices:f.vertices,configuration:.init(style:.flatStraight,mode:.dashed))
        XCTAssertTrue(renderer.root.childNodes.filter { $0.geometry is SCNSphere }.allSatisfy(\.isHidden))
        XCTAssertTrue(renderer.root.childNodes.contains { $0.geometry is SCNCapsule && !$0.isHidden })
        renderer.update(guide:nil,vertices:f.vertices,configuration:.init()); XCTAssertTrue(renderer.root.isHidden)
    }
    func testPipelineProducesGuidesAndRejectsResultsAfterLoss() async throws {
        let f=BrowFixture(),provider=DelayedLandmarks([f.detection()])
        let pipeline=EyebrowTrackingPipeline(provider:provider,requiredScanSamples:1)
        pipeline.reset(anchorID:f.anchor); pipeline.calibrate(input:try f.input(),style:.flatStraight)
        XCTAssertEqual(provider.started.wait(timeout:.now()+1),.success)
        pipeline.trackingLost(); provider.resume.signal()
        try await Task.sleep(for:.milliseconds(250))
        XCTAssertNil(pipeline.snapshot(style:.flatStraight).guide)
        let working=EyebrowTrackingPipeline(provider:FixtureLandmarks(result:[f.detection()]),requiredScanSamples:1)
        working.reset(anchorID:f.anchor); working.calibrate(input:try f.input(),style:.flatStraight)
        for _ in 0..<30 {
            if working.snapshot(style:.flatStraight).guide != nil { break }
            try await Task.sleep(for:.milliseconds(30))
        }
        XCTAssertNotNil(working.snapshot(style:.flatStraight).guide)
        working.reset(anchorID:UUID()); XCTAssertNil(working.snapshot(style:.flatStraight).guide)
    }
    @MainActor func testSessionLeasePreventsOldModuleFromPausingNewOwner() {
        let manager=ARFaceTrackingManager(),first=UUID(),second=UUID()
        var revocations=0
        manager.acquire(owner:first) { revocations += 1 }
        manager.acquire(owner:second) {}
        XCTAssertEqual(revocations,1); XCTAssertFalse(manager.release(owner:first)); XCTAssertTrue(manager.owns(second))
        XCTAssertTrue(manager.release(owner:second))
    }
}

// -Nimah: Vision sungguhan pada foto referensi bundled; tidak menyamakan foto ini dengan kalibrasi AR live.
extension EyebrowTests {
    func testVisionProviderFindsBrowLandmarksInBundledReference() throws {
        let image=try XCTUnwrap(UIImage(named:"GlamReference")?.cgImage)
        var buffer:CVPixelBuffer?
        let attributes=[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary
        XCTAssertEqual(CVPixelBufferCreate(nil,image.width,image.height,kCVPixelFormatType_32BGRA,attributes,&buffer),kCVReturnSuccess)
        let pixel=try XCTUnwrap(buffer)
        CIContext().render(CIImage(cgImage:image),to:pixel)
        let f=BrowFixture()
        let input=FaceLandmarkFrame(pixelBuffer:pixel,projection:f.projection,orientation:.up,timestamp:1,anchorID:f.anchor,
            vertices:f.vertices,triangles:f.triangles,leftEye:f.leftEye,rightEye:f.rightEye)
        let detected=try VisionFaceLandmarkProvider().detectEyebrows(in:input)
        XCTAssertFalse(detected.isEmpty,"Bundled face reference should provide two real Vision eyebrow regions")
        for result in detected {
            XCTAssertGreaterThanOrEqual(result.first.count,3); XCTAssertGreaterThanOrEqual(result.second.count,3)
            XCTAssertTrue((result.first+result.second).allSatisfy { $0.x>=0 && $0.x<=1 && $0.y>=0 && $0.y<=1 })
        }
    }
    @MainActor func testModulesShareOneSessionManager() {
        XCTAssertTrue(FaceCameraState().trackingManager === FaceCameraState().trackingManager)
    }
}

// -Nimah: Failure inference bukan wajah tidak terlihat; deformasi mesh harus menggerakkan guide, bukan layar.
extension EyebrowTests {
    func testPipelineReportsVisionFailureWithoutFakeGuide() async throws {
        struct FailingProvider:FaceLandmarkProviding {
            func detectEyebrows(in frame:FaceLandmarkFrame) throws -> [DetectedEyebrows] { throw NSError(domain:"VisionFixture",code:9) }
        }
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:FailingProvider())
        pipeline.reset(anchorID:f.anchor); pipeline.calibrate(input:try f.input(),style:.flatStraight)
        for _ in 0..<20 {
            if pipeline.snapshot(style:.flatStraight).message.contains("unavailable") { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertNil(pipeline.snapshot(style:.flatStraight).guide)
        XCTAssertTrue(pipeline.snapshot(style:.flatStraight).message.contains("unavailable"))
    }
    func testRenderedGuideFollowsCurrentMeshDeformation() throws {
        let f=BrowFixture(),guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:try f.region(),style:.flatStraight))
        let renderer=EyebrowSceneRenderer()
        renderer.update(guide:guide,vertices:f.vertices,configuration:.init(mode:.dots))
        let dot=try XCTUnwrap(renderer.root.childNodes.first(where:{ $0.geometry is SCNSphere && !$0.isHidden }))
        let original=dot.simdPosition,delta=SIMD3<Float>(0.003,0.005,0.002)
        renderer.update(guide:guide,vertices:f.vertices.map { $0+delta },configuration:.init(mode:.dots))
        XCTAssertLessThan(simd_distance(dot.simdPosition,original+delta),0.00001)
    }
}

// -Nimah: Formula and eye-scan gates, separate from real-face acceptance.
extension EyebrowTests {
    func testBrowFormulaUsesRayIntersectionAndRejectsInvalidGeometry() throws {
        let point=try XCTUnwrap(BrowMappingFormula.intersection(nose:.init(0.017,-0.015),through:.init(0.032,0.03),level:0.06))
        XCTAssertEqual(point.x,0.042,accuracy:0.00001); XCTAssertEqual(point.y,0.06,accuracy:0.00001)
        XCTAssertNil(BrowMappingFormula.intersection(nose:.zero,through:.init(1,0),level:1))
        XCTAssertNil(BrowMappingFormula.intersection(nose:.zero,through:.init(1,1),level:0.5))
        XCTAssertNil(BrowMappingFormula.intersection(nose:.zero,through:.init(.nan,1),level:2))
    }
    func testLiveMapperRequiresEyesPupilsAndNose() {
        let f=BrowFixture(); var detection=f.detection(); detection.eyeScan=nil
        XCTAssertNil(EyebrowRegionMapper.map(detection,projection:f.projection,vertices:f.vertices,triangles:f.triangles,
            leftEye:f.leftEye,rightEye:f.rightEye,timestamp:1,anchorID:f.anchor))
    }
    func testClosedEyeScanCannotProduceBrowGuide() throws {
        let f=BrowFixture(); var detection=f.detection(); let scan=try XCTUnwrap(detection.eyeScan)
        let eyes=scan.eyes.map { eye in
            DetectedEyeScan.Eye(contour:eye.contour.map { SIMD2($0.x,eye.pupil.y) },pupil:eye.pupil)
        }
        detection.eyeScan = .init(eyes:eyes,nose:scan.nose)
        XCTAssertNil(EyebrowRegionMapper.map(detection,projection:f.projection,vertices:f.vertices,triangles:f.triangles,
            leftEye:f.leftEye,rightEye:f.rightEye,timestamp:1,anchorID:f.anchor))
    }
    func testScannedMarksFollowNosePupilAndOuterEyeOnBothSides() throws {
        let f=BrowFixture(),region=try f.region()
        for brow in region.brows {
            let m=try XCTUnwrap(brow.mapping)
            XCTAssertEqual(m.start.x,m.ala.x,accuracy:0.00001)
            let arch=try XCTUnwrap(BrowMappingFormula.intersection(nose:.init(m.ala.x,m.ala.y),through:.init(m.pupil.x,m.pupil.y),level:m.arch.y))
            let tail=try XCTUnwrap(BrowMappingFormula.intersection(nose:.init(m.ala.x,m.ala.y),through:.init(m.outerEye.x,m.outerEye.y),level:m.tail.y))
            XCTAssertLessThan(simd_distance(arch,m.arch),0.00001); XCTAssertLessThan(simd_distance(tail,m.tail),0.00001)
        }
        let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:.softNatural))
        for curve in guide.curves {
            XCTAssertEqual(curve.keyPoints.count,3); XCTAssertEqual(curve.mappingLines.count,3)
            let m=try XCTUnwrap(region.brows.first(where:{ $0.side==curve.side })?.mapping)
            let point=try XCTUnwrap(curve.keyPoints[1].position(in:f.vertices))
            let expected=try XCTUnwrap(BrowMappingFormula.intersection(nose:.init(m.ala.x,m.ala.y),through:.init(m.pupil.x,m.pupil.y),level:point.y))
            XCTAssertEqual(point.x,expected.x,accuracy:0.00001)
        }
    }
    func testScanStabilityRejectsRepeatedFrameAndMovingBrowMapping() throws {
        let f=BrowFixture(),a=try f.region(),shifted=try f.region(offsetY:0.01)
        XCTAssertFalse(EyebrowTrackingPipeline.consistent(a,a))
        let b=EyebrowRegion(brows:shifted.brows,faceObservationConfidence:shifted.faceObservationConfidence,timestamp:2,
            anchorID:a.anchorID,restVertices:shifted.restVertices,triangles:shifted.triangles)
        XCTAssertFalse(EyebrowTrackingPipeline.consistent(a,b))
    }
    func testEyeScanNeedsThreeIndependentStableFramesBeforePreview() async throws {
        let f=BrowFixture(),pipeline=EyebrowTrackingPipeline(provider:FixtureLandmarks(result:[f.detection()]))
        pipeline.reset(anchorID:f.anchor)
        for i in 1...3 {
            pipeline.calibrate(input:try f.input(timestamp:Double(i)),style:.flatStraight)
            for _ in 0..<100 {
                let state=pipeline.snapshot(style:.flatStraight)
                if state.ready || state.message.contains("Eye scan \(i)/3") { break }
                try await Task.sleep(for:.milliseconds(20))
            }
            if i<3 { XCTAssertFalse(pipeline.snapshot(style:.flatStraight).ready) }
        }
        XCTAssertTrue(pipeline.snapshot(style:.flatStraight).ready)
        pipeline.trackingLost(); XCTAssertFalse(pipeline.snapshot(style:.flatStraight).ready)
    }
}

// -Nimah: Regression for a high arch floating above the scanned brow and eyeball-center depth bias.
extension EyebrowTests {
    func testLiveArchHeightStaysWithinOneMillimeterOfScannedArch() throws {
        let f=BrowFixture(),region=try f.region()
        for style in EyebrowStyle.allCases {
            let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:style))
            for curve in guide.curves {
                let mapping=try XCTUnwrap(region.brows.first(where:{ $0.side==curve.side })?.mapping)
                let peak=try XCTUnwrap(curve.keyPoints[1].position(in:f.vertices))
                XCTAssertLessThanOrEqual(peak.y,mapping.arch.y+0.00101)
                XCTAssertGreaterThanOrEqual(peak.y,mapping.arch.y-0.00151)
                if style == .softNatural { XCTAssertEqual(peak.y,mapping.arch.y,accuracy:0.00001) }
                for sample in curve.samples.compactMap({ $0?.position(in:f.vertices) }) {
                    XCTAssertLessThanOrEqual(sample.y,mapping.arch.y+0.00101)
                }
            }
        }
    }
    func testEyeDepthComesFromSurfaceMeshInsteadOfGlobeCenter() throws {
        let f=BrowFixture(),scan=try XCTUnwrap(f.detection().eyeScan)
        let eye=SIMD3<Float>(0.032,0.03,0.025)
        let contour=try XCTUnwrap(scan.eyes.first(where:{ ($0.pupil.x-0.5)>0 }))
        let depth=try XCTUnwrap(f.projection.eyeSurfaceDepth(contour:contour.contour,vertices:f.vertices,eye:eye,faceWidth:0.08))
        XCTAssertEqual(depth,0.04,accuracy:0.00001)
        XCTAssertGreaterThan(abs(depth-eye.z),0.01)
        XCTAssertNil(f.projection.eyeSurfaceDepth(contour:contour.contour,vertices:[],eye:eye,faceWidth:0.08))
    }
}

// -Nimah: A contour top is not the brow center; formula rays must not extend the fitted hair outline.
extension EyebrowTests {
    func testObservedFitCentersUpperAndLowerBrowInsteadOfUsingTopEdge() throws {
        var points:[SIMD3<Float>]=[]
        for i in 0...6 {
            let t=Float(i)/6,x=0.017+t*0.035,center=0.05+0.004*4*t*(1-t)
            points += [.init(x,center+0.002,0.04),.init(x,center-0.002,0.04)]
        }
        let fit=try XCTUnwrap(ObservedBrowFit(points:points,inner:points[0],outer:points[points.count-1]))
        XCTAssertEqual(fit.height(at:0),0.05,accuracy:0.00001)
        XCTAssertEqual(fit.height(at:0.5),0.054,accuracy:0.00001)
        XCTAssertEqual(fit.height(at:1),0.05,accuracy:0.00001)
    }
    func testLiveOutlineUsesObservedSpanEvenWhenFormulaTailExtendsFurther() throws {
        let f=BrowFixture(),region=try f.region()
        let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:.softNatural))
        for curve in guide.curves {
            let observed=try XCTUnwrap(region.brows.first(where:{ $0.side==curve.side }))
            let points=observed.landmarks.compactMap { $0.position(in:f.vertices) }
            let lo=points.map(\.x).min()!,hi=points.map(\.x).max()!
            XCTAssertEqual(curve.shapeKeyPoints.count,3)
            let first=try XCTUnwrap(curve.shapeKeyPoints.first?.position(in:f.vertices))
            let last=try XCTUnwrap(curve.shapeKeyPoints.last?.position(in:f.vertices))
            XCTAssertEqual(min(first.x,last.x),lo,accuracy:0.00001)
            XCTAssertEqual(max(first.x,last.x),hi,accuracy:0.00001)
            for sample in curve.samples.compactMap({ $0?.position(in:f.vertices) }) {
                XCTAssertGreaterThanOrEqual(sample.x,lo-0.00001)
                XCTAssertLessThanOrEqual(sample.x,hi+0.00001)
            }
        }
        XCTAssertFalse(EyebrowConfiguration().showMappingFormula)
    }
}
