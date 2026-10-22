// -Nimah: TrackingReadinessTests.swift — implementasi MVP SunriseApp.
import XCTest
import SceneKit
import UIKit
import Metal
import ARKit
@testable import SunriseApp

final class TrackingReadinessTests: XCTestCase {
    func testRequiresTwoSecondsOfContinuousTracking() {
        var readiness = TrackingReadiness()
        for i in 0..<20 { XCTAssertFalse(readiness.update(timestamp: Double(i) * 0.1, tracked: true, steady: true)) }
        XCTAssertTrue(readiness.update(timestamp: 2, tracked: true, steady: true))
    }
    func testTrackingLossMovementAndFrameGapsResetReadiness() {
        var readiness = TrackingReadiness()
        for i in 0...22 { _ = readiness.update(timestamp: Double(i) * 0.1, tracked: true, steady: true) }
        XCTAssertFalse(readiness.update(timestamp: 2.3, tracked: false, steady: true))
        XCTAssertFalse(readiness.update(timestamp: 2.4, tracked: true, steady: true))
        XCTAssertFalse(readiness.update(timestamp: 2.5, tracked: true, steady: false))
        XCTAssertFalse(readiness.update(timestamp: 9, tracked: true, steady: true))
    }
    func testBlushMaskAvoidsCenterAndBackOfFaceAndIsSymmetric() {
        XCTAssertEqual(BlushMask.weight(x: 0, y: -0.026, z: 0.04), 0)
        XCTAssertEqual(BlushMask.weight(x: 0.043, y: -0.026, z: -0.02), 0)
        let left = BlushMask.weight(x: -0.043, y: -0.026, z: 0.04)
        XCTAssertGreaterThan(left, 0)
        XCTAssertEqual(left, BlushMask.weight(x: 0.043, y: -0.026, z: 0.04))
    }
}

// -Nimah: Regresi pemetaan titik tanpa asumsi indeks face-mesh tertentu.
extension TrackingReadinessTests {
    func testPlacementMappingHandlesEmptyMeshAndNeverDuplicatesAnIndex() {
        XCTAssertTrue(PlacementDots.vertexIndices(vertices: [], step: .blush).isEmpty)
        let vertices: [SIMD3<Float>] = [.init(-0.043,-0.015,0.036),.init(0.043,-0.015,0.036)]
        let indices = PlacementDots.vertexIndices(vertices: vertices, step: .blush)
        XCTAssertEqual(indices.count, 2)
        XCTAssertEqual(Set(indices).count, indices.count)
        XCTAssertTrue(indices.allSatisfy { vertices.indices.contains($0) })
    }
    func testEveryTutorialStageProvidesDistinctPlacementTargets() {
        for step in TutorialStep.allCases {
            let targets = PlacementDots.targets(for: step)
            let mapped = PlacementDots.vertexIndices(vertices: targets, step: step)
            XCTAssertFalse(targets.isEmpty)
            XCTAssertEqual(mapped.count, targets.count)
            XCTAssertEqual(mapped, Array(targets.indices))
        }
        XCTAssertNotEqual(PlacementDots.targets(for: .blush), PlacementDots.targets(for: .contour))
    }
}

