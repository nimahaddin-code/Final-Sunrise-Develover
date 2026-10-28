// -Nimah: Native ARKit face UV / Metal renderer, one shared camera. All expensive work on a serial render queue.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI
import QuartzCore

@MainActor final class BeautyBlushARView:ARSCNView {
    let beautyLayer=CAMetalLayer()
    var beauty:BeautyBlushEngine?
    override func layoutSubviews() {
        super.layoutSubviews()
        beautyLayer.frame=bounds
        let scale=window?.screen.scale ?? UIScreen.main.scale
        let size=CGSize(width:bounds.width*scale,height:bounds.height*scale)
        beautyLayer.drawableSize=size
        beauty?.setViewport(bounds.size,orientation:window?.windowScene?.interfaceOrientation ?? .portrait)
    }
}
final class BeautyBlushEngine:@unchecked Sendable {
    private struct FrameLifetime:@unchecked Sendable {let y:CVMetalTexture;let cb:CVMetalTexture;let frame:ARFrame}
    private struct Vertex {var position:SIMD4<Float>;var rest:SIMD4<Float>;var uv:SIMD4<Float>}
    private struct Uniforms {
        var mvp:simd_float4x4;var rawFromClip:simd_float4x4;var maskFromRaw:simd_float4x4
        var shade:SIMD4<Float>;var controls:SIMD4<Float>;var tracking:SIMD4<Float>;var camera:SIMD4<Float>;var stretch:SIMD4<Float>
    }
    private struct BrowSegment {var a:SIMD4<Float>;var b:SIMD4<Float>}
    private struct Field {var ellipse:SIMD4<Float>;var shape:SIMD4<Float>;var limits:SIMD4<Float>}
    private struct Bake {var left:Field;var right:Field;var bridge=Field(ellipse:.zero,shape:.zero,limits:.zero);var paint=SIMD4<Float>.zero;var options=SIMD4<Float>.zero;var mouth=SIMD4<Float>.zero}
    private struct Settings {var enabled=false;var tint=SIMD3<Float>(0.9,0.3,0.45);var intensity:Float=0.72;var style=BlushPlacementStyle.cheekbone;var browStyle=EyebrowStyle.natural;var isBrow=false;var guide=false;var viewport=CGSize.zero;var orientation=UIInterfaceOrientation.portrait;var epoch=UUID()}
    private let inFlight=DispatchSemaphore(value:3)
    private let lock=NSLock(),queue=DispatchQueue(label:"dandan.blush.metal",qos:.userInteractive)
    private let device:MTLDevice,commands:MTLCommandQueue
    private let config:BeautyBlushConfiguration
    private let background,face,depth,atlasPipeline,browAtlasPipeline:MTLRenderPipelineState
    private let depthWrite,depthRead,noDepth:MTLDepthStencilState
    private let brush:MTLTexture
    private var textureCache:CVMetalTextureCache?
    private var layer:CAMetalLayer?
    private var settings=Settings(),busy=false
    private var vertices:[MTLBuffer]=[],indices:MTLBuffer?,bakeVertices:MTLBuffer?,indexCount=0,slot=0
    private var rest:[SIMD3<Float>]=[],uvs:[SIMD2<Float>]=[],filters:[OneEuroFilter]=[]
    private var browStabilizers:[BeautyBrowStabilizer]=[]
    private var atlas:MTLTexture?,depthTexture:MTLTexture?
    private var maskTextures:[MTLTexture?]=[nil,nil,nil],maskVersions:[Double]=[-1,-1,-1],cachedMaskBytes:[UInt8]=[]
    private var boundBrowStyle:EyebrowStyle?,boundIsBrow=false
    private var style:BlushPlacementStyle?,anchorID:UUID?,frameTime:Double=0
    private var visibility=BeautyBlushVisibility(),lastSegment:Double=0
    private let segmenter=HandOcclusionSegmenter(faceSkinOnly:true)
    private var segmentationTask:Task<Void,Never>?
    private var segmentationStarting=false,latestMask:OcclusionMask?
    private var lastMaskTime:Double = -1
    private var reportStart=0.0,reportFrames=0,gpuTimes:[Double]=[],ages:[Double]=[]
    var onStatus:(@Sendable (String?)->Void)?
    private var lastError:String?
    private var presentedFrames=0,pigmentFrames=0,projectionErrorPixels:Double=0
    private var maskAgeMilliseconds:Double = -1
    @MainActor static func make(on view:BeautyBlushARView) async->BeautyBlushEngine? {
        do {
            let engine=try await Task.detached(priority:.userInitiated) { try BeautyBlushEngine() }.value
            guard view.window != nil else{return nil}
            view.beautyLayer.device=engine.device;view.beautyLayer.pixelFormat = .bgra8Unorm_srgb
            view.beautyLayer.framebufferOnly=true;view.beautyLayer.isOpaque=true;view.beautyLayer.isHidden=true
            view.beautyLayer.actions=["bounds":NSNull(),"position":NSNull(),"contents":NSNull()]
            view.beautyLayer.maximumDrawableCount=3;view.layer.addSublayer(view.beautyLayer)
            engine.layer=view.beautyLayer;view.beauty=engine;view.setNeedsLayout();return engine
        } catch { UserDefaults.standard.set("setup_error: \(error)",forKey:"beautyBlush.status");return nil }
    }
    private init() throws {
        config=try BeautyBlushConfiguration.load()
        guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue(),let lib=BeautyBlushShaders.library else {throw CocoaError(.featureUnsupported)}
        device=d;commands=q
        func pipeline(_ vertex:String,_ fragment:String,_ format:MTLPixelFormat = .bgra8Unorm_srgb,_ writes:Bool=true)throws->MTLRenderPipelineState {
            let p=MTLRenderPipelineDescriptor();p.vertexFunction=lib.makeFunction(name:vertex);p.fragmentFunction=lib.makeFunction(name:fragment)
            p.colorAttachments[0].pixelFormat=format;p.colorAttachments[0].writeMask=writes ? .all:[]
            if format == .bgra8Unorm_srgb {p.depthAttachmentPixelFormat = .depth32Float}
            return try d.makeRenderPipelineState(descriptor:p)
        }
        background=try pipeline("blushBackgroundVertex","blushBackgroundFragment")
        face=try pipeline("blushFaceVertex","blushPigmentFragment")
        depth=try pipeline("blushFaceVertex","blushDepthFragment",.bgra8Unorm_srgb,false)
        atlasPipeline=try pipeline("blushAtlasVertex","blushAtlasFragment",.rgba16Float)
        browAtlasPipeline=try pipeline("blushAtlasVertex","browAtlasFragment",.rgba16Float)
        func state(_ compare:MTLCompareFunction,_ write:Bool)->MTLDepthStencilState? {let p=MTLDepthStencilDescriptor();p.depthCompareFunction=compare;p.isDepthWriteEnabled=write;return d.makeDepthStencilState(descriptor:p)}
        guard let dw=state(.less,true),let dr=state(.lessEqual,false),let nd=state(.always,false),
              let url=Bundle.main.url(forResource:config.mask_asset,withExtension:nil) else {throw CocoaError(.featureUnsupported)}
        depthWrite=dw;depthRead=dr;noDepth=nd
        brush=try MTKTextureLoader(device:d).newTexture(URL:url,options:[.SRGB:false,.textureUsage:MTLTextureUsage.shaderRead.rawValue])
        CVMetalTextureCacheCreate(nil,nil,d,nil,&textureCache)
        segmenter.onMask={ [weak self] mask in guard let self,let mask else{return};self.lock.lock();self.latestMask=mask;self.lock.unlock() }
    }
    func setViewport(_ size:CGSize,orientation:UIInterfaceOrientation) {lock.lock();settings.viewport=size;settings.orientation=orientation;lock.unlock()}
    @MainActor func configure(_ c:EyebrowConfiguration?) {
        let enabled=c.map { $0.previewAfter && ($0.layered ? ($0.browLayer.on || $0.blushLayer.on):(($0.needsBlush || $0.needsBrow) && $0.showMakeupPreview)) } ?? false
        lock.lock()
        let nextBrow=c.map {$0.needsBrow && !$0.needsBlush} ?? false
        if settings.isBrow != nextBrow || settings.enabled != enabled || (c.map {$0.blushStyle != settings.style} ?? false) {settings.epoch=UUID();layer?.isHidden=true}
        settings.enabled=enabled
        if let c {settings.isBrow=c.needsBrow && !c.needsBlush;settings.browStyle=c.style;settings.style=c.blushStyle;settings.guide=c.showGuide;let selected=settings.isBrow ? c.browLayer:c.blushLayer;settings.tint=c.layered ? selected.tint ?? (settings.isBrow ? SIMD3(0.2,0.13,0.09):SIMD3(0.9,0.3,0.45)):c.shadeTint ?? (settings.isBrow ? SIMD3(0.2,0.13,0.09):SIMD3(0.9,0.3,0.45));settings.intensity=c.layered ? selected.intensity:c.previewIntensity}
        if !enabled {layer?.isHidden=true}
        let start=enabled && !segmenter.isAvailable && !segmentationStarting
        if start {segmentationStarting=true}
        lock.unlock()
        if start {
            segmentationTask=Task { [weak self] in
                guard let self else{return}
                do {
                    try Task.checkCancellation()
                    try await self.segmenter.start()
                    try Task.checkCancellation()
                    self.queue.async {if self.lastError?.hasPrefix("segmentation_unavailable:")==true {self.lastError=nil}}
                } catch is CancellationError {
                    // Navigation cancellation is expected, not an unavailable makeup error.
                } catch {
                    if !Task.isCancelled {self.queue.async {self.lastError="segmentation_unavailable: \(error)"}}
                }
                if !Task.isCancelled {self.lock.lock();self.segmentationStarting=false;self.lock.unlock()}
            }
        }
    }
    @MainActor func pause() {
        segmentationTask?.cancel();segmentationTask=nil
        lock.lock();settings.epoch=UUID();settings.enabled=false;latestMask=nil;segmentationStarting=false;lock.unlock()
        segmenter.stop()
        queue.async { [self] in visibility=BeautyBlushVisibility();frameTime=0;anchorID=nil;style=nil;lastError=nil;lastSegment=0 }
        onStatus?(nil)
    }

