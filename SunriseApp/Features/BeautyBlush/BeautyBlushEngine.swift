// -Nimah: Native ARKit face UV / Metal renderer, one shared camera. All expensive work on a serial render queue.
// Blush follows the ARKit face mesh. Eyebrow follows MediaPipe landmarks on the same camera frames (no ARKit mesh,
// no Vision fit): the brow texture is laid over the observed brow and drawn on the very frame it was found in.
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
        var debug=SIMD4<Float>.zero
    }
    private struct BrowVertex {var position:SIMD4<Float>;var brow:SIMD4<Float>;var probes:SIMD4<Float>;var skin:SIMD4<Float>;var conceal:SIMD4<Float>}
    private struct BrowStrip {var vertices:[BrowVertex];var unwrap:[BrowUnwrapVertex];var cropToRaw:simd_float4x4?}
    private struct MarkVertex {var position:SIMD4<Float>;var color:SIMD4<Float>}
    private struct HairUniforms {var clipFromModel:simd_float4x4;var view:SIMD4<Float>;var look:SIMD4<Float>;var probe:SIMD4<Float>}
    /// One brow's hair mesh on the face: model to face-local, its scale and the raw-image offset for the hand check.
    private struct HairDraw {var matrix:simd_float4x4;var scale:Float;var probe:SIMD2<Float>}
    private struct BrowFrame:@unchecked Sendable {let frame:ARFrame;let epoch:UUID;let face:BrowFaceFrame?}
    private struct Field {var ellipse:SIMD4<Float>;var shape:SIMD4<Float>;var limits:SIMD4<Float>}
    private struct Bake {var left:Field;var right:Field;var bridge=Field(ellipse:.zero,shape:.zero,limits:.zero);var paint=SIMD4<Float>.zero;var options=SIMD4<Float>.zero;var mouth=SIMD4<Float>.zero}
    private struct Settings {
        var comparisonSplit=false;var enabled=false;var tint=SIMD3<Float>(0.9,0.3,0.45);var intensity:Float=0.72;var style=BlushPlacementStyle.cheekbone;var browStyle=EyebrowStyle.softNatural;var browOverlay:BrowOverlay?;var isBrow=false;var guide=false;var mapping=false;var tracking=false;var hideNatural=false;var viewport=CGSize.zero;var orientation=UIInterfaceOrientation.portrait;var epoch=UUID()}
    /// Developer brow view (`BrowDebugView` raw value), read each frame so the developer picker applies live.
    static let browDebugKey="beautyBrow.debugView"
    /// How long the brow keeps using the last face-skin mask. The segmenter often lags past `mask_max_age_seconds`
    /// on device, and dropping the brow for those frames made it blink; a hand still hides it within this time.
    private static let browMaskGraceSeconds:Double=0.3
    private let inFlight=DispatchSemaphore(value:3)
    private let lock=NSLock(),queue=DispatchQueue(label:"dandan.blush.metal",qos:.userInteractive)
    private let device:MTLDevice,commands:MTLCommandQueue
    private let config:BeautyBlushConfiguration
    private let background,face,depth,atlasPipeline,browTexturePipeline,browStripPipeline,browMarkPipeline,browHairPipeline:MTLRenderPipelineState
    private let depthWrite,depthRead,noDepth:MTLDepthStencilState
    private let brush:MTLTexture
    private var textureCache:CVMetalTextureCache?
    private var layer:CAMetalLayer?
    private var settings=Settings(),busy=false
    private var vertices:[MTLBuffer]=[],indices:MTLBuffer?,bakeVertices:MTLBuffer?,indexCount=0,slot=0
    private var rest:[SIMD3<Float>]=[],uvs:[SIMD2<Float>]=[],filters:[OneEuroFilter]=[]
    private var atlas:MTLTexture?,depthTexture:MTLTexture?
    private var maskTextures:[MTLTexture?]=[nil,nil,nil],maskVersions:[Double]=[-1,-1,-1],cachedMaskBytes:[UInt8]=[]
    // Repeated failed blush fits are throttled so a style tap cannot make the render queue
    // spend every frame rebuilding the same atlas.
    private var attemptedBlushStyle:BlushPlacementStyle?
    private var lastBindAttempt:Double = -.infinity
    // MediaPipe brow: one frame in flight, kept until its landmarks come back, then drawn with them.
    private let browTracker=MediaPipeBrowTracker()
    private var browTrackerTask:Task<Void,Never>?
    private var browTrackerStarting=false
    private var browToken:UInt64=0,browFrames:[UInt64:BrowFrame]=[:]
    /// The brow (camera picture and brow together) is redrawn at most this often, so it is not redrawn on every 60 Hz camera frame.
    static let browMaxFramesPerSecond:Double=30
    private var lastBrowSubmit:Double = -.infinity
    /// Whether a camera frame at `timestamp` is due, given the last one handed to MediaPipe. A little under the full interval is
    /// enough, so frames from a 60 Hz camera alternate instead of occasionally slipping to every third.
    static func browFrameDue(timestamp:Double,last:Double,maxFPS:Double=browMaxFramesPerSecond)->Bool {timestamp-last>=0.9/maxFPS}
    private var browSmoother=BrowObservationSmoother()
    /// Steadies the brow in ARKit's face space when ARKit tracks the face in the same frame; the image-space smoother is the fallback.
    private var browStabilizer=BrowFaceStabilizer()
    private var browStabilized=false
    /// The 3D hair brow: its mesh on the GPU, and the ARKit face mesh drawn as depth only so far hairs hide behind the face.
    private var hairBuffer:MTLBuffer?,hairVertexCount=0
    private var faceMeshVertices:[MTLBuffer]=[],faceMeshIndices:MTLBuffer?,faceMeshIndexCount=0
    private var browLight:Float=1
    private var browFaceTriangles:[UInt16]=[]
    private var browTexture:MTLTexture?,browTextureKey:String?
    private var browVertices:[MTLBuffer]=[],browIndices:MTLBuffer?
    /// Stands in for the face-skin mask until one arrives: nothing occluded.
    private var emptyMask:MTLTexture?
    /// Hides the natural brow (brow-space push-pull fill, optional MI-GAN); nil if its shaders are unavailable.
    private var eraser:BrowEraser?
    /// Bound in place of the eraser's fill when there is none, so the brow strip always has a texture array.
    private var emptyFill:MTLTexture?
    private var browStatus:String?? = .none
    private var style:BlushPlacementStyle?,anchorID:UUID?,frameTime:Double=0
    private var visibility=BeautyBlushVisibility(),lastSegment:Double=0
    private let segmenter=HandOcclusionSegmenter(faceSkinOnly:true)
    private var segmentationTask:Task<Void,Never>?
    private var segmentationStarting=false,latestMask:OcclusionMask?
    private var lastMaskTime:Double = -1
    private var reportStart=0.0,reportFrames=0,gpuTimes:[Double]=[],ages:[Double]=[]
    var onStatus:(@Sendable (String?)->Void)?
    /// The tracking view's per-frame readout (nil when the brow is not in tracking view).
    var onTracking:(@Sendable (BrowTrackingSnapshot?)->Void)?
    private var browResultTimes:[Double]=[]
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
        browTexturePipeline=try pipeline("browTextureVertex","browTextureFragment",.rgba16Float)
        browStripPipeline=try pipeline("browStripVertex","browStripFragment")
        let marks=MTLRenderPipelineDescriptor();marks.vertexFunction=lib.makeFunction(name:"browMarkVertex");marks.fragmentFunction=lib.makeFunction(name:"browMarkFragment")
        marks.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb;marks.depthAttachmentPixelFormat = .depth32Float
        marks.colorAttachments[0].isBlendingEnabled=true
        marks.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha;marks.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        marks.colorAttachments[0].sourceAlphaBlendFactor = .one;marks.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        browMarkPipeline=try d.makeRenderPipelineState(descriptor:marks)
        let hair=MTLRenderPipelineDescriptor();hair.vertexFunction=lib.makeFunction(name:"browRibbonVertex");hair.fragmentFunction=lib.makeFunction(name:"browRibbonFragment")
        hair.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb;hair.depthAttachmentPixelFormat = .depth32Float
        hair.colorAttachments[0].isBlendingEnabled=true
        hair.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha;hair.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        hair.colorAttachments[0].sourceAlphaBlendFactor = .one;hair.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        browHairPipeline=try d.makeRenderPipelineState(descriptor:hair)
        func state(_ compare:MTLCompareFunction,_ write:Bool)->MTLDepthStencilState? {let p=MTLDepthStencilDescriptor();p.depthCompareFunction=compare;p.isDepthWriteEnabled=write;return d.makeDepthStencilState(descriptor:p)}
        guard let dw=state(.less,true),let dr=state(.lessEqual,false),let nd=state(.always,false),
              let url=Bundle.main.url(forResource:config.mask_asset,withExtension:nil) else {throw CocoaError(.featureUnsupported)}
        depthWrite=dw;depthRead=dr;noDepth=nd
        brush=try MTKTextureLoader(device:d).newTexture(URL:url,options:[.SRGB:false,.textureUsage:MTLTextureUsage.shaderRead.rawValue])
        CVMetalTextureCacheCreate(nil,nil,d,nil,&textureCache)
        segmenter.onMask={ [weak self] mask in guard let self,let mask else{return};self.lock.lock();self.latestMask=mask;self.lock.unlock() }
        let empty=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r8Unorm,width:1,height:1,mipmapped:false);empty.usage = .shaderRead;empty.storageMode = .shared
        emptyMask=d.makeTexture(descriptor:empty)
        var zero:UInt8=0;emptyMask?.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:&zero,bytesPerRow:1)
        eraser=try? BrowEraser(device:d,library:lib)
        let fill=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:1,height:1,mipmapped:false)
        fill.textureType = .type2DArray;fill.arrayLength=2;fill.usage = .shaderRead;fill.storageMode = .shared
        emptyFill=d.makeTexture(descriptor:fill)
        let grid=Self.browGridIndices()
        browIndices=grid.withUnsafeBytes {d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
        browVertices=(0..<3).compactMap {_ in d.makeBuffer(length:Self.browVertexCount*2*MemoryLayout<BrowVertex>.stride,options:.storageModeShared)}
        browTracker.onResult={ [weak self] result in self?.queue.async { [weak self] in self?.renderBrow(result) } }
    }
    func setViewport(_ size:CGSize,orientation:UIInterfaceOrientation) {lock.lock();settings.viewport=size;settings.orientation=orientation;lock.unlock()}
    @MainActor func configure(_ c:EyebrowConfiguration?) {
        let enabled=c.map { $0.previewAfter && ($0.layered ? ($0.browLayer.on || $0.blushLayer.on):(($0.needsBlush || $0.needsBrow) && $0.showMakeupPreview)) } ?? false
        lock.lock()
        let nextBrow=c.map {$0.needsBrow && !$0.needsBlush} ?? false
        let previousBlushStyle=settings.style
        let previousIsBrow=settings.isBrow,previousEnabled=settings.enabled
        if settings.isBrow != nextBrow || settings.enabled != enabled {
            settings.epoch=UUID();layer?.isHidden=true
        }
        // A category/style tap must be eligible on the very next frame. The
        // retry throttle is only for repeated failures of the same request;
        // carrying its timestamp across a new request made quick switches
        // appear to be ignored for up to half a second. A new brow style is
        // baked on the next drawn frame, so it needs no epoch change.
        let styleChanged = c.map { previousBlushStyle != $0.blushStyle } ?? false
        if styleChanged || previousIsBrow != nextBrow {
            // Invalidate an in-flight command from the previous style without
            // hiding its already committed atlas. Its completion handler will
            // then be unable to publish stale state over the new selection.
            if styleChanged && settings.enabled && enabled && !nextBrow { settings.epoch=UUID() }
            attemptedBlushStyle=nil
            lastBindAttempt = -.infinity
        }
        settings.enabled=enabled
        if let c {settings.comparisonSplit=c.comparisonSplit;settings.isBrow=c.needsBrow && !c.needsBlush;settings.browStyle=c.style;settings.browOverlay=c.browOverlay;settings.style=c.blushStyle;settings.guide=c.showGuide;settings.mapping=c.showMappingFormula;settings.tracking=c.browTrackingOverlay;settings.hideNatural=c.hideNaturalBrow;let selected=settings.isBrow ? c.browLayer:c.blushLayer;settings.tint=c.layered ? selected.tint ?? (settings.isBrow ? SIMD3(0.2,0.13,0.09):SIMD3(0.9,0.3,0.45)):c.shadeTint ?? (settings.isBrow ? SIMD3(0.2,0.13,0.09):SIMD3(0.9,0.3,0.45));settings.intensity=c.layered ? selected.intensity:c.previewIntensity}
        if !enabled {layer?.isHidden=true}
        if enabled && nextBrow,let overlay=settings.browOverlay {BrowSpriteStore.shared.prepare(overlay);if overlay.is3D {BrowHairStore.shared.prepare()}}
        let start=enabled && !segmenter.isAvailable && !segmentationStarting
        if start {segmentationStarting=true}
        let startTracker=enabled && nextBrow && !browTracker.isAvailable && !browTrackerStarting
        if startTracker {browTrackerStarting=true}
        lock.unlock()
        if startTracker {
            browTrackerTask=Task { [weak self] in
                guard let self else{return}
                do {
                    try Task.checkCancellation()
                    try await self.browTracker.start()
                    self.queue.async {if self.lastError?.hasPrefix("brow_tracker_unavailable:")==true {self.lastError=nil}}
                } catch is CancellationError {
                    // Navigation cancellation is expected, not an unavailable makeup error.
                } catch {
                    if !Task.isCancelled {self.queue.async {self.lastError="brow_tracker_unavailable: \(error)";self.publishBrowStatus()}}
                }
                if !Task.isCancelled {self.lock.lock();self.browTrackerStarting=false;self.lock.unlock()}
            }
        }
        // The status pill belongs to the selected category; a brow waits for a face before anything is drawn.
        if previousIsBrow != nextBrow || previousEnabled != enabled {
            if enabled && nextBrow {queue.async { [self] in browFaceVisible=false;browStatus = .none;publishBrowStatus()}}
            else {onStatus?(nil)}
            onTracking?(nil)
        }
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
        browTrackerTask?.cancel();browTrackerTask=nil
        lock.lock();settings.epoch=UUID();settings.enabled=false;latestMask=nil;segmentationStarting=false;browTrackerStarting=false;browFrames=[:];lock.unlock()
        segmenter.stop();browTracker.stop()
        queue.async { [self] in
            visibility=BeautyBlushVisibility();frameTime=0;anchorID=nil;style=nil;lastError=nil;lastSegment=0
            browSmoother.reset();browStabilizer.reset();browStatus = .none
            lock.lock()
            attemptedBlushStyle=nil;lastBindAttempt = -.infinity;atlas=nil
            lock.unlock()
        }
        onStatus?(nil);onTracking?(nil)
    }

    func submit(_ frame:ARFrame,face:ARFaceAnchor?) {
        lock.lock();let s=settings
        guard s.enabled,s.viewport.width>0,s.viewport.height>0 else {lock.unlock();return}
        if s.isBrow {lock.unlock();submitBrow(frame,settings:s);return}
        guard !busy else {lock.unlock();return}
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
    private static func affine(_ a:CGAffineTransform)->simd_float4x4 {
        simd_float4x4(columns:(SIMD4(Float(a.a),Float(a.b),0,0),SIMD4(Float(a.c),Float(a.d),0,0),SIMD4(0,0,1,0),SIMD4(Float(a.tx),Float(a.ty),0,1)))
    }
    private func texture(_ buffer:CVPixelBuffer,plane:Int,format:MTLPixelFormat)->(CVMetalTexture,MTLTexture)? {
        guard let cache=textureCache else{return nil};var cv:CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,format,CVPixelBufferGetWidthOfPlane(buffer,plane),CVPixelBufferGetHeightOfPlane(buffer,plane),plane,&cv)==kCVReturnSuccess,let cv,let t=CVMetalTextureGetTexture(cv) else{return nil}
        return(cv,t)
    }
    private func bind(_ geometry:ARFaceGeometry,face anchor:ARFaceAnchor,frame:ARFrame,style requested:BlushPlacementStyle,command:MTLCommandBuffer)throws {
        if anchorID==anchor.identifier && style==requested && atlas != nil{return}
        let current=Array(geometry.vertices),triangles=Array(geometry.triangleIndices)
        let eyes=[anchor.leftEyeTransform,anchor.rightEyeTransform].map {SIMD3($0.columns.3.x,$0.columns.3.y,$0.columns.3.z)}
        guard let region=LaunchMakeupFit.shared.fittedRegion(anchorID:anchor.identifier,vertices:current,triangles:triangles,timestamp:frame.timestamp,eyeCenters:eyes) else {throw CocoaError(.coderInvalidValue)}
        guard let guide=BlushPlacementGenerator.make(region:region,style:requested),guide.pigmentFields.count==2 else {throw CocoaError(.coderInvalidValue)}
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
        b.paint=SIMD4(guide.pigmentFields[0].curvature,requested.isReferenceLook ? 1:0,0,0)
        b.mouth=Self.mouthExclusion(vertices:rest,triangles:triangles,eyes:eyes)
        e.setRenderPipelineState(atlasPipeline);e.setVertexBuffer(vb,offset:0,index:0);e.setFragmentBytes(&b,length:MemoryLayout<Bake>.stride,index:0);e.setFragmentTexture(brush,index:0)
        e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        if let mip=command.makeBlitCommandEncoder() {mip.generateMipmaps(for:target);mip.endEncoding()}
        atlas=target;anchorID=anchor.identifier;style=requested
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
        ensureDepth(for:drawable)
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
            let styleNeedsBind = anchorID != anchor.identifier || style != s.style
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
        let visible=visibility.update(timestamp:frame.timestamp,target:tracked && compatible ? maskWeight:0,tau:config.visibility_tau_seconds)
        let opacity=maskWeight>0 ? BeautyMaskContinuity.opacity(filtered:visible,age:age,freshAge:config.mask_max_age_seconds,fadeSeconds:config.mask_fade_seconds):0
        let matrixAttachment=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferYCbCrMatrixKey,nil) as? String
        let transfer=CVBufferCopyAttachment(frame.capturedImage,kCVImageBufferTransferFunctionKey,nil) as? String
        let full=CVPixelBufferGetPixelFormatType(frame.capturedImage)==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        var u=Uniforms(mvp:projection*view*(anchor?.transform ?? matrix_identity_float4x4),rawFromClip:raw,maskFromRaw:maskTransform,
            shade:SIMD4(BeautyBlushConfiguration.linear(s.tint.x),BeautyBlushConfiguration.linear(s.tint.y),BeautyBlushConfiguration.linear(s.tint.z),s.intensity),
            controls:SIMD4(config.coverage,config.absorption,config.saturation,config.pigment_mix),tracking:SIMD4(Float(opacity),s.guide ? 1:0,1/Float(size.width),1/Float(size.height)),
            camera:SIMD4(matrixAttachment==(kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 1:0,full ? 1:0,transfer==(kCVImageBufferTransferFunction_ITU_R_709_2 as String) ? 1:0,0),
            stretch:SIMD4(config.stretch_fade[0],config.stretch_fade[1],config.stretch_fade[2],config.stretch_fade[3]))
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        if s.comparisonSplit {e.setScissorRect(MTLScissorRect(x:0,y:0,width:max(1,drawable.texture.width/2),height:drawable.texture.height))}
        if let anchor,anchorID==anchor.identifier,style==s.style,let atlas,let ib=indices,let obstruction=frameMask,!vertices.isEmpty {
            let buffer=vertices[frameSlot]
            let pointer=buffer.contents().bindMemory(to:Vertex.self,capacity:rest.count)
            let points=anchor.geometry.vertices
            let smoothing=OneEuroConfig(minCutoff:config.min_cutoff_hz,beta:config.velocity_beta,dCutoff:1,deadband:0)
            for i in rest.indices {
                var p=points[i]
                for axis in 0..<3 {p[axis]=Float(filters[i*3+axis].filter(Double(p[axis]),t:frame.timestamp,config:smoothing))}
                p=BeautyBlushConfiguration.limitResidual(filtered:p,current:points[i])
                pointer[i]=Vertex(position:SIMD4(p,1),rest:SIMD4(rest[i],1),uv:SIMD4(uvs[i].x,uvs[i].y,0,0))
            }
            e.setCullMode(.none) // Native mesh depth prepass resolves visible surfaces without mirrored-winding assumptions.
            e.setVertexBuffer(buffer,offset:0,index:0);e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
            e.setRenderPipelineState(depth);e.setDepthStencilState(depthWrite)
            e.drawIndexedPrimitives(type:.triangle,indexCount:indexCount,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0)
            e.setRenderPipelineState(face);e.setDepthStencilState(depthRead);e.setFragmentTexture(atlas,index:2);e.setFragmentTexture(obstruction,index:3);
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
            self?.queue.async { [weak self] in self?.report(cb,frameTimestamp:ts,maskFresh:fresh,visibility:opacity,isBrow:false) }
        }
        committed=true;command.commit()
    }
    /// Uploads the latest face-skin mask into this frame slot's texture. Returns the texture, its camera-to-mask
    /// transform and whether the mask is fresh enough to draw pigment over.
    private func uploadMask(slot frameSlot:Int,capturedImage:CVPixelBuffer,maxAge:Double)->(MTLTexture?,simd_float4x4,Bool) {
        lock.lock();let mask=latestMask;lock.unlock()
        let fresh=mask.map {CACurrentMediaTime()-$0.time<=maxAge && Int($0.rawSize.width)==CVPixelBufferGetWidth(capturedImage) && Int($0.rawSize.height)==CVPixelBufferGetHeight(capturedImage)} ?? false
        var maskTransform=matrix_identity_float4x4
        var frameMask:MTLTexture?
        if let mask,fresh {
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
            maskTransform=Self.affine(rawPixels.concatenating(mask.toImage.inverted()).concatenating(normalize))
        }
        maskAgeMilliseconds=mask.map {max(0,CACurrentMediaTime()-$0.time)*1000} ?? -1
        return (frameMask,maskTransform,fresh)
    }
    private func ensureDepth(for drawable:CAMetalDrawable) {
        if depthTexture?.width != drawable.texture.width || depthTexture?.height != drawable.texture.height {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:drawable.texture.width,height:drawable.texture.height,mipmapped:false);d.storageMode = .private;d.usage = .renderTarget;depthTexture=device.makeTexture(descriptor:d)
        }
    }

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
    private static let browColumns=48,browRows=14
    static var browVertexCount:Int {(browColumns+1)*(browRows+1)}
    private static var browIndexCount:Int {browColumns*browRows*12}
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
    /// The 3D brow mesh once it has loaded (loading starts here); nil until then, and the brow's picture is drawn meanwhile.
    private func hairMeshIfReady()->BrowHairMesh? {
        guard let mesh=BrowHairStore.shared.mesh else {BrowHairStore.shared.prepare();return nil}
        installHairMesh(mesh)
        return hairBuffer==nil ? nil:mesh
    }
    private func installHairMesh(_ mesh:BrowHairMesh) {
        guard hairBuffer==nil else {return}
        let vertices=mesh.vertices
        hairBuffer=vertices.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
        hairVertexCount=vertices.count
    }
    /// Where the hair mesh goes on each tracked brow: head and tail, the mesh normal between them and the way to the forehead,
    /// all lifted onto ARKit's face mesh from the brow's (steadied) landmarks.
    private static func hairPlacements(_ o:BrowObservation,face:BrowFaceFrame,mesh:BrowHairMesh)->[HairDraw] {
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        var out:[HairDraw]=[]
        for side in [EyeSide.subjectRight,.subjectLeft] {
            guard let contour=o.brows[side],let g=BrowGeometry(contour:contour) else {continue}
            let headPixel=g.centerline(0).point,tailPixel=g.centerline(1).point,midPixel=g.point(u:0.5,w:0)
            guard let head=face.faceLocal(at:headPixel),let tail=face.faceLocal(at:tailPixel),let mid=face.faceLocal(at:midPixel),
                  let top=face.faceLocal(at:g.point(u:0.5,w:0.5)),
                  let frame=BrowHairPlacement.frame(mesh:mesh,head:head,tail:tail,normal:face.normal(near:mid),forehead:top-mid) else {continue}
            out.append(HairDraw(matrix:frame.matrix,scale:frame.scale,probe:(g.point(u:0.5,w:0.25)-midPixel)/image))
        }
        return out
    }
    /// ARKit's face mesh for this frame, in a ring of GPU buffers (for the depth pass).
    private func uploadFaceMesh(_ face:BrowFaceFrame,slot:Int)->Bool {
        let count=face.vertices.count,stride=MemoryLayout<Vertex>.stride
        guard count>0,slot<3 else {return false}
        if faceMeshVertices.count != 3 || faceMeshVertices[0].length != count*stride {
            faceMeshVertices=(0..<3).compactMap {_ in device.makeBuffer(length:count*stride,options:.storageModeShared)}
        }
        guard faceMeshVertices.count==3 else {return false}
        if faceMeshIndices==nil || faceMeshIndexCount != face.triangles.count {
            faceMeshIndices=face.triangles.withUnsafeBytes {device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
            faceMeshIndexCount=face.triangles.count
        }
        guard faceMeshIndices != nil else {return false}
        let target=faceMeshVertices[slot].contents().bindMemory(to:Vertex.self,capacity:count)
        for (i,v) in face.vertices.enumerated() {target[i]=Vertex(position:SIMD4(v,1),rest:SIMD4(v,1),uv:.zero)}
        return true
    }
    /// Draws the face mesh into the depth buffer only, then every hair of each brow against it. `mvp` is projection * view * face.
    private func encodeHair(_ e:MTLRenderCommandEncoder,draws:[HairDraw],mvp:simd_float4x4,projectionScaleY:Float,size:CGSize,light:Float,uniforms u:Uniforms,obstruction:MTLTexture?,slot:Int) {
        guard let hairBuffer,let indices=faceMeshIndices,slot<faceMeshVertices.count,let obstruction else {return}
        var meshUniforms=u;meshUniforms.mvp=mvp
        e.setCullMode(.none)
        e.setRenderPipelineState(depth);e.setDepthStencilState(depthWrite)
        e.setVertexBuffer(faceMeshVertices[slot],offset:0,index:0);e.setVertexBytes(&meshUniforms,length:MemoryLayout<Uniforms>.stride,index:1)
        e.drawIndexedPrimitives(type:.triangle,indexCount:faceMeshIndexCount,indexType:.uint16,indexBuffer:indices,indexBufferOffset:0)
        e.setRenderPipelineState(browHairPipeline);e.setDepthStencilState(depthRead)
        var fragmentUniforms=u
        e.setFragmentBytes(&fragmentUniforms,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(obstruction,index:3)
        e.setVertexBuffer(hairBuffer,offset:0,index:0)
        for draw in draws {
            var h=HairUniforms(clipFromModel:mvp*draw.matrix,view:SIMD4(Float(size.width),Float(size.height),0.5*Float(size.height)*projectionScaleY,draw.scale),
                               look:SIMD4(light,1.5,0.04,0),probe:SIMD4(draw.probe.x,draw.probe.y,0,0))
            e.setVertexBytes(&h,length:MemoryLayout<HairUniforms>.stride,index:1);e.setFragmentBytes(&h,length:MemoryLayout<HairUniforms>.stride,index:1)
            e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:hairVertexCount)
        }
        e.setDepthStencilState(noDepth)
    }
    /// The face ARKit tracked in this very frame, for steadying the brow in face space; nil when ARKit has none.
    private func browFaceFrame(_ frame:ARFrame)->BrowFaceFrame? {
        guard case .normal=frame.camera.trackingState,let anchor=frame.anchors.compactMap({$0 as? ARFaceAnchor}).first(where:{$0.isTracked}) else {return nil}
        let geometry=anchor.geometry
        if browFaceTriangles.count != geometry.triangleIndices.count {browFaceTriangles=geometry.triangleIndices.map {UInt16(bitPattern:$0)}}
        let resolution=frame.camera.imageResolution
        return BrowFaceFrame(anchorID:anchor.identifier,vertices:geometry.vertices,triangles:browFaceTriangles,intrinsics:frame.camera.intrinsics,
                             imageSize:SIMD2(Float(resolution.width),Float(resolution.height)),faceToWorld:anchor.transform,cameraToWorld:frame.camera.transform)
    }
    /// Hands this frame to MediaPipe unless one is still being processed; it is drawn when its landmarks return.
    private func submitBrow(_ frame:ARFrame,settings s:Settings) {
        guard browTracker.isAvailable,!browTracker.isBusy,Self.browFrameDue(timestamp:frame.timestamp,last:lastBrowSubmit) else {return}
        let buffer=frame.capturedImage
        let raw=CGSize(width:CVPixelBufferGetWidth(buffer),height:CVPixelBufferGetHeight(buffer))
        // The screen's up and across directions in the captured image pick the detector's rotation; no face tracker.
        let toRaw=frame.displayTransform(for:s.orientation,viewportSize:s.viewport).inverted()
        func direction(_ a:CGPoint,_ b:CGPoint)->CGPoint {
            let p=a.applying(toRaw),q=b.applying(toRaw)
            return CGPoint(x:(q.x-p.x)*raw.width,y:(q.y-p.y)*raw.height)
        }
        let up=direction(CGPoint(x:0.5,y:0.6),CGPoint(x:0.5,y:0.4)),across=direction(CGPoint(x:0.4,y:0.5),CGPoint(x:0.6,y:0.5))
        let entry=BrowFrame(frame:frame,epoch:s.epoch,face:browFaceFrame(frame))
        lock.lock()
        browToken += 1;let token=browToken;lastBrowSubmit=frame.timestamp
        browFrames=browFrames.filter {token-$0.key<2};browFrames[token]=entry
        lock.unlock()
        if !browTracker.submit(BrowTrackerInput(pixelBuffer:SendablePixelBuffer(buffer:buffer),timestamp:frame.timestamp,headUp:up,headAcross:across,token:token)) {
            lock.lock();browFrames[token]=nil;lock.unlock()
        }
        queue.async { [self] in
            // Hand/fringe occlusion uses the same face-skin mask as blush, at the same 15 Hz. Only the brow shape and the
            // hidden natural brow draw over the face, so only they need it.
            guard s.browOverlay != nil || s.hideNatural,entry.frame.timestamp-lastSegment>=1/15,!segmenter.isBusy,segmenter.isAvailable else {return}
            lastSegment=entry.frame.timestamp
            segmenter.submit(.init(pixelBuffer:SendablePixelBuffer(buffer:entry.frame.capturedImage),timestamp:entry.frame.timestamp,headUp:up,headAnchors:[]))
        }
    }
    private func renderBrow(_ result:BrowTrackerResult) {
        lock.lock();let entry=browFrames.removeValue(forKey:result.token);let s=settings;lock.unlock()
        guard let entry,s.enabled,s.isBrow,s.epoch==entry.epoch,s.viewport.width>0,s.viewport.height>0 else {return}
        autoreleasepool {drawBrow(entry.frame,observation:result.observation,face:entry.face,settings:s)}
    }
    private func bakeBrowTexture(_ style:EyebrowStyle,command:MTLCommandBuffer)throws {
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
    private func uploadBrowOverlay(_ baked:BakedBrowSprite,id:String,command:MTLCommandBuffer)throws {
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:baked.width,height:baked.height,mipmapped:true)
        desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
        guard let target=device.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
        baked.texels.withUnsafeBytes {target.replace(region:MTLRegionMake2D(0,0,baked.width,baked.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:baked.width*8)}
        guard let mip=command.makeBlitCommandEncoder() else {throw CocoaError(.featureUnsupported)}
        mip.generateMipmaps(for:target);mip.endEncoding()
        browTexture=target;browTextureKey="overlay:\(id)"
    }
    private func encodeBrowTexture(_ design:BrowDesign,into target:MTLTexture,command:MTLCommandBuffer)throws {
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
    private static func browStrip(_ o:BrowObservation,display:CGAffineTransform,chord:Bool=false)->BrowStrip? {
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
            let columns=(0...browColumns).map {column->(u:Float,half:Float,lower:(core:Float,end:Float),bow:Float) in
                let u=browExtent.x+(browExtent.y-browExtent.x)*Float(column)/Float(browColumns)
                return (u,g.observedHalf(u),lower(u),chord ? g.chordOffset(u):0)
            }
            for row in 0...browRows {
                let w=browExtent.z*(2*Float(row)/Float(browRows)-1)
                for c in columns {
                    let above=g.point(u:c.u,w:w+0.2)/image,below=g.point(u:c.u,w:w-0.2)/image
                    out.append(BrowVertex(position:clip(g.point(u:c.u,w:w)),brow:SIMD4(c.u,w,c.half,fade*fade*(3-2*fade)),
                                          probes:SIMD4(above.x,above.y,below.x,below.y),skin:SIMD4(blur.x,blur.y,c.bow,0),
                                          conceal:SIMD4(c.lower.core,c.lower.end,index,0)))
                }
            }
            // Unwrap grid for hiding the natural brow: the same columns, from below the brow up into the forehead.
            let space=BrowEraser.space
            for row in 0...BrowEraser.rows {
                let w=space.z+(space.w-space.z)*Float(row)/Float(BrowEraser.rows)
                for c in columns {
                    let p=g.point(u:c.u,w:w)
                    let crop=cropToRaw.map {BrowEraser.cropPoint(p,imageSize:o.imageSize,cropToRaw:$0)} ?? SIMD2(-2,-2)
                    unwrap.append(BrowUnwrapVertex(brow:SIMD4(c.u,w,c.half,index),raw:SIMD4(p.x/image.x,p.y/image.y,crop.x*2-1,1-crop.y*2),
                                                   conceal:SIMD4(c.lower.core,c.lower.end,0,0)))
                }
            }
        }
        guard out.allSatisfy({$0.position.x.isFinite && $0.position.y.isFinite}),unwrap.allSatisfy({$0.raw.x.isFinite && $0.raw.y.isFinite}) else {return nil}
        return BrowStrip(vertices:out,unwrap:unwrap,cropToRaw:cropToRaw)
    }
    /// Lines and dots in the camera image, turned into alpha-blended triangles in clip space.
    private struct MarkBuilder {
        let image:SIMD2<Float>,pixels:SIMD2<Float>,display:CGAffineTransform
        let thickness:Float
        var out:[MarkVertex]=[]
        init(imageSize:CGSize,drawable:CGSize,display:CGAffineTransform) {
            image=SIMD2(Float(imageSize.width),Float(imageSize.height));pixels=SIMD2(Float(drawable.width),Float(drawable.height))
            self.display=display;thickness=max(2,pixels.x*0.004)
        }
        func view(_ p:SIMD2<Float>)->SIMD2<Float> {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display)
            return SIMD2(Float(v.x),Float(v.y))*pixels
        }
        func clip(_ p:SIMD2<Float>)->SIMD4<Float> {SIMD4(p.x/pixels.x*2-1,1-p.y/pixels.y*2,0,1)}
        mutating func line(_ a:SIMD2<Float>,_ b:SIMD2<Float>,_ color:SIMD4<Float>,width:Float=1) {
            let p=view(a),q=view(b),d=q-p,length=simd_length(d)
            guard length>1 else {return}
            let n=SIMD2(-d.y,d.x)/length*thickness*width/2
            out += [p+n,p-n,q+n,p-n,q-n,q+n].map {MarkVertex(position:clip($0),color:color)}
        }
        mutating func polyline(_ points:[SIMD2<Float>],_ color:SIMD4<Float>,width:Float=1) {
            for (a,b) in zip(points,points.dropFirst()) {line(a,b,color,width:width)}
        }
        mutating func dot(_ c:SIMD2<Float>,_ radius:Float,_ color:SIMD4<Float>,segments:Int=12) {
            let p=view(c)
            for i in 0..<segments {
                let a0=Float(i)/Float(segments)*2*Float.pi,a1=Float(i+1)/Float(segments)*2*Float.pi
                out += [p,p+SIMD2(cos(a0),sin(a0))*radius,p+SIMD2(cos(a1),sin(a1))*radius].map {MarkVertex(position:clip($0),color:color)}
            }
        }
    }
    /// Tutorial nose-eye mapping lines (brow start, arch, tail) and landmark debug dots, in clip space.
    private static func browMarks(_ o:BrowObservation,display:CGAffineTransform,size:CGSize,landmarks:Bool,mapping:Bool,alpha:Float)->[MarkVertex] {
        var m=MarkBuilder(imageSize:o.imageSize,drawable:size,display:display)
        let thickness=m.thickness
        if mapping {
            let guide=SIMD4<Float>(0.95,0.72,0.80,0.85*alpha)
            for side in [EyeSide.subjectRight,.subjectLeft] {
                guard let eye=o.eyes[side],let contour=o.brows[side],let brow=BrowGeometry(contour:contour) else {continue}
                for through in [eye.inner,eye.iris ?? (eye.inner+eye.outer)/2,eye.outer] {
                    guard let hit=brow.crossing(from:eye.ala,through:through) else {continue}
                    m.line(eye.ala,hit,guide);m.dot(hit,thickness*2.2,guide)
                }
            }
        }
        if landmarks {
            for (side,contour) in o.brows {
                for p in contour.upper+contour.lower {m.dot(p,thickness*1.5,SIMD4(1,0.15,0.1,1))}
                if let eye=o.eyes[side] {
                    for p in [eye.inner,eye.outer]+(eye.iris.map {[$0]} ?? []) {m.dot(p,thickness*1.5,SIMD4(0.1,0.9,1,1))}
                    m.dot(eye.ala,thickness*1.5,SIMD4(1,0.9,0.1,1))
                }
            }
            m.dot(o.noseBridge,thickness*1.5,SIMD4(1,0.9,0.1,1))
        }
        return m.out
    }
    /// The MediaPipe tracking view: every face landmark, each brow's raw and smoothed points and contours, the fitted
    /// centerline and the brow frame a shape is drawn in, and the eye, iris, nose and nose-bridge points.
    private static func browTrackingMarks(_ o:BrowObservation,raw:BrowObservation?,display:CGAffineTransform,size:CGSize,tracked:Bool)->[MarkVertex] {
        var m=MarkBuilder(imageSize:o.imageSize,drawable:size,display:display)
        let t=m.thickness,fade:Float=tracked ? 1:0.45
        for p in o.mesh {m.dot(p,t*0.55,SIMD4(1,1,1,0.4),segments:4)}
        let upper=SIMD4<Float>(1,0.25,0.2,fade),lower=SIMD4<Float>(1,0.6,0.1,fade),center=SIMD4<Float>(1,0.9,0.1,fade)
        let frame=SIMD4<Float>(0.1,0.85,1,0.8*fade),tick=SIMD4<Float>(0.3,1,0.4,0.8*fade),eyeColor=SIMD4<Float>(1,0.2,0.9,1)
        let contours=o.brows.compactMap {$0.value}
        let across=contours.compactMap {BrowGeometry(contour:$0)?.width}.max()
        for contour in contours {
            if let g=BrowGeometry(contour:contour,across:across) {
                let e=browExtent
                let us=(0...24).map {e.x+(e.y-e.x)*Float($0)/24}
                m.polyline(us.map {g.point(u:$0,w:e.z)},frame,width:0.6)
                m.polyline(us.map {g.point(u:$0,w:-e.z)},frame,width:0.6)
                m.line(g.point(u:e.x,w:-e.z),g.point(u:e.x,w:e.z),frame,width:0.6)
                m.line(g.point(u:e.y,w:-e.z),g.point(u:e.y,w:e.z),frame,width:0.6)
                for u:Float in [0,0.5,1] {m.line(g.point(u:u,w:-e.z),g.point(u:u,w:e.z),tick,width:0.6)}
                m.polyline((0...30).map {g.point(u:Float($0)/30,w:0)},center,width:1.2)
            }
            m.polyline(contour.upper,upper);m.polyline(contour.lower,lower)
        }
        if let raw {for contour in raw.brows.values {for p in contour.upper+contour.lower {m.dot(p,t*1.1,SIMD4(0.75,0.75,0.75,0.9))}}}
        for contour in contours {
            for p in contour.upper {m.dot(p,t*2.1,upper)}
            for p in contour.lower {m.dot(p,t*2.1,lower)}
        }
        for eye in o.eyes.values {
            m.polyline(eye.lid,eyeColor,width:0.7)
            m.dot(eye.inner,t*1.8,eyeColor);m.dot(eye.outer,t*1.8,eyeColor);m.dot(eye.ala,t*1.8,eyeColor)
            if let iris=eye.iris {m.dot(iris,t*2.4,eyeColor)}
        }
        m.dot(o.noseBridge,t*2.4,SIMD4(1,1,1,1))
        return m.out
    }
    /// Head pose as seen on screen. MediaPipe's matrix follows the camera sensor, which is turned 90° in portrait, so
    /// its roll is re-measured from the eye corners on screen and yaw/pitch are turned by the same amount.
    static func screenPose(_ o:BrowObservation,display:CGAffineTransform)->BrowHeadPose {
        guard let r=o.eyes[.subjectRight]?.inner,let l=o.eyes[.subjectLeft]?.inner else {return o.pose}
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        func view(_ p:SIMD2<Float>)->SIMD2<Float> {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display);return SIMD2(Float(v.x),Float(v.y))
        }
        let axis=view(l)-view(r)
        var roll=atan2(axis.y,axis.x)*180/Float.pi
        // The eye axis has no front or back: keep the reading within ±90°, whichever way the view is mirrored.
        if roll>90 {roll -= 180} else if roll < -90 {roll += 180}
        return o.pose.turned(toRoll:roll)
    }
    /// MediaPipe indices beside the points, for the tracking view's labels (view-normalized positions).
    private static func browTrackingLabels(_ o:BrowObservation,display:CGAffineTransform)->[BrowTrackingSnapshot.Label] {
        let image=SIMD2(Float(o.imageSize.width),Float(o.imageSize.height))
        func label(_ text:String,_ p:SIMD2<Float>)->BrowTrackingSnapshot.Label {
            let v=CGPoint(x:CGFloat(p.x/image.x),y:CGFloat(p.y/image.y)).applying(display)
            return .init(text:text,x:Float(v.x),y:Float(v.y))
        }
        var out:[BrowTrackingSnapshot.Label]=[]
        let maps:[(EyeSide,MediaPipeEyeLandmarkProvider.EyeIndexMap)]=[(.subjectRight,MediaPipeEyeLandmarkProvider.subjectRightMap),(.subjectLeft,MediaPipeEyeLandmarkProvider.subjectLeftMap)]
        for (side,map) in maps {
            // Contours run head to tail; the index rows run tail to head.
            if let contour=o.brows[side] {
                out += zip(map.browUpper.reversed(),contour.upper).map {label("\($0)",$1)}
                out += zip(map.browLower.reversed(),contour.lower).map {label("\($0)",$1+SIMD2(0,0))}
            }
            if let eye=o.eyes[side] {
                out += [label("\(map.inner)",eye.inner),label("\(map.outer)",eye.outer),label("ala",eye.ala)]
                if let iris=eye.iris {out.append(label("iris",iris))}
            }
        }
        out.append(label("\(MediaPipeBrowTracker.noseBridge)",o.noseBridge))
        return out
    }
    private var browFaceVisible=false,browMaskFresh=false
    /// Brow status as soon as it changes: no face, mask not ready, or an error. Render queue only.
    private func publishBrowStatus() {
        let next:String?=lastError != nil ? String(localized:"Makeup is temporarily unavailable")
            : (!browFaceVisible ? String(localized:"Look straight at the camera to place your makeup")
            : (!browMaskFresh ? String(localized:"Preparing makeup visibility"):nil))
        if case .some(let current)=browStatus,current==next {return}
        browStatus = .some(next);onStatus?(next)
    }
    private func drawBrow(_ frame:ARFrame,observation detected:BrowObservation?,face:BrowFaceFrame?,settings s:Settings) {
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
        var observation:BrowObservation?
        if let detected {
            if let face,let steady=browStabilizer.stabilize(detected,face:face) {observation=steady;browSmoother.reset();browStabilized=true}
            else {browStabilizer.reset();observation=browSmoother.smooth(detected);browStabilized=false}
        } else {browSmoother.reset();browStabilizer.reset();browStabilized=false}
        let tracked=observation.map {abs($0.pose.yaw)<config.max_yaw_degrees && abs($0.pose.pitch)<config.max_yaw_degrees} ?? false
        // A 3D brow needs ARKit's face in this frame (browStabilized) and its mesh; otherwise its picture is drawn instead.
        let hairMesh=s.browOverlay?.is3D==true && browStabilized && tracked ? hairMeshIfReady():nil
        var hairDraws:[HairDraw]=[]
        if let hairMesh,let observation,let face {hairDraws=Self.hairPlacements(observation,face:face,mesh:hairMesh)}
        let hair3D = !hairDraws.isEmpty
        let pigment=s.browOverlay != nil && !hair3D
        let strip=tracked && (pigment || s.hideNatural) ? observation.flatMap {Self.browStrip($0,display:display,chord:pigment)}:nil
        let (frameMask,maskTransform,fresh)=uploadMask(slot:frameSlot,capturedImage:buffer,maxAge:max(config.mask_max_age_seconds,Self.browMaskGraceSeconds))
        // Hiding the natural brow does not wait for the mask; a hand only starts to protect it once one arrives.
        let ready=fresh || !(pigment || hair3D)
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
            eraser.encode(vertices:strip.unwrap,cropToRaw:strip.cropToRaw,uniforms:withUnsafeBytes(of:&u) {Array($0)},y:y,cb:cb,timestamp:frame.timestamp,command:command)
        } else {eraser?.reset()}
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        if s.comparisonSplit {e.setScissorRect(MTLScissorRect(x:0,y:0,width:max(1,drawable.texture.width/2),height:drawable.texture.height))}
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
            marks=Self.browMarks(observation,display:display,size:size,landmarks:debugView==2,mapping:s.guide && s.mapping,alpha:Float(visible))
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
                if show {self.layer?.isHidden=false}
            }
            self?.queue.async { [weak self] in self?.report(cb,frameTimestamp:ts,maskFresh:fresh,visibility:visible,isBrow:true) }
        }
        committed=true;command.commit()
    }
    private func report(_ cb:MTLCommandBuffer,frameTimestamp:Double,maskFresh:Bool,visibility:Double,isBrow:Bool) {
        let now=CACurrentMediaTime();if reportStart==0 {reportStart=now}
        reportFrames += 1;gpuTimes.append(max(0,cb.gpuEndTime-cb.gpuStartTime)*1000);ages.append(max(0,now-frameTimestamp)*1000)
        guard now-reportStart>=2 else{return}
        let sorted=ages.sorted(),p95=sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]
        var report:[String:Any]=["engine":isBrow ? "mediapipe_metal":"arkit_metal_uv","category":isBrow ? "eyebrow":"blush","fps_completed":Double(reportFrames)/(now-reportStart),"fps_presented":Double(presentedFrames)/(now-reportStart),"pigment_frames":pigmentFrames,"projection_error_pixels":projectionErrorPixels,"gpu_ms_mean":gpuTimes.reduce(0,+)/Double(gpuTimes.count),"frame_age_ms_p95":p95,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"mask_fresh":maskFresh,"mask_age_ms":maskAgeMilliseconds,"segmenter_available":segmenter.isAvailable,"visibility":visibility,"error":lastError ?? "none","shader_error":cb.error?.localizedDescription ?? "none"]
        if isBrow {report["landmark_latency_ms"]=browTracker.lastLatencyMs;report["brow_tracker_available"]=browTracker.isAvailable;report["brow_stabilized"]=browStabilized}
        // The brow publishes its own status as soon as it changes (a face found or lost cannot wait two seconds).
        if !isBrow {onStatus?(lastError != nil || cb.error != nil ? String(localized:"Makeup is temporarily unavailable") : (!maskFresh && visibility<0.1 ? String(localized:"Preparing makeup visibility"):nil))}
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
    static func renderAtlasFixture(placement:BlushPlacementGuide?=nil)throws->[Float] {
        let engine=try BeautyBlushEngine(),d=engine.device,n=placement == nil ? 64:256
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
        e.setRenderPipelineState(engine.atlasPipeline);e.setVertexBuffer(vb,offset:0,index:0);e.setFragmentBytes(&b,length:MemoryLayout<Bake>.stride,index:0);e.setFragmentTexture(engine.brush,index:0)
        e.drawIndexedPrimitives(type:.triangle,indexCount:triangles.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding();command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var raw=Array(repeating:UInt16(0),count:n*n*4)
        raw.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*8,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return raw.map {Float(Float16(bitPattern:$0))}
    }
    // Real Metal pixel fixture. Uses the production shader pipelines, with synthetic camera/UV data.
    static func renderPixelFixture(obstructed:Bool,intensity:Float,atlasValue:UInt8=255)throws->Data {
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
        let atlas=try texture(.rgba8Unorm,Array(repeating:atlasValue,count:n*n*4),n*4)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let positions:[SIMD3<Float>]=[.init(-0.8,-0.8,0.2),.init(0.8,-0.8,0.2),.init(0.8,0.8,0.2),.init(-0.8,0.8,0.2)]
        let points=positions.map {Vertex(position:SIMD4($0,1),rest:SIMD4($0,1),uv:SIMD4(($0.x+1)/2,($0.y+1)/2,0,0))}
        let tris:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=tris.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.8,0.05,0.15,intensity),controls:SIMD4(0.9,0.65,0.85,0.68),tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,0),stretch:SIMD4(0.45,0.7,1.45,1.85))
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
    /// The production brow texture bake for `style`, read back as RGBA floats (`width` x `height`).
    static func renderBrowTextureFixture(style:EyebrowStyle,width:Int=256,height:Int=128)throws->[Float] {
        let engine=try BeautyBlushEngine(),d=engine.device
        guard let design=BrowDesign.make(style:style) else {throw CocoaError(.coderInvalidValue)}
        let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:width,height:height,mipmapped:false);desc.storageMode = .shared;desc.usage=[.renderTarget,.shaderRead]
        guard let target=d.makeTexture(descriptor:desc),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        try engine.encodeBrowTexture(design,into:target,command:command)
        command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var raw=Array(repeating:UInt16(0),count:width*height*4)
        raw.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:width*8,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)}
        return raw.map {Float(Float16(bitPattern:$0))}
    }
    /// The production brow strip pipeline over a synthetic camera: a strip quad at the brow centre fills most of
    /// the target, and the brow texture holds `textureValue` in every channel. `darkBrow` puts a dark band (the natural
    /// brow) across the middle rows of the camera; `hideNatural` turns on hiding it, with the brow shape off.
    static func renderBrowStripFixture(obstructed:Bool,intensity:Float,textureValue:UInt8=255,darkBrow:Bool=false,hideNatural:Bool=false)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=32
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,(0..<n*n).map {darkBrow && (12..<20).contains($0/n) ? 40:180},n)
        let cb=try texture(.rg8Unorm,Array(repeating:128,count:n*n*2),n*2)
        let mask=try texture(.r8Unorm,Array(repeating:obstructed ? 255:0,count:n*n),n)
        let brow=try texture(.rgba8Unorm,Array(repeating:textureValue,count:n*n*4),n*4)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let corners:[SIMD2<Float>]=[.init(-0.8,-0.8),.init(0.8,-0.8),.init(0.8,0.8),.init(-0.8,0.8)]
        let points=corners.map {BrowVertex(position:SIMD4($0.x,$0.y,0,1),brow:SIMD4(0.5,0,0.1,1),probes:SIMD4(0.5,0.4,0.5,0.6),
                                           skin:SIMD4(0.05,0.05,0,0),conceal:SIMD4(0.16,0.3,0,0.17))}
        let tris:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=tris.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.05,0.03,0.02,intensity),controls:SIMD4(0.9,0.65,0.85,0.68),tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,1),stretch:SIMD4(0.45,0.7,1.45,1.85),
                       debug:SIMD4(0,hideNatural ? 1:0,hideNatural ? 0:1,0))
        var extent=browExtent
        // The eraser's fill, here the camera's bright skin colour (linear) in both brow slices.
        let fillDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:4,height:4,mipmapped:false)
        fillDescriptor.textureType = .type2DArray;fillDescriptor.arrayLength=2;fillDescriptor.usage = .shaderRead;fillDescriptor.storageMode = .shared
        guard let fill=d.makeTexture(descriptor:fillDescriptor) else {throw CocoaError(.featureUnsupported)}
        let skinValue=Float16(BeautyBlushConfiguration.linear(180/255)).bitPattern,one=Float16(1).bitPattern
        let fillTexels=(0..<16).flatMap {_ in [skinValue,skinValue,skinValue,one]}
        for slice in 0..<2 {fillTexels.withUnsafeBytes {fill.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,slice:slice,withBytes:$0.baseAddress!,bytesPerRow:32,bytesPerImage:128)}}
        var space=BrowEraser.space
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        e.setRenderPipelineState(engine.background);e.setDepthStencilState(engine.noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        e.setRenderPipelineState(engine.browStripPipeline);e.setVertexBuffer(vb,offset:0,index:0)
        e.setFragmentBytes(&space,length:MemoryLayout<SIMD4<Float>>.stride,index:2);e.setFragmentTexture(fill,index:4)
        // Hide mask: fully hidden everywhere (all ones), so the fixture tests the composite, not the area.
        guard let hide=d.makeTexture(descriptor:fillDescriptor) else {throw CocoaError(.featureUnsupported)}
        let ones=Array(repeating:one,count:64)
        for slice in 0..<2 {ones.withUnsafeBytes {hide.replace(region:MTLRegionMake2D(0,0,4,4),mipmapLevel:0,slice:slice,withBytes:$0.baseAddress!,bytesPerRow:32,bytesPerImage:128)}}
        e.setFragmentTexture(hide,index:5)
        e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentBytes(&extent,length:MemoryLayout<SIMD4<Float>>.stride,index:1)
        e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1);e.setFragmentTexture(brow,index:2);e.setFragmentTexture(mask,index:3)
        e.drawIndexedPrimitives(type:.triangle,indexCount:tris.count,indexType:.uint16,indexBuffer:ib,indexBufferOffset:0);e.endEncoding()
        command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var data=Data(count:n*n*4);data.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*4,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return data
    }
    /// The production 3D hair pipeline over a flat face 30 cm from the camera: the brow mesh on it, an occluding patch of the face
    /// nearer to the camera when `occluderInFront`, and the face-skin mask covering everything when `handCovers`. Returns the
    /// target's BGRA pixels (128 x 128) over a mid-grey frame.
    static func renderBrowHairFixture(intensity:Float=1,occluderInFront:Bool=false,handCovers:Bool=false)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=128
        guard let mesh=BrowHairMesh.load() else {throw CocoaError(.fileNoSuchFile)}
        engine.installHairMesh(mesh)
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let mask=try texture(.r8Unorm,Array(repeating:handCovers ? 255:0,count:n*n),n)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        // The face: a flat patch at the head's depth, or in front of the brow by 2 cm.
        let depth:Float=occluderInFront ? 0.02:-0.01
        let patch:[SIMD3<Float>]=[.init(-0.06,-0.02,depth),.init(0.06,-0.02,depth),.init(0.06,0.07,depth),.init(-0.06,0.07,depth)]
        var faceToWorld=matrix_identity_float4x4;faceToWorld.columns.3=SIMD4(0,0,-0.3,1)
        let face=BrowFaceFrame(anchorID:UUID(),vertices:patch,triangles:[0,1,2,0,2,3],intrinsics:matrix_identity_float3x3,imageSize:SIMD2(1,1),faceToWorld:faceToWorld,cameraToWorld:matrix_identity_float4x4)
        guard engine.uploadFaceMesh(face,slot:0) else {throw CocoaError(.featureUnsupported)}
        guard let placement=BrowHairPlacement.frame(mesh:mesh,head:SIMD3(-0.027,0.02,0),tail:SIMD3(0.027,0.02,0),normal:SIMD3(0,0,1),forehead:SIMD3(0,1,0)) else {throw CocoaError(.coderInvalidValue)}
        // A Metal-style perspective: 0.05 m either side of the axis at 0.3 m fills the frame.
        let (near,far,scale):(Float,Float,Float)=(0.001,10,6)
        let projection=simd_float4x4(columns:(SIMD4(scale,0,0,0),SIMD4(0,scale,0,0),SIMD4(0,0,far/(near-far),-1),SIMD4(0,0,far*near/(near-far),0)))
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(0.05,0.03,0.02,intensity),controls:.zero,
                       tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,0,1),stretch:.zero)
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0.5,0.5,0.5,1)
        pass.depthAttachment.texture=z;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{throw CocoaError(.featureUnsupported)}
        engine.encodeHair(e,draws:[HairDraw(matrix:placement.matrix,scale:placement.scale,probe:SIMD2(0,0.02))],mvp:projection*faceToWorld,projectionScaleY:scale,
                          size:CGSize(width:n,height:n),light:1,uniforms:u,obstruction:mask,slot:0)
        e.endEncoding();command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        var data=Data(count:n*n*4);data.withUnsafeMutableBytes {target.getBytes($0.baseAddress!,bytesPerRow:n*4,from:MTLRegionMake2D(0,0,n,n),mipmapLevel:0)}
        return data
    }
    /// The tracking view's mark vertex count and point labels for a synthetic observation.
    static func browTrackingFixture(_ observation:BrowObservation)->(vertices:Int,labels:[String]) {
        (browTrackingMarks(observation,raw:observation,display:.identity,size:CGSize(width:390,height:844),tracked:true).count,
         browTrackingLabels(observation,display:.identity).map(\.text))
    }
    /// Runs the eraser on a synthetic camera: bright skin, and dark brow hair around the subject's right brow that
    /// reaches `hairAbove` brow widths above its centerline. Returns the hide mask there at `w` (u = 0.5).
    static func browHideFixture(_ observation:BrowObservation,hairAbove:Float,w:Float)throws->Float {
        let engine=try BeautyBlushEngine(),d=engine.device
        guard let eraser=engine.eraser,let strip=browStrip(observation,display:.identity),let right=observation.brows[.subjectRight],
              let g0=BrowGeometry(contour:right) else {throw CocoaError(.featureUnsupported)}
        let left=observation.brows[.subjectLeft].flatMap {BrowGeometry(contour:$0)}
        guard let g=BrowGeometry(contour:right,across:max(g0.width,left?.width ?? 0)) else {throw CocoaError(.featureUnsupported)}
        let width=250,height=200,image=SIMD2(Float(observation.imageSize.width),Float(observation.imageSize.height))
        var luma=[UInt8](repeating:200,count:width*height)
        for u in stride(from:Float(0),through:1,by:0.01) {
            for across in stride(from:-g.observedHalf(u),through:hairAbove,by:0.01) {
                let p=g.point(u:u,w:across)/image
                let x=Int(p.x*Float(width)),y=Int(p.y*Float(height))
                if (0..<width).contains(x),(0..<height).contains(y) {luma[y*width+x]=40}
            }
        }
        func texture(_ format:MTLPixelFormat,_ w:Int,_ h:Int,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:w,height:h,mipmapped:false);desc.usage = .shaderRead;desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else {throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,width,height,luma,width),cb=try texture(.rg8Unorm,width/2,height/2,Array(repeating:128,count:width*height/2),width)
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:.zero,controls:.zero,tracking:.zero,camera:SIMD4(1,1,0,1),stretch:.zero)
        guard let command=engine.commands.makeCommandBuffer() else {throw CocoaError(.featureUnsupported)}
        eraser.encode(vertices:strip.unwrap,cropToRaw:nil,uniforms:withUnsafeBytes(of:&u) {Array($0)},y:y,cb:cb,timestamp:1,command:command)
        command.commit();command.waitUntilCompleted()
        if let error=command.error {throw error}
        return try eraser.hideFixture(u:0.5,w:w,slice:0,commands:engine.commands)
    }
    /// Strip vertices for a synthetic observation, as the renderer builds them.
    static func browStripFixture(_ observation:BrowObservation)->[(position:SIMD4<Float>,brow:SIMD4<Float>)]? {
        browStrip(observation,display:.identity)?.vertices.map {($0.position,$0.brow)}
    }
    /// Lower edge of the hidden-brow area per strip column of the subject's right brow, as (core, end) in brow widths.
    static func browConcealLowerFixture(_ observation:BrowObservation)->[SIMD2<Float>]? {
        browStrip(observation,display:.identity)?.vertices.prefix(browColumns+1).map {SIMD2($0.conceal.x,$0.conceal.y)}
    }
    #endif

}