// -Nimah: Mesh sintetis hanya untuk regresi algoritme; bukan bukti akurasi wajah iPhone.
private struct SurfaceFixture {
    var vertices: [SIMD3<Float>] = []
    var triangles: [Int16] = []
    var uv: [SIMD2<Float>] = []
    let eyes: [SIMD3<Float>] = [.init(-0.032,0.03,0.04),.init(0.032,0.03,0.04)]
    init(holes: Bool = true) {
        let columns=40, rows=50
        for row in 0...rows { for column in 0...columns {
            let x = -Float(0.08)+Float(column)*0.16/Float(columns)
            let y = -Float(0.11)+Float(row)*0.20/Float(rows)
            vertices.append(.init(x,y,0.04)); uv.append(.init(Float(column)/Float(columns),Float(row)/Float(rows)))
        } }
        func inHole(_ point: SIMD3<Float>) -> Bool {
            guard holes else { return false }
            for center in eyes {
                let dx=(point.x-center.x)/0.015, dy=(point.y-center.y)/0.007
                if dx*dx+dy*dy < 1 { return true }
            }
            let dx=point.x/0.025, dy=(point.y+0.055)/0.008
            return dx*dx+dy*dy < 1
        }
        for row in 0..<rows { for column in 0..<columns {
            let a=row*(columns+1)+column,b=a+1,c=a+columns+1,d=c+1
            for ids in [[a,b,c],[b,d,c]] {
                let center=ids.reduce(SIMD3<Float>.zero) { $0+vertices[$1] }/3
                if !inHole(center) { triangles.append(contentsOf:ids.map(Int16.init)) }
            }
        } }
    }
    func profile(scale:Float=1) -> FaceSurfaceProfile? {
        FaceSurfaceProfile.make(vertices:vertices.map { $0*scale },triangles:triangles,eyeCenters:eyes.map { $0*scale })
    }
}
extension TrackingReadinessTests {
    func testPreviewModeSeparatesResultPointsAndOriginal() {
        XCTAssertTrue(MakeupPreviewMode.pointsAndLook.showsMakeup)
        XCTAssertTrue(MakeupPreviewMode.pointsAndLook.showsPoints)
        XCTAssertFalse(MakeupPreviewMode.lookOnly.showsPoints)
        XCTAssertFalse(MakeupPreviewMode.pointsOnly.showsMakeup)
        XCTAssertFalse(MakeupPreviewMode.original.showsMakeup)
        XCTAssertFalse(MakeupPreviewMode.original.showsPoints)
    }
    func testTopologyFitFindsHolesAndUsesOnlyRenderedVertices() throws {
        let fixture=SurfaceFixture(),profile=try XCTUnwrap(fixture.profile())
        XCTAssertTrue(profile.fittedEyes); XCTAssertTrue(profile.fittedLips)
        let valid=Set(fixture.triangles.map(Int.init))
        for step in TutorialStep.allCases {
            XCTAssertEqual(profile.weights[step]?.count,fixture.vertices.count)
            XCTAssertTrue(profile.weights[step]!.allSatisfy { $0.isFinite && $0>=0 && $0<=1 })
            if step == .eyeliner { XCTAssertTrue(profile.guides[step]!.isEmpty) }
            else { XCTAssertFalse(profile.guides[step]!.isEmpty) }
            XCTAssertTrue(profile.guides[step]!.allSatisfy { valid.contains($0) })
            XCTAssertEqual(Set(profile.guides[step]!).count,profile.guides[step]!.count)
        }
    }
    func testFitAdaptsToFaceScaleRatherThanFixedMeterCoordinates() throws {
        let fixture=SurfaceFixture(),small=try XCTUnwrap(fixture.profile()),large=try XCTUnwrap(fixture.profile(scale:1.2))
        for step in TutorialStep.allCases {
            for (a,b) in zip(small.weights[step]!,large.weights[step]!) { XCTAssertEqual(a,b,accuracy:0.0003,"Scale changed \(step.rawValue) mask") }
        }
    }
    func testMissingEyeAndMouthBoundariesDisableThoseEffects() throws {
        let profile=try XCTUnwrap(SurfaceFixture(holes:false).profile())
        XCTAssertFalse(profile.fittedEyes); XCTAssertFalse(profile.fittedLips)
        for step in [TutorialStep.eyeshadow,.eyeliner,.lips] {
            XCTAssertTrue(profile.weights[step]!.allSatisfy { $0==0 })
            XCTAssertTrue(profile.guides[step]!.isEmpty)
        }
        XCTAssertGreaterThan(profile.weights[.blush]!.max()!,0)
    }
    func testInvalidTopologyRejectsFitWithoutCrash() {
        let fixture=SurfaceFixture()
        XCTAssertNil(FaceSurfaceProfile.make(vertices:fixture.vertices,triangles:[-1,0,1],eyeCenters:fixture.eyes))
        XCTAssertNil(FaceSurfaceProfile.make(vertices:[],triangles:[],eyeCenters:fixture.eyes))
    }
    func testTextureBakerBuildsTransparentLayersAndRejectsBadUVs() throws {
        let fixture=SurfaceFixture(),profile=try XCTUnwrap(fixture.profile())
        let baked=try XCTUnwrap(MakeupTextureBaker.bake(surface:profile,uv:fixture.uv,triangles:fixture.triangles,referenceID:"sculpted-glam",size:64))
        XCTAssertEqual(baked.textures.count,5)
        XCTAssertEqual(baked.fullLook.width,64)
        let data=try XCTUnwrap(baked.fullLook.dataProvider?.data)
        let bytes=[UInt8](data as Data)
        let alphas=stride(from:3,to:bytes.count,by:4).map { bytes[$0] }
        XCTAssertTrue(alphas.contains(0)); XCTAssertTrue(alphas.contains { $0>0 })
        XCTAssertNil(MakeupTextureBaker.bake(surface:profile,uv:[],triangles:fixture.triangles,referenceID:"sculpted-glam",size:64))
    }
    @MainActor func testCalibrationRequiresFittingAndReportsDistanceWithoutRangeLock() {
        let camera=FaceCameraState()
        camera.report(tracked:true,ready:true)
        XCTAssertFalse(camera.calibrated)
        camera.fitReady=true; camera.report(tracked:true,ready:true)
        XCTAssertTrue(camera.calibrated)
        camera.distanceMeters=0.15
        XCTAssertNotNil(camera.distanceHint)
        XCTAssertTrue(camera.tracked)
        camera.suspend(); XCTAssertNil(camera.distanceHint); XCTAssertFalse(camera.calibrated)
    }
}

