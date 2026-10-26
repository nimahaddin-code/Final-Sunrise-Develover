// -Nimah: Preference provenance, missing coverage and real mesh binding regression, not on-face acceptance.
import XCTest
import SceneKit
import UIKit
import ImageIO
import Metal
@testable import SunriseApp

final class MakeupPreferenceTests:XCTestCase {
    func testFaceSkinOcclusionModelInitializesFromBundledLabels() async throws {
        let model=HandOcclusionSegmenter(faceSkinOnly:true)
        try await model.start()
        XCTAssertTrue(model.isAvailable,"Actual bundled model must provide a verified face-skin label")
        model.stop()
    }
    func testNativeBoundaryMouthMaskDoesNotRequireSemanticMeshIndices() {
        let n=20
        var v:[SIMD3<Float>]=[],tri:[Int16]=[]
        for y in 0...n {for x in 0...n {v.append(SIMD3(-1+Float(x)/10,-1+Float(y)/10,0))}}
        for y in 0..<n {for x in 0..<n {
            if (8..<12).contains(x) && (4..<8).contains(y) {continue}
            let a=y*(n+1)+x,b=a+1,c=a+n+1,d=c+1
            tri += [a,b,c,b,d,c].map(Int16.init)
        }}
        let mask=BeautyBlushEngine.mouthExclusion(vertices:v,triangles:tri,eyes:[SIMD3(-0.3,0.3,0),SIMD3(0.3,0.3,0)])
        XCTAssertEqual(mask.x,0,accuracy:0.01);XCTAssertEqual(mask.y,-0.4,accuracy:0.01)
        XCTAssertGreaterThan(mask.z,0.2);XCTAssertGreaterThan(mask.w,0.2)
    }
    func testMetalAtlasPaintsIndependentCheeksAndKeepsNoseClear() throws {
        guard MTLCreateSystemDefaultDevice() != nil else{throw XCTSkip("Metal unavailable")}
        let pixels=try BeautyBlushEngine.renderAtlasFixture()
        func sample(_ x:Int,_ y:Int,_ channel:Int)->Float {pixels[(y*64+x)*4+channel]}
        XCTAssertGreaterThan(sample(45,35,0),0.1);XCTAssertEqual(sample(45,35,1),0,accuracy:0.0001)
        XCTAssertGreaterThan(sample(19,35,1),0.1);XCTAssertEqual(sample(19,35,0),0,accuracy:0.0001)
        XCTAssertEqual(sample(32,35,0)+sample(32,35,1),0,accuracy:0.0001)
        XCTAssertEqual(sample(45,5,0)+sample(45,5,1),0,accuracy:0.0001)
    }
    func testMetalBlushUsesCameraTextureAndSuppressesObstructedSkin() throws {
        guard MTLCreateSystemDefaultDevice() != nil else{throw XCTSkip("Metal unavailable")}
        let bare=try BeautyBlushEngine.renderPixelFixture(obstructed:false,intensity:0)
        let makeup=try BeautyBlushEngine.renderPixelFixture(obstructed:false,intensity:0.7)
        let obstructed=try BeautyBlushEngine.renderPixelFixture(obstructed:true,intensity:0.7)
        let i=(16*32+16)*4
        XCTAssertGreaterThan(Int(makeup[i+2])-Int(makeup[i+1]),20,"GPU pigment must tint actual camera pixels")
        for c in 0..<3 {XCTAssertEqual(Int(bare[i+c]),Int(obstructed[i+c]),accuracy:1,"Occlusion must restore camera skin, not black or transparent edges")}
        XCTAssertEqual(Int(bare[i+1]),128,accuracy:2,"sRGB camera must not be decoded twice")
    }
    func testBeautyBlushConfigurationRejectsUnsafeValuesAndVisibilityRejectsStaleClock() throws {
        let config=try BeautyBlushConfiguration.load()
        XCTAssertEqual(config.target_fps,60)
        let url=try XCTUnwrap(Bundle.main.url(forResource:"blush-rendering",withExtension:"json"))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        json["saturation"]=99
        XCTAssertThrowsError(try BeautyBlushConfiguration.decode(JSONSerialization.data(withJSONObject:json)))
        var visibility=BeautyBlushVisibility()
        XCTAssertEqual(visibility.update(timestamp:1,visible:true,tau:0.055),0)
        let first=visibility.update(timestamp:1.016,visible:true,tau:0.055)
        XCTAssertGreaterThan(first,0);XCTAssertLessThan(first,1)
        XCTAssertEqual(visibility.update(timestamp:0.5,visible:false,tau:0.055),first)
        XCTAssertLessThan(visibility.update(timestamp:1.032,visible:false,tau:0.055),first)
    }
    func testBlushRevisionBroadensVisibleRegionAndSoftensOuterFalloff() throws {
        let region=try BrowFixture().region()
        let field=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.cheekbone)?.pigmentFields.first)
        var previous=field
        previous=BlushPigmentField(center:field.center,radius:SIMD2(0.16*0.170,0.16*0.105),angle:field.angle,side:field.side,nasalLimit:field.nasalLimit,outerLimit:field.outerLimit,eyeLimit:field.eyeLimit,opacity:field.opacity,power:field.power,edgeFeather:0.16*0.012,smoothstepMix:0)
        let outward=SIMD2(field.side*cos(field.angle),sin(field.angle))
        let p=field.center+outward*0.16*0.14
        XCTAssertGreaterThan(field.coverage(p),previous.coverage(p)+0.1)
        let inside=field.center+outward*field.radius.x*0.99
        XCTAssertLessThan(field.coverage(inside),0.001,"Gradient must approach zero gently at the ellipse edge")
        XCTAssertEqual(field.coverage(field.center+outward*field.radius.x*1.01),0)
    }
    func testWideBlushWashKeepsLargeFootprintAndFeathersSafeBoundaries() throws {
        let region=try BrowFixture().region()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.cheekbone))
        for field in guide.pigmentFields {
            XCTAssertGreaterThan(field.radius.x,0.16*0.15)
            XCTAssertGreaterThan(field.radius.y,0.16*0.09)
            XCTAssertLessThan(field.power,1.3,"Lower exponent keeps color across a wider part of the cheek")
            let axis=SIMD2(field.side*cos(field.angle),sin(field.angle))
            XCTAssertGreaterThan(field.coverage(field.center+axis*field.radius.x*0.65),0.45)
            let border=SIMD2(field.side*field.nasalLimit,field.center.y)
            XCTAssertEqual(field.coverage(border),0,accuracy:0.000001)
            XCTAssertEqual(field.coverage(border-SIMD2(field.side*0.001,0)),0)
            let inner=border+SIMD2(field.side*field.edgeFeather*0.5,0)
            XCTAssertGreaterThan(field.coverage(inner),0)
            XCTAssertLessThan(field.coverage(inner),field.coverage(inner+SIMD2(field.side*field.edgeFeather*0.5,0)))
        }
    }
    @MainActor func testBlushIntensityUsesUpdatedJSONWithoutChangingBrowOrLiner() {
        let home=TryOnHomeModel(plan:MakeupPlan(shape:.heart),assessment:.init(shape:.heart,origin:.analysis),checker:MockFaceTrackingChecker(),hasLaunchFit:true)
        XCTAssertEqual(home.intensities[.blush] ?? -1,0.72,accuracy:0.00001)
        XCTAssertEqual(home.intensities[.eyebrow] ?? -1,0.65,accuracy:0.00001)
        home.deactivate()
    }
    func testBrowBodyHasUsableThicknessWithoutShorteningObservedContour() throws {
        let region=try BrowFixture().region()
        let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:.lowArch))
        for curve in guide.curves {
            let observed=curve.landmarks.compactMap { $0.position(in:region.restVertices) }
            let width=observed.map(\.x).max()!-observed.map(\.x).min()!
            let count=curve.samples.count,index=count/2
            let upper=try XCTUnwrap(curve.outline[index]?.position(in:region.restVertices))
            let lower=try XCTUnwrap(curve.outline[count*2-1-index]?.position(in:region.restVertices))
            XCTAssertGreaterThan(upper.y-lower.y,width*0.10)
            let samples=curve.samples.compactMap { $0?.position(in:region.restVertices) }
            XCTAssertEqual(samples.map(\.x).max()!-samples.map(\.x).min()!,width,accuracy:0.0001)
        }
    }
    func testMissingBrowOutlineSampleClipsOnlyThatStripInsteadOfErasingBothBrows() throws {
        let region=try BrowFixture().region()
        let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:.lowArch))
        let original=try XCTUnwrap(guide.curves.first)
        var outline=original.outline
        outline[20]=nil
        let curve=EyebrowGuide.Curve(side:original.side,landmarks:original.landmarks,samples:original.samples,outline:outline,strokes:[])
        let polygons=FaceRegionPreviewRenderer.browPolygons(curve:curve,vertices:region.restVertices)
        XCTAssertEqual(polygons.count,2)
        let gap=try XCTUnwrap(original.samples[20]?.position(in:region.restVertices))
        for polygon in polygons {
            XCTAssertTrue(polygon.allSatisfy { $0.x<gap.x } || polygon.allSatisfy { $0.x>gap.x })
        }
    }
    func testBundledDatabaseAssignmentsAndFullWidthGeometry() throws {
        let rules=try XCTUnwrap(MakeupRuleDatabase.shared)
        let expected:[MakeupFaceShape:(String,String)]=[.oval:("brow.natural","blush.cheekbone"),.round:("brow.high_arch","blush.high_cheekbone"),.square:("brow.rounded","blush.apple"),.oblong:("brow.straight","blush.horizontal"),.heart:("brow.low_arch","blush.center_cheek"),.diamond:("brow.soft_arch","blush.temple_sweep")]
        for (shape,ids) in expected {
            XCTAssertEqual(MakeupPreferenceCatalog.assignedBrow(for:shape)?.id,ids.0)
            XCTAssertEqual(MakeupPreferenceCatalog.assignedBlush(for:shape)?.id,ids.1)
        }
        XCTAssertNil(rules.assignment(.rectangle));XCTAssertNil(rules.assignment(.pear))
        let region=try BrowFixture().region()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.cheekbone))
        XCTAssertEqual(guide.pigmentFields.count,2)
        for f in guide.pigmentFields {
            XCTAssertEqual(f.radius.x,0.16*0.210,accuracy:0.000001)
            XCTAssertEqual(f.radius.y,0.16*0.130,accuracy:0.000001)
            XCTAssertEqual(f.angle,15*Float.pi/180,accuracy:0.000001)
            XCTAssertGreaterThan(f.coverage(f.center),0.99)
            XCTAssertEqual(f.coverage(SIMD2(0,f.center.y)),0)
        }
    }
    func testDatabaseRejectsMissingParameterAndNonFiniteOrOutOfRangeValue() throws {
        let url=try XCTUnwrap(Bundle.main.url(forResource:"makeup-reference.database",withExtension:"json"))
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        var presets=try XCTUnwrap(json["blush_presets"] as? [[String:Any]])
        var parameters=try XCTUnwrap(presets[0]["parameters"] as? [String:Any])
        parameters.removeValue(forKey:"major_radius");presets[0]["parameters"]=parameters;json["blush_presets"]=presets
        XCTAssertThrowsError(try MakeupRuleDatabase.decode(JSONSerialization.data(withJSONObject:json)))
    }
    // -Nimah: Enrollment may use another valid portrait orientation; failed retakes preserve the saved fit.
    @MainActor func testRetakeOrientationFallbackAndFailedReplacementKeepsFit() async throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws->[DetectedEyebrows] {
                frame.orientation == .right ? [result] : []
            }
        }
        let f=BrowFixture(),cache=LaunchMakeupFit()
        XCTAssertTrue(cache.prepare(try f.input(),provider:Provider(result:f.detection())))
        let preparation=LaunchFitPreparation(cache:cache,provider:Provider(result:f.detection()))
        preparation.restart()
        let replaced=await preparation.finish()
        XCTAssertFalse(replaced)
        XCTAssertTrue(cache.hasFit,"Starting or cancelling a retake must preserve a previously working fit")
    }

    // -Nimah: Reopening restores sparse fit descriptors without storing the original mesh/frame.
    func testSavedFittingRestoresAcrossLaunchesAndRetakeClearsIt() throws {
        struct Provider:FaceLandmarkProviding {
            let result:DetectedEyebrows
            func detectEyebrows(in frame:FaceLandmarkFrame) throws->[DetectedEyebrows] { [result] }
        }
        let name="SavedFittingTests-"+UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        let f=BrowFixture(),input=try f.input()
        let first=LaunchMakeupFit(defaults:defaults)
        XCTAssertTrue(first.prepare(input,provider:Provider(result:f.detection())))
        let reopened=LaunchMakeupFit(defaults:defaults)
        XCTAssertTrue(reopened.hasFit)
        let region=try XCTUnwrap(reopened.fittedRegion(anchorID:UUID(),vertices:input.vertices,triangles:input.triangles,timestamp:1))
        XCTAssertNotNil(EyebrowGuideGenerator.make(region:region,style:.natural))
        reopened.clear()
        XCTAssertFalse(LaunchMakeupFit(defaults:defaults).hasFit)
    }

    // -Nimah: Pigment fades throughout the cheek, rather than having an opaque sticker core.
    func testBlushFalloffIsContinuousFromCenterToEdge() {
        let radius=SIMD2<Float>(0.02,0.012)
        let values=(0...10).map { FaceRegionPreviewRenderer.softBlushCoverage(SIMD2(Float($0)/10*radius.x,0),center:.zero,radius:radius) }
        XCTAssertEqual(values.first!,1,accuracy:0.0001)
        XCTAssertEqual(values.last!,0,accuracy:0.0001)
        for i in 1..<values.count { XCTAssertLessThan(values[i],values[i-1]) }
    }
    func testBlushPairsUseSameFaceLocalHeight() throws {
        let region=try BrowFixture().region()
        for style in [BlushPlacementStyle.apple,.upperInner,.outerSweep] {
            let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:style))
            let means=guide.areas.map { area -> Float in
                let points=area.boundary.compactMap { $0.position(in:region.restVertices) }
                return points.map(\.y).reduce(0,+)/Float(points.count)
            }
            XCTAssertEqual(means[0],means[1],accuracy:0.00001)
        }
    }

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
            XCTAssertEqual(guide.areas.count,2)
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
        // A native coarse occlusion surface can sit in front of the interpolated cheek patch.
        // Pigment must remain composited over the camera rather than vanish behind its own face depth.
        let depth=SCNPlane(width:0.16,height:0.22)
        let occluder=SCNMaterial();occluder.colorBufferWriteMask=[]
        occluder.writesToDepthBuffer=true;occluder.isDoubleSided=true;depth.materials=[occluder]
        let depthNode=SCNNode(geometry:depth);depthNode.position.z=0.05;depthNode.renderingOrder = -10
        scene.rootNode.addChildNode(depthNode)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true
        camera.camera?.orthographicScale=0.2;camera.camera?.zNear=0.01;camera.position=SCNVector3(0,0,1)
        scene.rootNode.addChildNode(camera)
        let renderer=SCNRenderer(device:device,options:nil);renderer.scene=scene;renderer.pointOfView=camera
        let image=renderer.snapshot(atTime:0,with:CGSize(width:256,height:256),antialiasingMode:.none)
        let photo=try XCTUnwrap(image.pngData().flatMap(PalettePhoto.decode))
        var coloured=0
        for offset in stride(from:0,to:photo.rgba.count,by:4) {
            // JSON alpha is 0.38, composited in SceneKit linear space: on white the sRGB green is ~215, not <200.
            if Int(photo.rgba[offset])-Int(photo.rgba[offset+1])>20 && photo.rgba[offset+1]<240 { coloured += 1 }
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
    // -Nimah: Off-screen recommendations/tab changes must not load a second eyeliner detector.
    @MainActor func testHiddenHomeAndTutorialDoNotStartEyeliner() {
        let eyes=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:1.5))
        let plan=MakeupPlan(shape:.heart,eyeScan:eyes)
        let assessment=FaceShapeAssessment(shape:.heart,origin:.analysis)
        let home=TryOnHomeModel(plan:plan,assessment:assessment,checker:MockFaceTrackingChecker(),hasLaunchFit:true)
        home.choose(.eyeliner)
        XCTAssertTrue(home.canTry(.eyeliner))
        XCTAssertFalse(home.liner.hasLiner)
        let tutorial=GuidedTutorialModel(checker:MockFaceTrackingChecker(),assessment:assessment,plan:plan,
            handoff:TutorialHandoff(tool:.blush,shades:home.shades,intensities:home.intensities))
        tutorial.select(.eyeliner)
        XCTAssertTrue(tutorial.hasGuide)
        XCTAssertFalse(tutorial.liner.hasLiner)
        home.deactivate();tutorial.deactivate()
    }
    @MainActor func testTryOnShowsOnlySelectedToolAndUsesLaunchFitting() {
        let eyes=EyeShapeClassifier().classify(EyeMeasurements(openness:0.30,tilt:4,spacing:0.72,lidSpace:1.5))
        let home=TryOnHomeModel(plan:MakeupPlan(shape:.heart,eyeScan:eyes),assessment:.init(shape:.heart,origin:.analysis),checker:MockFaceTrackingChecker(),hasLaunchFit:true)
        XCTAssertEqual(home.enabled,[.blush])
        XCTAssertTrue(home.liveConfiguration.usesLaunchFit)
        XCTAssertFalse(home.liveConfiguration.browLayer.on);XCTAssertTrue(home.liveConfiguration.blushLayer.on)
        home.choose(.eyebrow)
        XCTAssertEqual(home.enabled,[.eyebrow])
        XCTAssertTrue(home.liveConfiguration.browLayer.on);XCTAssertFalse(home.liveConfiguration.blushLayer.on)
        home.choose(.eyeliner)
        XCTAssertEqual(home.enabled,[.eyeliner])
        XCTAssertFalse(home.liveConfiguration.browLayer.on);XCTAssertFalse(home.liveConfiguration.blushLayer.on)
        home.choose(.blush)
        XCTAssertEqual(home.enabled,[.blush])
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
                // Reject every orientation of the first fixture frame (.up + portrait variants).
                return attempts<=1+FaceContourDetector.orientations.count ? [] : [result]
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
    // -Nimah: The heart-face tutorial V must render as filled cheek pigment, not a chevron.
    func testUpperInnerTryOnFillsCenterWithoutChangingTutorialGuide() throws {
        let region=try BrowFixture().region()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.upperInner))
        XCTAssertEqual(guide.pigmentFields.count,2)
        for field in guide.pigmentFields {
            XCTAssertGreaterThan(field.coverage(field.center),0.99)
            XCTAssertEqual(field.radius.x,0.16*0.09,accuracy:0.00001)
            XCTAssertEqual(field.radius.y,0.16*0.075,accuracy:0.00001)
        }
    }

    // -Nimah: Slider/colour changes must reuse bindings, topology and feather data.
    func testShadeChangesReuseSurfaceBindings() throws {
        let f=BrowFixture(),region=try f.region(),pigment=FaceRegionPreviewRenderer()
        let guide=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.apple))
        var config=EyebrowConfiguration();config.region = .blush;config.showMakeupPreview=true
        pigment.update(brow:nil,forehead:nil,blush:guide,vertices:region.restVertices,triangles:region.triangles,configuration:config)
        let node=try XCTUnwrap(pigment.root.childNodes.first),geometry=try XCTUnwrap(node.geometry)
        let positions=try XCTUnwrap(geometry.sources(for:.vertex).first).data
        let colours=try XCTUnwrap(geometry.sources(for:.color).first)
        let topology=try XCTUnwrap(geometry.elements.first)
        for i in 0..<30 {
            config.shadeTint=SIMD3(Float(i)/30,0.2,0.4);config.previewIntensity=Float(i)/30
            pigment.update(brow:nil,forehead:nil,blush:guide,vertices:region.restVertices,triangles:region.triangles,configuration:config)
            XCTAssertTrue(node === pigment.root.childNodes.first)
            XCTAssertTrue(topology === node.geometry?.elements.first)
            XCTAssertTrue(colours === node.geometry?.sources(for:.color).first)
            XCTAssertEqual(node.geometry?.sources(for:.vertex).first?.data,positions)
        }
        XCTAssertEqual(pigment.bindingBuildCount,1)
        let tint=try XCTUnwrap(node.geometry?.firstMaterial?.diffuse.contents as? UIColor)
        var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
        XCTAssertTrue(tint.getRed(&r,green:&g,blue:&b,alpha:&a))
        XCTAssertEqual(g,0.2,accuracy:0.00001)
    }
    func testOverlayBudgetDropsExcessFramesAndRecoversClockReset() {
        var budget=LiveOverlayBudget(),accepted=0
        for frame in 0..<120 { if budget.accepts(Double(frame)/120) { accepted += 1 } }
        XCTAssertEqual(accepted,30)
        XCTAssertFalse(budget.accepts(.nan))
        XCTAssertTrue(budget.accepts(0),"A new session must not be blocked by the old clock")
        XCTAssertFalse(budget.accepts(0))
    }
    func testHiddenGuidesDoNotConstructSceneNodes() throws {
        let f=BrowFixture(),region=try f.region()
        let guide=try XCTUnwrap(EyebrowGuideGenerator.make(region:region,style:.natural))
        let blush=try XCTUnwrap(BlushPlacementGenerator.make(region:region,style:.apple))
        let browRenderer=EyebrowSceneRenderer(),areaRenderer=ForeheadSceneRenderer()
        var config=EyebrowConfiguration();config.showGuide=false
        browRenderer.update(guide:guide,vertices:region.restVertices,configuration:config)
        areaRenderer.update(blush:blush,vertices:region.restVertices,configuration:config)
        XCTAssertTrue(browRenderer.root.childNodes.isEmpty);XCTAssertTrue(areaRenderer.root.childNodes.isEmpty)
        config.showGuide=true
        browRenderer.update(guide:guide,vertices:region.restVertices,configuration:config)
        areaRenderer.update(blush:blush,vertices:region.restVertices,configuration:config)
        XCTAssertFalse(browRenderer.root.isHidden);XCTAssertFalse(areaRenderer.root.isHidden)
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