    func submit(_ frame:ARFrame,face:ARFaceAnchor?) {
        lock.lock();let s=settings
        guard s.enabled,!busy,s.viewport.width>0,s.viewport.height>0 else {lock.unlock();return}
        busy=true;lock.unlock()
        queue.async { [self] in
            defer {lock.lock();busy=false;lock.unlock()}
            lock.lock();let current=settings.epoch==s.epoch && settings.enabled;lock.unlock()
            guard current else{return}
            let rate=ProcessInfo.processInfo.thermalState.rawValue>=ProcessInfo.ThermalState.serious.rawValue ? config.thermal_fps:config.target_fps
            guard frame.timestamp>frameTime,frame.timestamp-frameTime>=1/Double(rate)-0.001 else{return}
            frameTime=frame.timestamp
            autoreleasepool {render(frame,face:face,settings:s)}
        }
    }
    // -Nimah: Pack measured, JSON-shaped brow centerlines and taper into a UV bake. No screen offsets.
    private static func browSegments(_ guide:EyebrowGuide,vertices:[SIMD3<Float>]) throws->[BrowSegment] {
        guard guide.curves.count==2 else {throw CocoaError(.coderInvalidValue)}
        var result:[BrowSegment]=[]
        for curve in guide.curves {
            guard curve.samples.count==41,curve.outline.count>=41 else {throw CocoaError(.coderInvalidValue)}
            var points:[SIMD4<Float>]=[]
            for i in 0...40 {
                guard let p=curve.samples[i]?.position(in:vertices),let upper=curve.outline[i]?.position(in:vertices) else {throw CocoaError(.coderInvalidValue)}
                let half=abs(upper.y-p.y)
                guard p.x.isFinite,p.y.isFinite,half.isFinite,half>0 else {throw CocoaError(.coderInvalidValue)}
                points.append(SIMD4(p.x,p.y,half,Float(i)/40))
            }
            for i in 0..<40 {result.append(BrowSegment(a:points[i],b:points[i+1]))}
        }
        return result
    }
    private static func affine(_ a:CGAffineTransform)->simd_float4x4 {
        simd_float4x4(columns:(SIMD4(Float(a.a),Float(a.b),0,0),SIMD4(Float(a.c),Float(a.d),0,0),SIMD4(0,0,1,0),SIMD4(Float(a.tx),Float(a.ty),0,1)))
    }
    private func texture(_ buffer:CVPixelBuffer,plane:Int,format:MTLPixelFormat)->(CVMetalTexture,MTLTexture)? {
        guard let cache=textureCache else{return nil};var cv:CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,format,CVPixelBufferGetWidthOfPlane(buffer,plane),CVPixelBufferGetHeightOfPlane(buffer,plane),plane,&cv)==kCVReturnSuccess,let cv,let t=CVMetalTextureGetTexture(cv) else{return nil}
        return(cv,t)
    }
    private func bind(_ geometry:ARFaceGeometry,face anchor:ARFaceAnchor,frame:ARFrame,style requested:BlushPlacementStyle,browStyle:EyebrowStyle,isBrow:Bool,command:MTLCommandBuffer)throws {
        if anchorID==anchor.identifier && style==requested && boundBrowStyle==browStyle && boundIsBrow==isBrow && atlas != nil{return}
        let current=Array(geometry.vertices),triangles=Array(geometry.triangleIndices)
        let eyes=[anchor.leftEyeTransform,anchor.rightEyeTransform].map {SIMD3($0.columns.3.x,$0.columns.3.y,$0.columns.3.z)}
        guard let region=LaunchMakeupFit.shared.fittedRegion(anchorID:anchor.identifier,vertices:current,triangles:triangles,timestamp:frame.timestamp,eyeCenters:eyes) else {throw CocoaError(.coderInvalidValue)}
        let guide=BlushPlacementGenerator.make(region:region,style:requested)
        let browGuide=isBrow ? EyebrowGuideGenerator.make(region:region,style:browStyle):nil
        guard isBrow ? browGuide?.curves.count==2:guide?.pigmentFields.count==2 else {throw CocoaError(.coderInvalidValue)}
        rest=region.restVertices;uvs=Array(geometry.textureCoordinates)
        guard rest.count==current.count,uvs.count==rest.count else {throw CocoaError(.coderInvalidValue)}
        filters=Array(repeating:OneEuroFilter(),count:rest.count*3)
        browStabilizers=Array(repeating:BeautyBrowStabilizer(),count:rest.count)
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
        if isBrow,let browGuide,let rule=MakeupRuleDatabase.brow(browStyle == .thin || browStyle == .feathered ? .natural:browStyle) {
            let segments=try Self.browSegments(browGuide,vertices:rest)
            guard let sb=segments.withUnsafeBytes({device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else {throw CocoaError(.featureUnsupported)}
            var controls=SIMD4(rule.number("max_alpha"),rule.number("head_fade_extent"),rule.number("edge_feather"),0)
            e.setRenderPipelineState(browAtlasPipeline);e.setVertexBuffer(vb,offset:0,index:0)
            e.setFragmentBuffer(sb,offset:0,index:0);e.setFragmentBytes(&controls,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
        } else if let guide {
            var b=Bake(left:field(guide.pigmentFields[0]),right:field(guide.pigmentFields[1]),options:SIMD4(guide.pigmentFields[0].smoothstepMix,guide.pigmentFields[1].smoothstepMix,config.paint_feather,0))
            if let bridge=guide.noseBridge {b.bridge=field(bridge)}
            b.paint=SIMD4(guide.pigmentFields[0].curvature,requested.isReferenceLook ? 1:0,0,0)
            b.mouth=Self.mouthExclusion(vertices:rest,triangles:triangles,eyes:eyes)
            e.setRenderPipelineState(atlasPipeline);e.setVertexBuffer(vb,offset:0,index:0);e.setFragmentBytes(&b,length:MemoryLayout<Bake>.stride,index:0);e.setFragmentTexture(brush,index:0)
        }
        e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        do {
            guard let mip=command.makeBlitCommandEncoder() else {throw CocoaError(.featureUnsupported)}
            mip.generateMipmaps(for:target);mip.endEncoding()
        }
        atlas=target;anchorID=anchor.identifier;style=requested;boundBrowStyle=browStyle;boundIsBrow=isBrow
    }
    // Native mesh boundary components, not invented landmark indices. Largest loop is the outer face.
    // A centered lower inner loop supplies an observed mouth-opening bound; expand modestly to protect lips.
    static func mouthExclusion(vertices:[SIMD3<Float>],triangles:[Int16],eyes:[SIMD3<Float>])->SIMD4<Float> {
        BlushPlacementGenerator.mouthExclusion(vertices:vertices,triangles:triangles,eyes:eyes)
    }

    private func render(_ frame:ARFrame,face anchor:ARFaceAnchor?,settings s:Settings) {
        guard inFlight.wait(timeout:.now()) == .success else{return}
        var committed=false
        defer {if !committed {inFlight.signal()}}
        guard CVPixelBufferGetPlaneCount(frame.capturedImage)>=2,let (cy,y)=texture(frame.capturedImage,plane:0,format:.r8Unorm),let (cc,cb)=texture(frame.capturedImage,plane:1,format:.rg8Unorm),
              let drawable=layer?.nextDrawable(),let command=commands.makeCommandBuffer() else{return}
        let frameSlot=slot%3;slot += 1
        let size=CGSize(width:drawable.texture.width,height:drawable.texture.height)
        if depthTexture?.width != drawable.texture.width || depthTexture?.height != drawable.texture.height {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:drawable.texture.width,height:drawable.texture.height,mipmapped:false);d.storageMode = .private;d.usage = .renderTarget;depthTexture=device.makeTexture(descriptor:d)
        }
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
            do {
                try bind(anchor.geometry,face:anchor,frame:frame,style:s.style,browStyle:s.browStyle,isBrow:s.isBrow,command:command)
                if lastError?.hasPrefix("fit_or_atlas_unavailable:")==true {lastError=nil}
            } catch {lastError="fit_or_atlas_unavailable: \(error)"}
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
        let compatible=anchorID==anchor?.identifier && style==s.style && boundBrowStyle==s.browStyle && boundIsBrow==s.isBrow && atlas != nil
        let visible=visibility.update(timestamp:frame.timestamp,target:tracked && compatible ? maskWeight:0,tau:config.visibility_tau_seconds)
        let opacity=maskWeight>0 ? BeautyMaskContinuity.opacity(filtered:visible,age:age,freshAge:config.mask_max_age_seconds,fadeSeconds:config.mask_fade_seconds):0
        let matrixAttachment=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferYCbCrMatrixKey,nil) as? String
        let transfer=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferTransferFunctionKey,nil) as? String
        let full=CVPixelBufferGetPixelFormatType(frame.capturedImage)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var u=Uniforms(mvp:projection*view*(anchor?.transform ?? matrix_identity_float4x4),rawFromClip:raw,maskFromRaw:maskTransform,
            shade:SIMD4(BeautyBlushConfiguration.linear(s.tint.x),BeautyBlushConfiguration.linear(s.tint.y),BeautyBlushConfiguration.linear(s.tint.z),s.intensity),
            controls:SIMD4(config.coverage,config.absorption,config.saturation,config.pigment_mix),tracking:SIMD4(Float(opacity),s.guide ? 1:0,1/Float(size.width),1/Float(size.height)),
            camera:SIMD4(matrixAttachment==(kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 1:0,full ? 1:0,transfer==(kCVImageBufferTransferFunction_ITU_R_709_2 as String) ? 1:0,s.isBrow ? 1:0),
            stretch:SIMD4(config.stretch_fade[0],config.stretch_fade[1],config.stretch_fade[2],config.stretch_fade[3]))
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        if let anchor,anchorID==anchor.identifier,style==s.style,boundBrowStyle==s.browStyle,boundIsBrow==s.isBrow,let atlas,let ib=indices,let obstruction=frameMask,!vertices.isEmpty {
            let buffer=vertices[frameSlot]
            let pointer=buffer.contents().bindMemory(to:Vertex.self,capacity:rest.count)
            let points=anchor.geometry.vertices
            let smoothing=OneEuroConfig(minCutoff:config.min_cutoff_hz,beta:config.velocity_beta,dCutoff:1,deadband:0)
            for i in rest.indices {
                var p=points[i]
                if s.isBrow {p=browStabilizers[i].update(p,timestamp:frame.timestamp)}
                else {
                    for axis in 0..<3 {p[axis]=Float(filters[i*3+axis].filter(Double(p[axis]),t:frame.timestamp,config:smoothing))}
                    p=BeautyBlushConfiguration.limitResidual(filtered:p,current:points[i])
                }
                pointer[i]=Vertex(position:SIMD4(p,1),rest:SIMD4(rest[i],1),uv:SIMD4(uvs[i].x,uvs[i].y,0,0))
            }
            e.setCullMode(.none) // Native mesh depth prepass resolves visible surfaces without mirrored-winding assumptions.
            e.setVertexBuffer(buffer,offset:0,index:0);e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
            e.setRenderPipelineState(depth);e.setDepthStencilState(depthWrite)
            e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0)
            e.setRenderPipelineState(face);e.setDepthStencilState(depthRead);e.setFragmentTexture(atlas,index:2);e.setFragmentTexture(obstruction,index:3)
            e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0)
        }
        e.endEncoding()
        if let anchor {
            let world=SIMD3(anchor.transform.columns.3.x,anchor.transform.columns.3.y,anchor.transform.columns.3.z)
            let rawSize=CGSize(width:CVPixelBufferGetWidth(frame.capturedImage),height:CVPixelBufferGetHeight(frame.capturedImage))
            let rp=frame.camera.projectPoint(world,orientation:.landscapeRight,viewportSize:rawSize)
            let normalized=CGPoint(x:rp.x/rawSize.width,y:rp.y/rawSize.height)
            let expected=normalized.applying(frame.displayTransform(for:s.orientation,viewportSize:s.viewport))
            let clip=projection*view*SIMD4(world,1)
            let actual=CGPoint(x:CGFloat(clip.x/clip.w)*0.5+0.5,y:0.5-CGFloat(clip.y/clip.w)*0.5)
            projectionErrorPixels=hypot((expected.x-actual.x)*s.viewport.width,(expected.y-actual.y)*s.viewport.height)
        }
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { [weak self] _ in self?.queue.async { [weak self] in self?.presentedFrames += 1 } }
        #endif
        command.present(drawable)
        let ts=frame.timestamp
        if tracked && opacity>0.9 {pigmentFrames += 1;lastError=nil}
        let retained=FrameLifetime(y:cy,cb:cc,frame:frame)
        let completionGate=inFlight
        command.addCompletedHandler { [weak self] cb in
            completionGate.signal()
            withExtendedLifetime(retained) {}
            Task { @MainActor [weak self] in
                guard let self else{return};self.lock.lock();let show=self.settings.enabled && self.settings.epoch==s.epoch;self.lock.unlock()
                if show {self.layer?.isHidden=false}
            }
            self?.queue.async { [weak self] in self?.report(cb,frameTimestamp:ts,maskFresh:fresh,visibility:opacity,isBrow:s.isBrow) }
        }
        committed=true;command.commit()
    }
    private func report(_ cb:MTLCommandBuffer,frameTimestamp:Double,maskFresh:Bool,visibility:Double,isBrow:Bool) {
        let now=CACurrentMediaTime();if reportStart==0 {reportStart=now}
        reportFrames += 1;gpuTimes.append(max(0,cb.gpuEndTime-cb.gpuStartTime)*1000);ages.append(max(0,now-frameTimestamp)*1000)
        guard now-reportStart>=2 else{return}
        let sorted=ages.sorted(),p95=sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]
        let report:[String:Any]=["engine":"arkit_metal_uv","category":isBrow ? "eyebrow":"blush","fps_completed":Double(reportFrames)/(now-reportStart),"fps_presented":Double(presentedFrames)/(now-reportStart),"pigment_frames":pigmentFrames,"projection_error_pixels":projectionErrorPixels,"gpu_ms_mean":gpuTimes.reduce(0,+)/Double(gpuTimes.count),"frame_age_ms_p95":p95,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"mask_fresh":maskFresh,"mask_age_ms":maskAgeMilliseconds,"segmenter_available":segmenter.isAvailable,"visibility":visibility,"error":lastError ?? "none","shader_error":cb.error?.localizedDescription ?? "none"]
        onStatus?(lastError != nil || cb.error != nil ? String(localized:"Makeup is temporarily unavailable") : (!maskFresh && visibility<0.1 ? String(localized:"Preparing makeup visibility"):nil))
        if let data=try? JSONSerialization.data(withJSONObject:report) {UserDefaults.standard.set(data,forKey:isBrow ? "beautyBrow.metrics":"beautyBlush.metrics")}
        reportStart=now;reportFrames=0;presentedFrames=0;pigmentFrames=0;gpuTimes.removeAll(keepingCapacity:true);ages.removeAll(keepingCapacity:true)
    }
    #if DEBUG
    @MainActor static func cancelledPreparationFixture() async throws->String? {
        let engine=try BeautyBlushEngine()
        var c=EyebrowConfiguration();c.region = .blush;c.showMakeupPreview=true
        engine.configure(c);engine.pause()
        try await Task.sleep(for:.milliseconds(50))
        return await withCheckedContinuation {continuation in
            engine.queue.async {continuation.resume(returning:engine.lastError)}
        }
    }
    static func browSpanFixture(region:EyebrowRegion,style:EyebrowStyle)throws->[(Float,Float)] {
        guard let guide=EyebrowGuideGenerator.make(region:region,style:style) else {throw CocoaError(.coderInvalidValue)}
        let segments=try browSegments(guide,vertices:region.restVertices)
        return stride(from:0,to:80,by:40).map { (segments[$0].a.x,segments[$0+39].b.x) }
    }
    static func renderAtlasFixture(brow:Bool=false,placement:BlushPlacementGuide?=nil)throws->[Float] {
        let engine=try BeautyBlushEngine(),d=engine.device,n=(brow || placement != nil) ? 256:64
        let extent:Float=placement == nil ? 1:0.08
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:n,height:n,mipmapped:false);desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
        guard let target=d.makeTexture(descriptor:desc),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let positions:[SIMD3<Float>]=[.init(-1,-1,0),.init(1,-1,0),.init(1,1,0),.init(-1,1,0)]
        let points=positions.map {Vertex(position:SIMD4($0*extent,1),rest:SIMD4($0*extent,1),uv:SIMD4(($0.x+1)/2,(1-$0.y)/2,0,0))}
        let triangles:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=triangles.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        var b=Bake(left:.init(ellipse:SIMD4(0.4,-0.1,0.3,0.4),shape:SIMD4(1,0.1,0.5,1.15),limits:SIMD4(0.1,0.95,0.4,0.04)),right:.init(ellipse:SIMD4(-0.4,-0.1,0.3,0.4),shape:SIMD4(-1,0.1,0.5,1.15),limits:SIMD4(0.1,0.95,0.4,0.04)),options:SIMD4(1,1,0.9,0))
        if let placement {
            func field(_ f:BlushPigmentField)->Field {.init(ellipse:SIMD4(f.center.x,f.center.y,f.radius.x,f.radius.y),shape:SIMD4(f.side,f.angle,f.opacity,f.power),limits:SIMD4(f.nasalLimit,f.outerLimit,f.eyeLimit,f.edgeFeather))}
            b.left=field(placement.pigmentFields[0]);b.right=field(placement.pigmentFields[1])
            b.paint=SIMD4(placement.pigmentFields[0].curvature,placement.style.isReferenceLook ? 1:0,0,0)
            if let bridge=placement.noseBridge {b.bridge=field(bridge)}
        }
        if brow {
            var segments:[BrowSegment]=[]
            for side:Float in [-1,1] {
                func point(_ i:Int)->SIMD4<Float> {
                    let t=Float(i)/40
                    return SIMD4(side*(0.18+0.6*t),0.25+0.12*sin(t*Float.pi),0.10*(1-0.85*t),t)
                }
                for i in 0..<40 {segments.append(BrowSegment(a:point(i),b:point(i+1)))}
            }
            guard let sb=segments.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else {throw CocoaError(.featureUnsupported)}
            var c=SIMD4<Float>(0.55,0.18,0.55,0)
            e.setRenderPipelineState(engine.browAtlasPipeline);e.setVertexBuffer(vb,offset:0,index:0)
            e.setFragmentBuffer(sb,offset:0,index:0);e.setFragmentBytes(&c,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
        } else {
        e.setRenderPipelineState(engine.atlasPipeline);e.setVertexBuffer(vb,offset:0,index:0);e.setFragmentBytes(&b,length:MemoryLayout<Bake>.stride,index:0);e.setFragmentTexture(engine.brush,index:0)
        }
        e.drawIndexedPrimitives(type:.triangle,indexCount:triangles.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding();command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var raw=Array(repeating:UInt16(0),count:n*n*4)
        raw.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*8,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return raw.map {Float(Float16(bitPattern:$0))}
    }
    // Real Metal pixel fixture. Uses the production shader pipelines, with synthetic camera/UV data.
    static func renderPixelFixture(obstructed:Bool,intensity:Float,brow:Bool=false)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=32
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,Array(repeating:128,count:n*n),n)
        let cb=try texture(.rg8Unorm,Array(repeating:128,count:n*n*2),n*2)
        let mask=try texture(.r8Unorm,Array(repeating:obstructed ? 255:0,count:n*n),n)
        let atlas=try texture(.rgba8Unorm,Array(repeating:255,count:n*n*4),n*4)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let positions:[SIMD3<Float>]=[.init(-0.8,-0.8,0.2),.init(0.8,-0.8,0.2),.init(0.8,0.8,0.2),.init(-0.8,0.8,0.2)]
        let points=positions.map {Vertex(position:SIMD4($0,1),rest:SIMD4($0,1),uv:SIMD4(($0.x+1)/2,($0.y+1)/2,0,0))}
        let tris:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=tris.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.8,0.05,0.15,intensity),controls:SIMD4(0.9,0.65,0.85,0.68),tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,brow ? 1:0),stretch:SIMD4(0.45,0.7,1.45,1.85))
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        e.setRenderPipelineState(engine.background);e.setDepthStencilState(engine.noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        e.setCullMode(.none);e.setVertexBuffer(vb,offset:0,index:0);e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
        e.setRenderPipelineState(engine.depth);e.setDepthStencilState(engine.depthWrite)
        e.drawIndexedPrimitives(type:.triangle,indexCount:tris.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0)
        e.setRenderPipelineState(engine.face);e.setDepthStencilState(engine.depthRead);e.setFragmentTexture(atlas,index:2);e.setFragmentTexture(mask,index:3)
        e.drawIndexedPrimitives(type:.triangle,indexCount:tris.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var data=Data(count:n*n*4);data.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*4,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return data
    }
    #endif

}