// -Nimah: Uji piksel hasil GPU, bukan hanya keberadaan alpha pada file tekstur.
extension TrackingReadinessTests {
    @MainActor func testMakeupTextureActuallyRendersOverDepthMesh() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let scene = SCNScene()
        scene.background.contents = UIColor.white
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera!.usesOrthographicProjection = true
        camera.camera!.orthographicScale = 1
        camera.position.z = 2
        scene.rootNode.addChildNode(camera)
        let depth = SCNPlane(width: 1, height: 1)
        let occluder = SCNMaterial(); occluder.colorBufferWriteMask = []
        occluder.writesToDepthBuffer = true
        depth.materials = [occluder]
        let depthNode = SCNNode(geometry: depth); depthNode.renderingOrder = -10
        scene.rootNode.addChildNode(depthNode)
        let weights: [Float] = [0, 0, 1, 1]
        let surface = FaceSurfaceProfile(weights: Dictionary(uniqueKeysWithValues: TutorialStep.allCases.map { ($0, weights) }),
            guides: [:], fittedEyes: true, fittedLips: true, vertexCount: 4)
        let baked = try XCTUnwrap(MakeupTextureBaker.bake(surface: surface,
            uv: [.init(0,0), .init(1,0), .init(0,1), .init(1,1)],
            triangles: [0,1,2,1,3,2], referenceID: "sculpted-glam", size: 64))
        let material = SCNMaterial()
        material.lightingModel = .constant; material.blendMode = .alpha
        material.writesToDepthBuffer = false; material.readsFromDepthBuffer = true
        material.diffuse.contents = baked.textures[.lips]
        material.transparency = 0.8
        let plane = SCNPlane(width: 1, height: 1); plane.materials = [material]
        let node = SCNNode(geometry: plane); node.position.z = 0.00015
        scene.rootNode.addChildNode(node)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let output = renderer.snapshot(atTime: 0, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        let cg = try XCTUnwrap(output.cgImage)
        func sample(_ image: CGImage, y: CGFloat) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: -32, y: -y, width: 64, height: 64))
            }
            return bytes
        }
        let upper = try sample(cg, y: 40), lower = try sample(cg, y: 24)
        XCTAssertGreaterThan(Int(upper[0]) - Int(upper[1]), 10, "Upper mesh must visibly show lip pigment: \(upper)")
        XCTAssertGreaterThan(Int(lower[1]) - Int(upper[1]), 15, "Pigment must follow vertex weights, not vertically reversed UV: \(upper), \(lower)")
        material.transparency = 0
        let original = try XCTUnwrap(renderer.snapshot(atTime: 1, with: CGSize(width: 64, height: 64), antialiasingMode: .none).cgImage)
        let clear = try sample(original, y: 40)
        XCTAssertGreaterThan(Int(clear[1]) - Int(upper[1]), 25, "Zero intensity must restore background: \(clear)")
        XCTAssertLessThan(abs(Int(clear[0]) - Int(clear[1])), 3)

    }
}

