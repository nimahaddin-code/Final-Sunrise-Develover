// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): the brow strip, brow texture or picture, and drawing a frame with its landmarks.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

extension BeautyBlushEngine {
    // MARK: MediaPipe brow

    /// Brow-space extent of the baked brow texture and of the strip laid over each brow: u from just before the head
    /// to just past the tail, and up to `z` brow widths either side of the observed centerline.
    static let browExtent=SIMD4<Float>(-0.3,1.35,0.5,0)
    /// The area hiding the natural brow above the centerline, in brow widths: full cover to `core`, gone by `end`. It
    /// reaches well past MediaPipe's upper brow row, which sits inside the hair, and fades over several millimetres so
    /// no edge shows. Matches `browStripFragment`.
    static func concealUpper(half h:Float)->(core:Float,end:Float) {(h*1.15+0.02,h*2.2+0.10)}
    /// The same below the centerline. It covers the lower brow edge MediaPipe's row also misses and ends at most 85%
    /// of the way down to the upper eyelid. The fade always takes at least the lower 40% of that depth: a short fade
    /// near the eye reads as a hard line, which is worse than a faint trace of lower brow hair.
    static func concealLower(half h:Float,lidDepth:Float?)->(core:Float,end:Float) {
        var core=h*1.1+0.02,end=h*2.0+0.10
        if let lidDepth,lidDepth<0 {end=min(end,-lidDepth*0.85)}
        core=min(core,end*0.6)
        return (core,end)
    }
    static let browColumns=48,browRows=14
    static var browVertexCount:Int {(browColumns+1)*(browRows+1)}
    static var browIndexCount:Int {browColumns*browRows*12}
    static func browGridIndices()->[UInt16] {
        var out:[UInt16]=[]
        for side in 0..<2 {
            for row in 0..<browRows {
                for column in 0..<browColumns {
                    let a=side*browVertexCount+row*(browColumns+1)+column,b=a+1,c=a+browColumns+1,d=c+1
                    out += [a,b,c,b,d,c].map {UInt16($0)}
                }
            }
        }
        return out
    }
    func bakeBrowTexture(_ style:EyebrowStyle,command:MTLCommandBuffer)throws {
        guard let design=BrowDesign.make(style:style) else {throw CocoaError(.coderInvalidValue)}
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1024,height:512,mipmapped:true)
        desc.usage=[.renderTarget,.shaderRead];desc.storageMode = .private
        guard let target=device.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
        try encodeBrowTexture(design,into:target,command:command)
        // Mipmaps and anisotropic sampling keep minified strands from shimmering.
        guard let mip=command.makeBlitCommandEncoder() else {throw CocoaError(.featureUnsupported)}
        mip.generateMipmaps(for:target);mip.endEncoding()
        browTexture=target;browTextureKey="style:\(style.rawValue)"
    }
    /// Uploads a baked overlay picture as the brow texture (mipmapped like the designs).
    func uploadBrowOverlay(_ baked:BakedBrowSprite,id:String,command:MTLCommandBuffer)throws {
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:baked.width,height:baked.height,mipmapped:true)
        desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
        guard let target=device.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
        baked.texels.withUnsafeBytes {target.replace(region:MTLRegionMake2D(0,0,baked.width,baked.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:baked.width*8)}
        guard let mip=command.makeBlitCommandEncoder() else {throw CocoaError(.featureUnsupported)}
        mip.generateMipmaps(for:target);mip.endEncoding()
        browTexture=target;browTextureKey="overlay:\(id)"
    }
    func encodeBrowTexture(_ design:BrowDesign,into target:MTLTexture,command:MTLCommandBuffer)throws {
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else {throw CocoaError(.featureUnsupported)}
        var data=design.points+[SIMD4(design.maxAlpha,design.headFade,design.edgeFeather,0),Self.browExtent]
        e.setRenderPipelineState(browTexturePipeline)
        e.setFragmentBytes(&data,length:data.count*MemoryLayout<SIMD4<Float>>.stride,index:0)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);e.endEncoding()
    }
    /// The strip over both brows for one observation, in clip space; nil when a brow cannot be framed.
    /// With `chord`, each vertex also carries how far the observed centerline lies above the brow's head-to-tail chord, so
    /// an overlay picture (drawn in chord space) keeps its own arch.
    static func browStrip(_ o:BrowObservation,display:CGAffineTransform,chord:Bool=false)->BrowStrip? {
        guard let right=o.brows[.subjectRight],let left=o.brows[.subjectLeft],
              let r0=BrowGeometry(contour:right),let l0=BrowGeometry(contour:left) else {return nil}
        let across=max(r0.width,l0.width)
        guard let r=BrowGeometry(contour:right,across:across),let l=BrowGeometry(contour:left,across:across) else {return nil}
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        func clip(_ p:SIMD2<Float>)->SIMD4<Float> {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display)
            return SIMD4(Float(v.x)*2-1,1-Float(v.y)*2,0,1)
        }
        // Blur radius for the camera's own low frequency when the natural brow is hidden: about 2.5 mm, wider than
        // hair spacing, narrower than the brow, in camera coordinates.
        let blur=across*0.05/image
        var out:[BrowVertex]=[],unwrap:[BrowUnwrapVertex]=[]
        out.reserveCapacity(browVertexCount*2);unwrap.reserveCapacity(BrowEraser.vertexCount*2)
        let cropToRaw=BrowEraser.faceCrop(o)
        for (side,g) in [(EyeSide.subjectRight,r),(.subjectLeft,l)] {
            let lid=o.eyes[side]?.lid ?? []
            func lower(_ u:Float)->(core:Float,end:Float) {concealLower(half:g.observedHalf(u),lidDepth:g.depth(of:lid,at:u))}
            // A brow much shorter than the other is turned away: fade it rather than squeeze its strands.
            let ratio=g.width/across,fade=max(0,min(1,(ratio-0.35)/0.25))
            let index:Float=side == .subjectRight ? 0:1
            // The centerline is evaluated once per column; every row of both grids is a step across it.
            let columns=(0...browColumns).map {column->(u:Float,half:Float,lower:(core:Float,end:Float),bow:Float,section:(point:SIMD2<Float>,across:SIMD2<Float>)) in
                let u=browExtent.x+(browExtent.y-browExtent.x)*Float(column)/Float(browColumns)
                return (u,g.observedHalf(u),lower(u),chord ? g.chordOffset(u):0,g.section(u))
            }
            for row in 0...browRows {
                let w=browExtent.z*(2*Float(row)/Float(browRows)-1)
                for c in columns {
                    let p=c.section.point+c.section.across*w,step=c.section.across*0.2
                    let above=(p+step)/image,below=(p-step)/image
                    out.append(BrowVertex(position:clip(p),brow:SIMD4(c.u,w,c.half,fade*fade*(3-2*fade)),
                                          probes:SIMD4(above.x,above.y,below.x,below.y),skin:SIMD4(blur.x,blur.y,c.bow,0),
                                          conceal:SIMD4(c.lower.core,c.lower.end,index,0)))
                }
            }
            // Unwrap grid for hiding the natural brow: the same columns, from below the brow up into the forehead.
            let space=BrowEraser.space
            for row in 0...BrowEraser.rows {
                let w=space.z+(space.w-space.z)*Float(row)/Float(BrowEraser.rows)
                for c in columns {
                    let p=c.section.point+c.section.across*w
                    let crop=cropToRaw.map {BrowEraser.cropPoint(p,imageSize:o.imageSize,cropToRaw:$0)} ?? SIMD2(-2,-2)
                    unwrap.append(BrowUnwrapVertex(brow:SIMD4(c.u,w,c.half,index),raw:SIMD4(p.x/image.x,p.y/image.y,crop.x*2-1,1-crop.y*2),
                                                   conceal:SIMD4(c.lower.core,c.lower.end,0,0)))
                }
            }
        }
        guard out.allSatisfy({$0.position.x.isFinite && $0.position.y.isFinite}),unwrap.allSatisfy({$0.raw.x.isFinite && $0.raw.y.isFinite}) else {return nil}
        return BrowStrip(vertices:out,unwrap:unwrap,cropToRaw:cropToRaw)
    }
    /// Brow status as soon as it changes: no face, mask not ready, or an error. Render queue only.
    func publishBrowStatus() {
        let next:String?=lastError != nil ? String(localized:"Makeup is temporarily unavailable")
            : (!browFaceVisible ? String(localized:"Look straight at the camera to place your makeup")
            : (!browMaskFresh ? String(localized:"Preparing makeup visibility"):nil))
        if case .some(let current)=browStatus,current==next {return}
        browStatus = .some(next);onStatus?(next)
    }
    /// Draws one camera frame with `observation` (already steadied and placed on this frame); `detected` is MediaPipe's raw
    /// answer it came from, for the tracking view.
    func drawBrow(_ frame:ARFrame,observation:BrowObservation?,raw detected:BrowObservation?,face:BrowFaceFrame?,settings s:Settings) {
        guard inFlight.wait(timeout:.now()) == .success else{return}
        var committed=false
        defer {if !committed {inFlight.signal()}}
        let buffer=frame.capturedImage
        guard CVPixelBufferGetPlaneCount(buffer)>=2,let (cy,y)=texture(buffer,plane:0,format:.r8Unorm),let (cc,cb)=texture(buffer,plane:1,format:.rg8Unorm),
              browVertices.count==3,let ib=browIndices,let drawable=layer?.nextDrawable(),let command=commands.makeCommandBuffer() else{return}
        let frameSlot=slot%3;slot += 1
        let size=CGSize(width:drawable.texture.width,height:drawable.texture.height)
        ensureDepth(for:drawable)
        if let overlay=s.browOverlay {
            // The picture is baked off this queue; until it is ready the previous texture stays (or none: nothing is drawn).
            if browTextureKey != "overlay:\(overlay.id)" {
                if let baked=BrowSpriteStore.shared.baked(overlay) {
                    do {try uploadBrowOverlay(baked,id:overlay.id,command:command);if lastError?.hasPrefix("brow_texture_unavailable:")==true {lastError=nil}}
                    catch {lastError="brow_texture_unavailable: \(error)"}
                } else if BrowSpriteStore.shared.hasFailed(overlay) {lastError="brow_texture_unavailable: overlay \(overlay.id)"}
                else {BrowSpriteStore.shared.prepare(overlay)}
            }
        } else if browTexture==nil || browTextureKey != "style:\(s.browStyle.rawValue)" {
            do {try bakeBrowTexture(s.browStyle,command:command);if lastError?.hasPrefix("brow_texture_unavailable:")==true {lastError=nil}}
            catch {lastError="brow_texture_unavailable: \(error)"}
        }
        let display=frame.displayTransform(for:s.orientation,viewportSize:s.viewport)
        let tracked=observation.map {abs($0.pose.yaw)<config.max_yaw_degrees && abs($0.pose.pitch)<config.max_yaw_degrees} ?? false
        // A 3D brow needs ARKit's face in this frame (browStabilized) and its mesh; otherwise its picture is drawn instead.
        let hairMesh=s.browOverlay?.is3D==true && browStabilized && tracked ? hairMeshIfReady():nil
        var hairDraws:[HairDraw]=[]
        if let hairMesh,let observation,let face {hairDraws=Self.hairPlacements(observation,face:face,mesh:hairMesh)}
        let hair3D = !hairDraws.isEmpty
        let pigment=s.browOverlay != nil && !hair3D
        let strip=tracked && (pigment || s.hideNatural) ? observation.flatMap {Self.browStrip($0,display:display,chord:pigment)}:nil
        let (frameMask,maskTransform,fresh)=uploadMask(slot:frameSlot,capturedImage:buffer,maxAge:max(config.mask_max_age_seconds,Self.browMaskGraceSeconds))
        // The brow does not wait for the hand mask: when the segmenter falls behind (it shares the GPU with the brow
        // tracker and the inpainter) the brow is drawn without occlusion instead of fading out. A mask up to
        // `browMaskGraceSeconds` old still keeps hands in front.
        let ready=true
        let visible=visibility.update(timestamp:frame.timestamp,visible:(strip != nil || hair3D) && ready && (browTexture != nil || hair3D),tau:config.visibility_tau_seconds)
        let debugView=UserDefaults.standard.bool(forKey:DeveloperTools.key) ? UserDefaults.standard.integer(forKey:Self.browDebugKey):0
        let matrixAttachment=CVBufferCopyAttachment(buffer,kCVImageBufferYCbCrMatrixKey,nil) as? String
        let transfer=CVBufferCopyAttachment(buffer,kCVImageBufferTransferFunctionKey,nil) as? String
        let full=CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:Self.affine(display.inverted()),maskFromRaw:maskTransform,
            shade:SIMD4(BeautyBlushConfiguration.linear(s.tint.x),BeautyBlushConfiguration.linear(s.tint.y),BeautyBlushConfiguration.linear(s.tint.z),s.intensity),
            controls:SIMD4(config.coverage,config.absorption,config.saturation,config.pigment_mix),tracking:SIMD4(ready ? Float(visible):0,s.guide && pigment ? 1:0,1/Float(size.width),1/Float(size.height)),
            camera:SIMD4(matrixAttachment==(kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 1:0,full ? 1:0,transfer==(kCVImageBufferTransferFunction_ITU_R_709_2 as String) ? 1:0,1),
            stretch:SIMD4(config.stretch_fade[0],config.stretch_fade[1],config.stretch_fade[2],config.stretch_fade[3]),
            debug:SIMD4(Float(debugView),s.hideNatural && eraser != nil ? 1:0,pigment ? 1:0,pigment ? 1:0))
        // Hiding the natural brow: this frame's brow-space fill; restarted after the brow was not drawn.
        if let strip,s.hideNatural,let eraser {
            eraser.encode(vertices:strip.unwrap,cropToRaw:strip.cropToRaw,uniforms:withUnsafeBytes(of:&u) {Array($0)},y:y,cb:cb,timestamp:frame.timestamp,
                          modelInterval:BrowLoad.current(ProcessInfo.processInfo.thermalState).modelInterval,command:command)
        } else {eraser?.reset()}
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        if let strip,let browTexture,let obstruction=frameMask ?? emptyMask,let fill=s.hideNatural ? eraser?.fill ?? emptyFill:emptyFill,
           strip.vertices.count==Self.browVertexCount*2 {
            let vb=browVertices[frameSlot]
            strip.vertices.withUnsafeBytes {vb.contents().copyMemory(from:$0.baseAddress!,byteCount:$0.count)}
            var extent=Self.browExtent
            e.setRenderPipelineState(browStripPipeline);e.setVertexBuffer(vb,offset:0,index:0)
            e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentBytes(&extent,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
            e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1);e.setFragmentTexture(browTexture,index:2);e.setFragmentTexture(obstruction,index:3)
            var space=BrowEraser.space;e.setFragmentBytes(&space,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
            e.setFragmentTexture(fill,index:4);e.setFragmentTexture(s.hideNatural ? eraser?.hide ?? emptyFill:emptyFill,index:5)
            e.drawIndexedPrimitives(type:.triangle,indexCount:Self.browIndexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0)
        }
        if hair3D,let face,uploadFaceMesh(face,slot:frameSlot) {
            if let estimate=frame.lightEstimate {browLight += (Float(max(0.55,min(1.4,(estimate.ambientIntensity/1000).squareRoot())))-browLight)*0.1}
            let view=frame.camera.viewMatrix(for:s.orientation),projection=frame.camera.projectionMatrix(for:s.orientation,viewportSize:s.viewport,zNear:0.001,zFar:10)
            encodeHair(e,draws:hairDraws,mvp:projection*view*face.faceToWorld,projectionScaleY:projection.columns.1.y,size:size,light:browLight,uniforms:u,obstruction:frameMask ?? emptyMask,slot:frameSlot)
        }
        var marks:[MarkVertex]=[]
        if s.tracking,let observation {marks=Self.browTrackingMarks(observation,raw:detected,display:display,size:size,tracked:tracked)}
        else if let observation,tracked,debugView==2 || (s.guide && s.mapping) {
            // The guide does not wait for the hand mask, or it would vanish whenever the mask is late.
            marks=Self.browMarks(observation,display:display,size:size,landmarks:debugView==2,mapping:s.guide && s.mapping,alpha:1)
        }
        do {
            if !marks.isEmpty,let mb=marks.withUnsafeBytes({device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) {
                e.setRenderPipelineState(browMarkPipeline);e.setVertexBuffer(mb,offset:0,index:0)
                e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:marks.count)
            }
        }
        e.endEncoding()
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { [weak self] _ in self?.queue.async { [weak self] in self?.presentedFrames += 1 } }
        #endif
        command.present(drawable)
        let ts=frame.timestamp
        if strip != nil && fresh && visible>0.9 {pigmentFrames += 1;if lastError?.hasPrefix("brow_tracker_unavailable:") != true {lastError=nil}}
        browFaceVisible=pigment ? strip != nil:observation != nil;browMaskFresh=ready;publishBrowStatus()
        if s.tracking {
            browResultTimes.append(frame.timestamp);browResultTimes.removeAll {frame.timestamp-$0>1}
            let rate=browResultTimes.count>1 ? Double(browResultTimes.count-1)/max(0.001,frame.timestamp-browResultTimes[0]):0
            let snapshot=observation.map {o in
                let pose=Self.screenPose(o,display:display)
                return BrowTrackingSnapshot(faceFound:true,tracked:tracked,yaw:pose.yaw,pitch:pose.pitch,roll:pose.roll,meshPoints:o.mesh.count,
                                     latencyMs:browTracker.lastLatencyMs,rate:rate,labels:Self.browTrackingLabels(o,display:display))
            } ?? BrowTrackingSnapshot(faceFound:false)
            onTracking?(snapshot)
        }
        let retained=FrameLifetime(y:cy,cb:cc,frame:frame)
        let completionGate=inFlight
        command.addCompletedHandler { [weak self] cb in
            completionGate.signal()
            withExtendedLifetime(retained) {}
            Task { @MainActor [weak self] in
                guard let self else{return};self.lock.lock();let show=self.settings.enabled && self.settings.epoch==s.epoch;self.lock.unlock()
                if show {self.setLayerShown(true)}
            }
            self?.queue.async { [weak self] in self?.report(cb,frameTimestamp:ts,maskFresh:fresh,visibility:visible,isBrow:true) }
        }
        committed=true;command.commit()
    }
}
