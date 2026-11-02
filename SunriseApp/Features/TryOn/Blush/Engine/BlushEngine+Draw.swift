// -Nimah: Blush parts of the makeup engine (moved from BeautyBlushEngine.swift, no change): the cheek fit from MediaPipe
// landmarks, the tutorial guide outlines, binding the face mesh and baking the pigment atlas (`bind`), and the per-frame
// blush pass (`prepareBlush` before the encoder, `encodeBlush` inside it). The shared engine lives in Core/Engine.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI
import QuartzCore

extension BeautyBlushEngine {
    /// Hands a frame to MediaPipe for the blush cheek fit, at most 15 times a second, only while ARKit tracks the face in it.
    func submitBlushLandmarks(_ frame:ARFrame,settings s:Settings) {
        guard browTracker.isAvailable,!browTracker.isBusy,Self.browFrameDue(timestamp:frame.timestamp,last:lastBrowSubmit,maxFPS:15),
              let face=browFaceFrame(frame) else {return}
        submitToBrowTracker(frame,face:face,settings:s)
    }
    /// A MediaPipe answer while blush is selected: a frontal face's cheek landmarks, lifted onto the same frame's ARKit mesh, are
    /// kept; after `blushLandmarkSamples` of them their median becomes this anchor's cheek fit and the atlas is re-baked.
    func collectBlushLandmarks(_ result:BrowTrackerResult) {
        lock.lock();let entry=browFrames.removeValue(forKey:result.token);let s=settings;lock.unlock()
        guard let entry,s.enabled,!s.isBrow,s.epoch==entry.epoch,let o=result.observation else {return}
        addBlushSample(o,face:entry.face)
    }
    /// One MediaPipe answer for the blush cheek fit (blush alone, or alongside the brow). Frontal faces only; render queue.
    func addBlushSample(_ o:BrowObservation,face:BrowFaceFrame?) {
        guard let face,o.mesh.count>=468,abs(o.pose.yaw)<15,abs(o.pose.pitch)<15 else {return}
        lock.lock();let measured=blushLandmarks?.anchor==face.anchorID;lock.unlock()
        guard !measured else {return}
        if blushSampleAnchor != face.anchorID {blushSamples=[];blushSampleAnchor=face.anchorID}
        let points=BlushCheekLandmarks.indices.compactMap {face.faceLocal(at:o.mesh[$0])}
        guard BlushCheekLandmarks(points:points) != nil else {return}
        blushSamples.append(points)
        guard blushSamples.count>=Self.blushLandmarkSamples,let median=BlushCheekLandmarks.median(blushSamples),
              let value=BlushCheekLandmarks(points:median) else {return}
        blushSamples=[]
        lock.lock();blushLandmarks=(face.anchorID,value);attemptedBlushStyle=nil;lastBindAttempt = -.infinity;lock.unlock()
    }
    /// The tutorial's inner circle (`innerScale` of the field) and outer line (`outerScale`), clipped to the field's nose, eye
    /// and face-edge limits like the pigment, bound to the rest mesh. Nil when the cheek cannot be bound.
    static let guideInnerScale:Float=0.38,guideOuterScale:Float=0.82
    static func guideOutline(_ f:BlushPigmentField,vertices:[SIMD3<Float>],triangles:[Int16],minimumZ:Float)->GuideOutline? {
        func point(_ a:Float,_ scale:Float)->SIMD2<Float> {
            let nx=cos(a),q=SIMD2(f.radius.x*scale*nx,f.radius.y*scale*(sin(a)+f.curvature*(nx*nx-0.25)))
            let p=f.center+SIMD2(f.side*(q.x*cos(f.angle)-q.y*sin(f.angle)),q.x*sin(f.angle)+q.y*cos(f.angle))
            return SIMD2(f.side*max(f.nasalLimit,min(f.outerLimit,f.side*p.x)),min(f.eyeLimit,p.y))
        }
        func bind(_ p:SIMD2<Float>)->SurfaceAttachment? {SurfaceAttachment.bind(p,vertices:vertices,triangles:triangles,minimumZ:minimumZ)}
        func ring(_ scale:Float)->[SurfaceAttachment]? {
            let bound=(0..<48).compactMap {bind(point(Float($0)/48*2*Float.pi,scale))}
            return bound.count>=40 ? bound:nil
        }
        let outward=f.center+SIMD2(f.side*cos(f.angle),sin(f.angle))*f.radius.x*0.6
        guard let inner=ring(guideInnerScale),let outer=ring(guideOuterScale),let c=bind(f.center),let o=bind(outward) else {return nil}
        return GuideOutline(inner:inner,outer:outer,center:c,outward:o)
    }
    /// Face-local outline points to view points through the frame's `mvp`; nil when any cheek falls behind the camera.
    static func projectGuide(_ outlines:[GuideOutline],vertices:[SIMD3<Float>],mvp:simd_float4x4,viewport:CGSize)->BlushGuideSnapshot? {
        func view(_ a:SurfaceAttachment)->CGPoint? {
            guard let p=a.position(in:vertices) else {return nil}
            let c=mvp*SIMD4(p,1)
            guard c.w>1e-5 else {return nil}
            return CGPoint(x:CGFloat(c.x/c.w+1)/2*viewport.width,y:CGFloat(1-c.y/c.w)/2*viewport.height)
        }
        var cheeks:[BlushGuideSnapshot.Cheek]=[]
        for o in outlines {
            guard let center=view(o.center),let outward=view(o.outward) else {return nil}
            cheeks.append(.init(inner:o.inner.compactMap(view),outer:o.outer.compactMap(view),center:center,outward:outward))
        }
        return cheeks.isEmpty ? nil:BlushGuideSnapshot(cheeks:cheeks)
    }
    /// The measured cheek landmarks for this anchor, when the requested look uses them.
    func cheekLandmarks(for anchor:ARFaceAnchor,style requested:BlushPlacementStyle)->BlushCheekLandmarks? {
        guard requested.isReferenceLook else {return nil}
        lock.lock();defer {lock.unlock()}
        return blushLandmarks?.anchor==anchor.identifier ? blushLandmarks?.value:nil
    }
    func bind(_ geometry:ARFaceGeometry,face anchor:ARFaceAnchor,frame:ARFrame,style requested:BlushPlacementStyle,command:MTLCommandBuffer)throws {
        let cheeks=cheekLandmarks(for:anchor,style:requested)
        if anchorID==anchor.identifier && style==requested && atlas != nil && (atlasFromLandmarks || cheeks==nil) {return}
        let current=Array(geometry.vertices),triangles=Array(geometry.triangleIndices)
        let eyes=[anchor.leftEyeTransform,anchor.rightEyeTransform].map {SIMD3($0.columns.3.x,$0.columns.3.y,$0.columns.3.z)}
        guard let region=LaunchMakeupFit.shared.fittedRegion(anchorID:anchor.identifier,vertices:current,triangles:triangles,timestamp:frame.timestamp,eyeCenters:eyes) else {throw CocoaError(.coderInvalidValue)}
        guard let guide=BlushPlacementGenerator.make(region:region,style:requested,cheeks:cheeks) ?? BlushPlacementGenerator.make(region:region,style:requested),
              guide.pigmentFields.count==2 else {throw CocoaError(.coderInvalidValue)}
        rest=region.restVertices;uvs=Array(geometry.textureCoordinates)
        guard rest.count==current.count,uvs.count==rest.count else {throw CocoaError(.coderInvalidValue)}
        filters=Array(repeating:OneEuroFilter(),count:rest.count*3)
        let data=rest.indices.map {Vertex(position:SIMD4(rest[$0],1),rest:SIMD4(rest[$0],1),uv:SIMD4(uvs[$0].x,uvs[$0].y,0,0))}
        vertices=(0..<3).compactMap {_ in device.makeBuffer(length:data.count*MemoryLayout<Vertex>.stride,options:.storageModeShared)}
        bakeVertices=data.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
        indices=triangles.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
        guard vertices.count==3,let vb=bakeVertices,let ib=indices else {throw CocoaError(.featureUnsupported)}
        indexCount=triangles.count
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:config.atlas_size,height:config.atlas_size,mipmapped:true)
        desc.usage=[.renderTarget,.shaderRead];desc.storageMode = .private
        guard let target=device.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else {throw CocoaError(.featureUnsupported)}
        func field(_ f:BlushPigmentField)->Field {.init(ellipse:SIMD4(f.center.x,f.center.y,f.radius.x,f.radius.y),shape:SIMD4(f.side,f.angle,f.opacity,f.power),limits:SIMD4(f.nasalLimit,f.outerLimit,f.eyeLimit,f.edgeFeather))}
        var b=Bake(left:field(guide.pigmentFields[0]),right:field(guide.pigmentFields[1]),options:SIMD4(guide.pigmentFields[0].smoothstepMix,guide.pigmentFields[1].smoothstepMix,config.paint_feather,0))
        if let bridge=guide.noseBridge {b.bridge=field(bridge)}
        b.paint=SIMD4(guide.pigmentFields[0].curvature,requested.isReferenceLook ? 1:0,guide.pigmentFields.allSatisfy(\.wash) ? 1:0,0)
        b.mouth=Self.mouthExclusion(vertices:rest,triangles:triangles,eyes:eyes)
        e.setRenderPipelineState(atlasPipeline);e.setVertexBuffer(vb,offset:0,index:0);e.setFragmentBytes(&b,length:MemoryLayout<Bake>.stride,index:0);e.setFragmentTexture(brush,index:0)
        e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        if let mip=command.makeBlitCommandEncoder() {mip.generateMipmaps(for:target);mip.endEncoding()}
        atlas=target;anchorID=anchor.identifier;style=requested;atlasFromLandmarks=guide.pigmentFields.contains(where:\.wash)
        let minimumZ=(eyes[0].z+eyes[1].z)/2-0.06
        guideOutlines=guide.pigmentFields.compactMap {Self.guideOutline($0,vertices:rest,triangles:triangles,minimumZ:minimumZ)}
    }
    // Native mesh boundary components, not invented landmark indices. Largest loop is the outer face.
    // A centered lower inner loop supplies an observed mouth-opening bound; expand modestly to protect lips.
    static func mouthExclusion(vertices:[SIMD3<Float>],triangles:[Int16],eyes:[SIMD3<Float>])->SIMD4<Float> {
        BlushPlacementGenerator.mouthExclusion(vertices:vertices,triangles:triangles,eyes:eyes)
    }

    /// One frame's blush face pass, prepared before the frame's render encoder starts (it may bake the atlas on `command`):
    /// fit and atlas, hand mask, visibility, this frame's smoothed mesh and the tutorial outlines. `surface` is nil when
    /// there is no face to draw on; `u` is still valid for the camera background.
    struct BlushPrepared {
        var u:Uniforms
        var surface:(buffer:MTLBuffer,atlas:MTLTexture,indices:MTLBuffer,obstruction:MTLTexture)?
        var diagnostic:BlushDiagnostic
        var opacity:Double,fresh:Bool,tracked:Bool
        var view:simd_float4x4,projection:simd_float4x4
    }
    func prepareBlush(_ frame:ARFrame,face anchor:ARFaceAnchor?,settings s:Settings,frameSlot:Int,size:CGSize,command:MTLCommandBuffer)->BlushPrepared {
        // -Nimah: Match ARSCNView camera orientation; do not add a category-only reflection.
        let raw=Self.affine(frame.displayTransform(for:s.orientation,viewportSize:s.viewport).inverted())
        let view=frame.camera.viewMatrix(for:s.orientation)
        let projection=frame.camera.projectionMatrix(for:s.orientation,viewportSize:s.viewport,zNear:0.001,zFar:10)
        let relative=anchor.map {simd_inverse(frame.camera.transform)*$0.transform}
        let angle=relative.map {acos(max(-1,min(1,simd_normalize(SIMD3($0.columns.2.x,$0.columns.2.y,$0.columns.2.z)).z)))*180/Float.pi} ?? 180
        let normal:Bool;if case .normal=frame.camera.trackingState {normal=true}else{normal=false}
        let tracked=normal && anchor?.isTracked==true && angle<config.max_yaw_degrees
        let rawSize=CGSize(width:CVPixelBufferGetWidth(frame.capturedImage),height:CVPixelBufferGetHeight(frame.capturedImage))
        let headAnchors:[CGPoint]=anchor.map {face in
            [SIMD4<Float>(-0.04,0.025,0,1),SIMD4<Float>(0.04,0.025,0,1),SIMD4<Float>(0,-0.035,0,1)].map {p in
                let w=face.transform*p
                return frame.camera.projectPoint(SIMD3(w.x,w.y,w.z),orientation:.landscapeRight,viewportSize:rawSize)
            }
        } ?? []
        if let anchor,tracked {
            // Retry an unavailable fit at a bounded cadence instead of rebuilding
            // the same atlas on every frame.
            // Re-baked once when the MediaPipe cheek fit arrives over the ARKit-only fallback.
            let styleNeedsBind = anchorID != anchor.identifier || style != s.style || (!atlasFromLandmarks && cheekLandmarks(for:anchor,style:s.style) != nil)
            lock.lock()
            let requestChanged = attemptedBlushStyle != s.style
            let canAttempt = !styleNeedsBind || requestChanged || frame.timestamp - lastBindAttempt >= 0.5
            if styleNeedsBind && canAttempt {
                attemptedBlushStyle=s.style
                lastBindAttempt = frame.timestamp
            }
            lock.unlock()
            if styleNeedsBind && canAttempt {
                do {
                    try bind(anchor.geometry,face:anchor,frame:frame,style:s.style,command:command)
                    if lastError?.hasPrefix("fit_or_atlas_unavailable:")==true {lastError=nil}
                } catch {lastError="fit_or_atlas_unavailable: \(error)"}
            }
            if frame.timestamp-lastSegment>=1/15 && !segmenter.isBusy && segmenter.isAvailable {
                lastSegment=frame.timestamp
                let rawSize=CGSize(width:CVPixelBufferGetWidth(frame.capturedImage),height:CVPixelBufferGetHeight(frame.capturedImage))
                let center=frame.camera.projectPoint(SIMD3(anchor.transform.columns.3.x,anchor.transform.columns.3.y,anchor.transform.columns.3.z),orientation:.landscapeRight,viewportSize:rawSize)
                let upWorld=anchor.transform*SIMD4<Float>(0,0.05,0,1)
                let up=frame.camera.projectPoint(SIMD3(upWorld.x,upWorld.y,upWorld.z),orientation:.landscapeRight,viewportSize:rawSize)
                segmenter.submit(.init(pixelBuffer:SendablePixelBuffer(buffer:frame.capturedImage),timestamp:frame.timestamp,headUp:CGPoint(x:up.x-center.x,y:up.y-center.y),headAnchors:headAnchors))
            }
        }
        if segmenter.isAvailable && lastError?.hasPrefix("segmentation_unavailable:")==true {lastError=nil}
        lock.lock();let mask=latestMask;lock.unlock()
        let age=mask.map {CACurrentMediaTime()-$0.time} ?? .infinity
        let dimensionsMatch=mask.map {Int($0.rawSize.width)==CVPixelBufferGetWidth(frame.capturedImage) && Int($0.rawSize.height)==CVPixelBufferGetHeight(frame.capturedImage)} ?? false
        let fresh=dimensionsMatch && age>=0 && age<=config.mask_max_age_seconds
        let motion=mask.flatMap {SimilarityTransform(from:headAnchors,to:$0.headAnchors)}
        let usableMotion=motion?.isPlausible ?? false
        let maskWeight=dimensionsMatch && (fresh || usableMotion) ? BeautyMaskContinuity.weight(age:age,freshAge:config.mask_max_age_seconds,fadeSeconds:config.mask_fade_seconds):0
        var maskTransform=matrix_identity_float4x4
        var frameMask:MTLTexture?
        if let mask,dimensionsMatch {
            let w=Int(mask.size.width),h=Int(mask.size.height)
            if lastMaskTime != mask.time {
                cachedMaskBytes=mask.opacity.count==w*h ? mask.opacity:mask.occupied.map { $0==0 ? UInt8(0):UInt8(255) }
                lastMaskTime=mask.time
            }
            // Match the vertex-buffer ring: never replace a mask while its GPU command is in flight.
            if maskTextures[frameSlot]?.width != w || maskTextures[frameSlot]?.height != h {
                let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Unorm,width:w,height:h,mipmapped:false);d.usage = .shaderRead;d.storageMode = .shared
                maskTextures[frameSlot]=device.makeTexture(descriptor:d);maskVersions[frameSlot] = -1
            }
            if maskVersions[frameSlot] != mask.time && cachedMaskBytes.count==w*h {
                cachedMaskBytes.withUnsafeBytes {p in if let address=p.baseAddress {maskTextures[frameSlot]?.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:address,bytesPerRow:w)}}
                maskVersions[frameSlot]=mask.time
            }
            frameMask=maskTextures[frameSlot]
            let rawPixels=CGAffineTransform(scaleX:mask.rawSize.width,y:mask.rawSize.height)
            let normalize=CGAffineTransform(scaleX:1/mask.size.width,y:1/mask.size.height)
            let reprojection=usableMotion ? motion!.affine:CGAffineTransform.identity
            maskTransform=Self.affine(rawPixels.concatenating(reprojection).concatenating(mask.toImage.inverted()).concatenating(normalize))
        }
        maskAgeMilliseconds=mask.map {max(0,CACurrentMediaTime()-$0.time)*1000} ?? -1
        let compatible=anchorID==anchor?.identifier && style==s.style && atlas != nil
        let visible=blushVisibility.update(timestamp:frame.timestamp,target:tracked && compatible ? maskWeight:0,tau:config.visibility_tau_seconds)
        let opacity=maskWeight>0 ? BeautyMaskContinuity.opacity(filtered:visible,age:age,freshAge:config.mask_max_age_seconds,fadeSeconds:config.mask_fade_seconds):0
        let matrixAttachment=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferYCbCrMatrixKey,nil) as? String
        let transfer=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferTransferFunctionKey,nil) as? String
        let full=CVPixelBufferGetPixelFormatType(frame.capturedImage)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var u=Uniforms(mvp:projection*view*(anchor?.transform ?? matrix_identity_float4x4),rawFromClip:raw,maskFromRaw:maskTransform,
            shade:SIMD4(BeautyBlushConfiguration.linear(s.blushTint.x),BeautyBlushConfiguration.linear(s.blushTint.y),BeautyBlushConfiguration.linear(s.blushTint.z),s.blushIntensity),
            controls:SIMD4(config.coverage,config.absorption,config.saturation,config.pigment_mix),tracking:SIMD4(Float(opacity),0,1/Float(size.width),1/Float(size.height)),
            camera:SIMD4(matrixAttachment==(kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 1:0,full ? 1:0,transfer==(kCVImageBufferTransferFunction_ITU_R_709_2 as String) ? 1:0,0),
            stretch:SIMD4(config.stretch_fade[0],config.stretch_fade[1],config.stretch_fade[2],config.stretch_fade[3]))
        let developer=UserDefaults.standard.bool(forKey:DeveloperTools.key)
        let blend=developer ? BlushBlend(rawValue:UserDefaults.standard.integer(forKey:Self.blushBlendKey)) ?? .pigment:.pigment
        let diagnostic=developer ? BlushDiagnostic(rawValue:UserDefaults.standard.integer(forKey:Self.blushDiagnosticKey)) ?? .final:.final
        u.blush=SIMD4(Float(blend.rawValue),Float(diagnostic.shaderValue),config.detail_radius_px,0)
        var surface:(buffer:MTLBuffer,atlas:MTLTexture,indices:MTLBuffer,obstruction:MTLTexture)?
        if let anchor,anchorID==anchor.identifier,style==s.style,let atlas,let ib=indices,let obstruction=frameMask,!vertices.isEmpty {
            let buffer=vertices[frameSlot]
            let pointer=buffer.contents().bindMemory(to:Vertex.self,capacity:rest.count)
            let points=anchor.geometry.vertices
            let smoothing=OneEuroConfig(minCutoff:config.min_cutoff_hz,beta:config.velocity_beta,dCutoff:1,deadband:0)
            let publishGuide=s.guide && !guideOutlines.isEmpty && frame.timestamp-lastGuidePublish>=1.0/30
            var drawn:[SIMD3<Float>]=[]
            if publishGuide {drawn.reserveCapacity(rest.count)}
            for i in rest.indices {
                var p=points[i]
                for axis in 0..<3 {p[axis]=Float(filters[i*3+axis].filter(Double(p[axis]),t:frame.timestamp,config:smoothing))}
                p=BeautyBlushConfiguration.limitResidual(filtered:p,current:points[i])
                pointer[i]=Vertex(position:SIMD4(p,1),rest:SIMD4(rest[i],1),uv:SIMD4(uvs[i].x,uvs[i].y,0,0))
                if publishGuide {drawn.append(p)}
            }
            if publishGuide {
                // The same surface the pigment is drawn on this frame, so the outlines sit exactly on the blush.
                lastGuidePublish=frame.timestamp
                // Follows face tracking only. Pigment opacity also rises and falls with the hand mask's age, which made
                // the outlines blink several times a second.
                if tracked,let snapshot=Self.projectGuide(guideOutlines,vertices:drawn,mvp:u.mvp,viewport:s.viewport) {
                    guideSeen=frame.timestamp;onBlushGuide?(snapshot);guidePublished=true
                } else if guidePublished && frame.timestamp-guideSeen>Self.guideHoldSeconds {onBlushGuide?(nil);guidePublished=false}
            }
            surface=(buffer,atlas,ib,obstruction)
        }
        // Outlines leave with the face, or when the tutorial guide is turned off.
        let guideSurface=anchor.map {anchorID==$0.identifier && style==s.style && atlas != nil} ?? false
        if guidePublished && (!s.guide || (!guideSurface && frame.timestamp-guideSeen>Self.guideHoldSeconds)) {onBlushGuide?(nil);guidePublished=false}
        return BlushPrepared(u:u,surface:surface,diagnostic:diagnostic,opacity:opacity,fresh:fresh,tracked:tracked,view:view,projection:projection)
    }
    /// Draws a prepared blush onto the face (depth prepass, pigment, optional wireframe), leaving depth testing off.
    func encodeBlush(_ p:BlushPrepared,_ e:MTLRenderCommandEncoder) {
        guard let surface=p.surface else {return}
        var u=p.u
        e.setCullMode(.none) // Native mesh depth prepass resolves visible surfaces without mirrored-winding assumptions.
        e.setVertexBuffer(surface.buffer,offset:0,index:0);e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
        e.setRenderPipelineState(depth);e.setDepthStencilState(depthWrite)
        e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:surface.indices,indexBufferOffset:0)
        e.setRenderPipelineState(face);e.setDepthStencilState(depthRead);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0)
        e.setFragmentTexture(surface.atlas,index:2);e.setFragmentTexture(surface.obstruction,index:3)
        e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:surface.indices,indexBufferOffset:0)
        if p.diagnostic == .wireframe {
            // The native ARKit triangles as drawn this frame, front and back (no depth test).
            e.setRenderPipelineState(wire);e.setDepthStencilState(noDepth);e.setTriangleFillMode(.lines)
            e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:surface.indices,indexBufferOffset:0)
            e.setTriangleFillMode(.fill)
        }
        e.setDepthStencilState(noDepth)
    }
}