// -Nimah: Regresi anatomi, deformasi dan scope tutorial; fixture bukan bukti ketelitian kamera fisik.
extension TrackingReadinessTests {
    func testTutorialScopeNeverSilentlyAddsOtherLayers() {
        XCTAssertEqual(MakeupLayerSelection.layers(step:.eyeliner,fullLook:false,previous:false),[.eyeliner])
        XCTAssertEqual(MakeupLayerSelection.layers(step:.eyeliner,fullLook:false,previous:true),[.blush,.contour,.eyeshadow,.eyeliner])
        XCTAssertEqual(MakeupLayerSelection.layers(step:.eyeliner,fullLook:true,previous:false),TutorialStep.allCases)
    }
    @MainActor func testNewCameraStartsInSingleLayerTutorial() {
        let camera=FaceCameraState()
        XCTAssertFalse(camera.previewFullLook); XCTAssertFalse(camera.showPreviousSteps)
    }
    func testAttachmentFollowsTriangleDeformationAndRejectsHole() throws {
        let v:[SIMD3<Float>]=[.init(0,0,0.04),.init(1,0,0.04),.init(0,1,0.04)]
        let attachment=try XCTUnwrap(SurfaceAttachment.bind(.init(0.25,0.25),vertices:v,triangles:[0,1,2],minimumZ:0))
        let p=try XCTUnwrap(attachment.position(in:v)); XCTAssertEqual(p.x,0.25,accuracy:0.000001)
        let changed=[v[0],v[1]+SIMD3(0,0,0.04),v[2]]
        let q=try XCTUnwrap(attachment.position(in:changed)); XCTAssertEqual(q.z,0.05,accuracy:0.000001)
        XCTAssertNil(SurfaceAttachment.bind(.init(0.8,0.8),vertices:v,triangles:[0,1,2],minimumZ:0))
        XCTAssertNil(attachment.position(in:[]))
        XCTAssertNil(SurfaceAttachment.bind(.zero,vertices:v,triangles:[-1,0,1],minimumZ:0))
    }
    func testEyelinerAttachmentsStayAboveEyesAndAwayFromNoseAndLowerCheeks() throws {
        let fixture=SurfaceFixture(),profile=try XCTUnwrap(fixture.profile())
        let region=EyelinerRegion.make(vertices:fixture.vertices,triangles:fixture.triangles,rims:profile.eyeRims,style:EyelinerStyle())
        XCTAssertEqual(region.eyes.count,2,region.reason)
        for eye in region.eyes {
            XCTAssertGreaterThan(eye.triangles.count,36)
            for attachment in eye.attachments {
                let p=try XCTUnwrap(attachment.position(in:fixture.vertices))
                XCTAssertGreaterThan(p.y,0.025,"Eyeliner must stay near the upper eye rim")
                XCTAssertGreaterThan(abs(p.x),0.012,"Eyeliner must not reach the nose")
                XCTAssertLessThan(abs(p.x),0.065)
            }
            for guide in eye.guides {
                XCTAssertTrue(eye.attachments.contains { $0.indices==guide.indices && $0.weights==guide.weights })
            }
        }
    }
    func testEyelinerNeedsVerifiedRimsAndClampsStyle() throws {
        let fixture=SurfaceFixture(),profile=try XCTUnwrap(fixture.profile())
        XCTAssertTrue(EyelinerRegion.make(vertices:fixture.vertices,triangles:fixture.triangles,rims:[],style:EyelinerStyle()).eyes.isEmpty)
        let style=EyelinerStyle(wingLength:5,wingAngle:100,thickness:1).clamped
        XCTAssertEqual(style.wingLength,0.3); XCTAssertEqual(style.wingAngle,35); XCTAssertEqual(style.thickness,0.065)
        let base=EyelinerRegion.make(vertices:fixture.vertices,triangles:fixture.triangles,rims:profile.eyeRims,style:EyelinerStyle(wingLength:0))
        let wing=EyelinerRegion.make(vertices:fixture.vertices,triangles:fixture.triangles,rims:profile.eyeRims,style:EyelinerStyle(wingLength:0.25))
        XCTAssertEqual(base.eyes.count,2); XCTAssertEqual(wing.eyes.count,2)
        let baseX=base.eyes.flatMap(\.attachments).compactMap { $0.position(in:fixture.vertices) }.map { abs($0.x) }.max()!
        let wingX=wing.eyes.flatMap(\.attachments).compactMap { $0.position(in:fixture.vertices) }.map { abs($0.x) }.max()!
        XCTAssertGreaterThan(wingX,baseX)
    }
    func testRendererUVReaderRespectsStrideAndOffset() throws {
        let values:[Float]=[99,0.1,0.2,88,99,0.7,0.8,88]
        let source=SCNGeometrySource(data:values.withUnsafeBytes { Data($0) },semantic:.texcoord,vectorCount:2,
            usesFloatComponents:true,componentsPerVector:2,bytesPerComponent:4,dataOffset:4,dataStride:16)
        let geometry=SCNGeometry(sources:[source],elements:[])
        let uv=try XCTUnwrap(LiveGuideDiagnostics.textureCoordinates(of:geometry))
        XCTAssertEqual(uv,[SIMD2<Float>(0.1,0.2),SIMD2<Float>(0.7,0.8)])
    }
    @MainActor func testActualEyelinerRendererTintsEyeAndLeavesNoseAndCheeksClear() throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let fixture=SurfaceFixture(),profile=try XCTUnwrap(fixture.profile())
        let region=EyelinerRegion.make(vertices:fixture.vertices,triangles:fixture.triangles,rims:profile.eyeRims,style:EyelinerStyle())
        XCTAssertEqual(region.eyes.count,2)
        let scene=SCNScene(); scene.background.contents=UIColor.white
        let camera=SCNNode(); camera.camera=SCNCamera(); camera.camera!.usesOrthographicProjection=true
        camera.camera!.orthographicScale=0.12; camera.camera!.zNear=0.001; camera.camera!.zFar=10; camera.position.z=0.4; scene.rootNode.addChildNode(camera)
        let surface=SCNGeometry(sources:[SCNGeometrySource(vertices:fixture.vertices.map { SCNVector3($0.x,$0.y,$0.z) })],
            elements:[SCNGeometryElement(indices:fixture.triangles,primitiveType:.triangles)])
        let occluder=SCNMaterial(); occluder.colorBufferWriteMask=[]; occluder.writesToDepthBuffer=true; occluder.isDoubleSided=true
        surface.materials=[occluder]
        let depth=SCNNode(geometry:surface); depth.renderingOrder = -10; scene.rootNode.addChildNode(depth)
        for eye in region.eyes {
            let geometry=try XCTUnwrap(EyelinerRenderer.geometry(eye:eye,vertices:fixture.vertices,material:EyelinerRenderer.material()))
            scene.rootNode.addChildNode(SCNNode(geometry:geometry))
        }
        let renderer=SCNRenderer(device:device,options:nil); renderer.scene=scene; renderer.pointOfView=camera
        let image=try XCTUnwrap(renderer.snapshot(atTime:0,with:CGSize(width:512,height:512),antialiasingMode:.multisampling4X).cgImage)
        func green(at point: SIMD3<Float>) throws -> Int {
            let x=CGFloat((point.x/0.24+0.5)*512),y=CGFloat((point.y/0.24+0.5)*512)
            var bytes=[UInt8](repeating:0,count:4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image,in:CGRect(x:-x,y:-y,width:512,height:512))
            }
            return Int(bytes[1])
        }
        for eye in region.eyes {
            let middle=eye.attachments.count/8*4
            let a=try XCTUnwrap(eye.attachments[middle+1].position(in:fixture.vertices))
            let b=try XCTUnwrap(eye.attachments[middle+2].position(in:fixture.vertices))
            XCTAssertLessThan(try green(at:(a+b)/2),220,"Eyeliner must render at its own attachment")
        }
        for point: SIMD3<Float> in [.init(0,0,0.04),.init(-0.05,-0.07,0.04),.init(0.05,-0.07,0.04)] {
            XCTAssertGreaterThan(try green(at:point),250,"Eyeliner must not paint nose or lower cheeks")
        }
    }
}

// -Nimah: Uji mesh netral ARKit di hardware, tanpa menjalankan kamera atau mengambil wajah pengguna.
extension TrackingReadinessTests {
    @MainActor func testNativeFaceMeshSupportsSurfaceEyelinerAndRendererUV() throws {
        guard ARFaceTrackingConfiguration.isSupported else { throw XCTSkip("Native AR face geometry requires supported hardware") }
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let neutral=try XCTUnwrap(ARFaceGeometry(blendShapes:[:]))
        let native=try XCTUnwrap(ARSCNFaceGeometry(device:device,fillMesh:false))
        native.update(from:neutral)
        let vertices=Array(neutral.vertices),triangles=Array(neutral.triangleIndices)
        let uv=try XCTUnwrap(LiveGuideDiagnostics.textureCoordinates(of:native))
        XCTAssertEqual(uv.count,vertices.count)
        // -Nimah: Diagnostik mesh netral buatan ARKit, bukan telemetry wajah pengguna.
        let raw=Array(neutral.textureCoordinates)
        let same=zip(uv,raw).filter { simd_length($0.0-$0.1)<0.00001 }.count
        let flipped=zip(uv,raw).filter { simd_length($0.0-SIMD2($0.1.x,1-$0.1.y))<0.00001 }.count
        print("Neutral UV convention: identity=\(same), flippedV=\(flipped), total=\(uv.count)")
        XCTAssertTrue(uv.allSatisfy { $0.x>=0 && $0.x<=1 && $0.y>=0 && $0.y<=1 })
        let profile=try XCTUnwrap(FaceSurfaceProfile.make(vertices:vertices,triangles:triangles,
            eyeCenters:[.init(-0.032,0.03,0.03),.init(0.032,0.03,0.03)]))
        XCTAssertTrue(profile.fittedEyes,"Neutral topology must expose both eye holes")
        let region=EyelinerRegion.make(vertices:vertices,triangles:triangles,rims:profile.eyeRims,style:EyelinerStyle())
        XCTAssertEqual(region.eyes.count,2,region.reason)
        for eye in region.eyes {
            XCTAssertNotNil(EyelinerRenderer.geometry(eye:eye,vertices:vertices,material:EyelinerRenderer.material()))
            XCTAssertTrue(eye.attachments.allSatisfy { $0.position(in:vertices) != nil })
        }
    }
}

// -Nimah: Regresi screenshot eyeshadow di pipi: jalur warna produksi wajib bebas UV dan mengikuti vertex panduan.
extension TrackingReadinessTests {
    func testEyeshadowVertexColorsStayAboveEyesAndExcludeEyeliner() throws {
        let fixture=SurfaceFixture(),surface=try XCTUnwrap(fixture.profile())
        let colors=SurfaceMakeupRenderer.colors(surface:surface,steps:[.eyeshadow],referenceID:"sculpted-glam")
        XCTAssertEqual(colors.count,fixture.vertices.count)
        for i in fixture.vertices.indices {
            if fixture.vertices[i].y<0.025 || abs(fixture.vertices[i].x)<0.006 { XCTAssertEqual(colors[i].w,0) }
        }
        for index in surface.guides[.eyeshadow] ?? [] { XCTAssertGreaterThan(colors[index].w,0) }
        let liner=SurfaceMakeupRenderer.colors(surface:surface,steps:[.eyeliner],referenceID:"sculpted-glam")
        XCTAssertTrue(liner.allSatisfy { $0.w==0 },"Eyeliner must use the separate attachment renderer")
    }
    @MainActor func testEyeshadowProductionRendererOnSyntheticMesh() throws {
        let fixture=SurfaceFixture(),surface=try XCTUnwrap(fixture.profile())
        try assertShadowRender(vertices:fixture.vertices,triangles:fixture.triangles,surface:surface)
    }
    @MainActor func testEyeshadowProductionRendererOnNativeMesh() throws {
        guard ARFaceTrackingConfiguration.isSupported else { throw XCTSkip("Native mesh requires supported hardware") }
        let neutral=try XCTUnwrap(ARFaceGeometry(blendShapes:[:]))
        let vertices=Array(neutral.vertices),triangles=Array(neutral.triangleIndices)
        let surface=try XCTUnwrap(FaceSurfaceProfile.make(vertices:vertices,triangles:triangles,
            eyeCenters:[.init(-0.032,0.03,0.03),.init(0.032,0.03,0.03)]))
        try assertShadowRender(vertices:vertices,triangles:triangles,surface:surface)
    }
    @MainActor private func assertShadowRender(vertices:[SIMD3<Float>],triangles:[Int16],surface:FaceSurfaceProfile) throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let colors=SurfaceMakeupRenderer.colors(surface:surface,steps:[.eyeshadow],referenceID:"sculpted-glam")
        let material=EyelinerRenderer.material(tint:.white)
        let geometry=try XCTUnwrap(SurfaceMakeupRenderer.geometry(vertices:vertices,triangles:triangles,
            colorSource:SurfaceMakeupRenderer.colorSource(colors),material:material))
        XCTAssertTrue(geometry.sources(for:.texcoord).isEmpty,"Production color geometry must not depend on atlas orientation")
        let scene=SCNScene(); scene.background.contents=UIColor.white
        let node=SCNNode(geometry:geometry); node.position.z=0.0006; scene.rootNode.addChildNode(node)
        let depthGeometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices.map { SCNVector3($0.x,$0.y,$0.z) })],elements:[SCNGeometryElement(indices:triangles,primitiveType:.triangles)])
        let depthMaterial=SCNMaterial(); depthMaterial.colorBufferWriteMask=[]; depthMaterial.writesToDepthBuffer=true; depthMaterial.isDoubleSided=true
        depthGeometry.materials=[depthMaterial]
        let depth=SCNNode(geometry:depthGeometry); depth.renderingOrder = -10; scene.rootNode.addChildNode(depth)
        let camera=SCNNode(); camera.camera=SCNCamera(); camera.camera!.zNear=0.001; camera.camera!.zFar=10
        camera.camera!.usesOrthographicProjection=true; camera.camera!.orthographicScale=0.12; camera.position.z=0.4
        scene.rootNode.addChildNode(camera)
        let renderer=SCNRenderer(device:device,options:nil); renderer.scene=scene; renderer.pointOfView=camera
        func image() throws -> CGImage { try XCTUnwrap(renderer.snapshot(atTime:0,with:CGSize(width:512,height:512),antialiasingMode:.multisampling4X).cgImage) }
        func green(_ image: CGImage,_ p: SIMD3<Float>) throws -> Int {
            var bytes=[UInt8](repeating:0,count:4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image,in:CGRect(x:-CGFloat((p.x/0.24+0.5)*512),y:-CGFloat((p.y/0.24+0.5)*512),width:512,height:512))
            }
            return Int(bytes[1])
        }
        let output=try image()
        // -Nimah: Uji centroid triangle paling berpigmen di setiap mata, bukan warna file atlas.
        var eyeSamples:[SIMD3<Float>]=[]
        for sign:Float in [-1,1] {
            var best:Float=0,point=SIMD3<Float>.zero
            for t in stride(from:0,to:triangles.count,by:3) {
                let ids=[Int(triangles[t]),Int(triangles[t+1]),Int(triangles[t+2])]
                let center=ids.reduce(SIMD3<Float>.zero) { $0+vertices[$1] }/3
                let alpha=ids.reduce(Float(0)) { $0+colors[$1].w }/3
                if center.x*sign>0,alpha>best { best=alpha; point=center }
            }
            XCTAssertGreaterThan(best,0.1); eyeSamples.append(point)
            XCTAssertLessThan(try green(output,point),235,"Shadow must render over its own eye-region triangle")
        }
        for p:SIMD3<Float> in [.init(0,0,0.04),.init(-0.05,-0.06,0.04),.init(0.05,-0.06,0.04)] {
            XCTAssertGreaterThan(try green(output,p),250,"No eyeshadow on nose or lower cheeks")
        }
        material.transparency=0
        let original=try image()
        for p in eyeSamples { XCTAssertGreaterThan(try green(original,p),250) }
    }
}
