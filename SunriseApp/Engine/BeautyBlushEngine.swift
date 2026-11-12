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
    struct FrameLifetime:@unchecked Sendable {let y:CVMetalTexture;let cb:CVMetalTexture;let frame:ARFrame}
    struct Vertex {var position:SIMD4<Float>;var rest:SIMD4<Float>;var uv:SIMD4<Float>}
    struct Uniforms {
        var mvp:simd_float4x4;var rawFromClip:simd_float4x4;var maskFromRaw:simd_float4x4
        var shade:SIMD4<Float>;var controls:SIMD4<Float>;var tracking:SIMD4<Float>;var camera:SIMD4<Float>;var stretch:SIMD4<Float>
        var debug=SIMD4<Float>.zero
        /// Blush only: x `BlushBlend`, y `BlushDiagnostic`, z detail radius in camera pixels. See BeautyBlush.metal.
        var blush=SIMD4<Float>.zero
    }
    struct BrowVertex {var position:SIMD4<Float>;var brow:SIMD4<Float>;var probes:SIMD4<Float>;var skin:SIMD4<Float>;var conceal:SIMD4<Float>}
    struct BrowStrip {var vertices:[BrowVertex];var unwrap:[BrowUnwrapVertex];var cropToRaw:simd_float4x4?}
    struct MarkVertex {var position:SIMD4<Float>;var color:SIMD4<Float>}
    struct HairUniforms {var clipFromModel:simd_float4x4;var view:SIMD4<Float>;var look:SIMD4<Float>;var probe:SIMD4<Float>}
    /// One brow's hair mesh on the face: model to face-local, its scale and the raw-image offset for the hand check.
    struct HairDraw {var matrix:simd_float4x4;var scale:Float;var probe:SIMD2<Float>}
    struct BrowFrame:@unchecked Sendable {let frame:ARFrame;let epoch:UUID;let face:BrowFaceFrame?}
    struct Field {var ellipse:SIMD4<Float>;var shape:SIMD4<Float>;var limits:SIMD4<Float>}
    struct Bake {var left:Field;var right:Field;var bridge=Field(ellipse:.zero,shape:.zero,limits:.zero);var paint=SIMD4<Float>.zero;var options=SIMD4<Float>.zero;var mouth=SIMD4<Float>.zero}
    struct Settings {
        var comparisonSplit=false;var browOnlySide:EyeSide?;var mappingSide:EyeSide?;var enabled=false;var tint=SIMD3<Float>(0.9,0.3,0.45);var intensity:Float=0.72;var style=BlushPlacementStyle.cheekbone;var browStyle=EyebrowStyle.softNatural;var browOverlay:BrowOverlay?;var isBrow=false;var guide=false;var mapping=false;var tracking=false;var hideNatural=false;var viewport=CGSize.zero;var orientation=UIInterfaceOrientation.portrait;var epoch=UUID()
        /// Blush drawn too (on the brow path when the brow is also on). Its own shade and strength: brow and blush differ.
        var pigmentHalf=PigmentHalf.full
        var withBlush=false;var blushTint=SIMD3<Float>(0.9,0.3,0.45);var blushIntensity:Float=0.72
    }
    /// Developer brow view (`BrowDebugView` raw value), read each frame so the developer picker applies live.
    static let browDebugKey="beautyBrow.debugView"
    /// Developer blush blend and diagnostic (`BlushBlend` / `BlushDiagnostic` raw values), read each frame; only
    /// honoured while developer tools are on, so a stale value can never change what users see.
    static let blushBlendKey="beautyBlush.blend",blushDiagnosticKey="beautyBlush.diagnostic"
    /// How long the brow keeps using the last face-skin mask. The segmenter often lags past `mask_max_age_seconds`
    /// on device, and dropping the brow for those frames made it blink; a hand still hides it within this time.
    static let browMaskGraceSeconds:Double=0.6
    let inFlight=DispatchSemaphore(value:3)
    let lock=NSLock(),queue=DispatchQueue(label:"dandan.blush.metal",qos:.userInteractive)
    let device:MTLDevice,commands:MTLCommandQueue
    let config:BeautyBlushConfiguration
    let background,face,depth,wire,atlasPipeline,browTexturePipeline,browStripPipeline,browMarkPipeline,browHairPipeline:MTLRenderPipelineState
    let depthWrite,depthRead,noDepth:MTLDepthStencilState
    let brush:MTLTexture
    var textureCache:CVMetalTextureCache?
    var layer:CAMetalLayer?
    /// Whether `configure` turned drawing on (developer read-out).
    var isDrawing:Bool {lock.lock();defer{lock.unlock()};return settings.enabled}
    /// Shutters waiting for the next presented picture (`readScreen`). Guarded by `lock`.
    var screenReaders:[ScreenReader]=[]
    var settings=Settings(),busy=false
    var vertices:[MTLBuffer]=[],indices:MTLBuffer?,bakeVertices:MTLBuffer?,indexCount=0,slot=0
    var rest:[SIMD3<Float>]=[],uvs:[SIMD2<Float>]=[],filters:[OneEuroFilter]=[]
    var atlas:MTLTexture?,depthTexture:MTLTexture?
    var maskTextures:[MTLTexture?]=[nil,nil,nil],maskVersions:[Double]=[-1,-1,-1],cachedMaskBytes:[UInt8]=[]
    // Repeated failed blush fits are throttled so a style tap cannot make the render queue
    // spend every frame rebuilding the same atlas.
    var attemptedBlushStyle:BlushPlacementStyle?
    var lastBindAttempt:Double = -.infinity
    // MediaPipe brow: one frame in flight, kept until its landmarks come back, then drawn with them.
    let browTracker=MediaPipeBrowTracker()
    var browTrackerTask:Task<Void,Never>?
    var browTrackerStarting=false
    var browToken:UInt64=0,browFrames:[UInt64:BrowFrame]=[:]
    var lastBrowSubmit:Double = -.infinity
    /// Blush cheek fit from MediaPipe (reference looks): frontal frames lifted onto ARKit's mesh, then their median, once per
    /// face anchor. Until it is ready the ARKit-only fit is drawn. `blushLandmarks` is guarded by `lock`; the rest is render queue.
    static let blushLandmarkSamples=10
    var blushSamples:[[SIMD3<Float>]]=[],blushSampleAnchor:UUID?
    var blushLandmarks:(anchor:UUID,value:BlushCheekLandmarks)?
    var atlasFromLandmarks=false
    /// Blush tutorial outlines bound to the mesh at bake time (inner circle, outer line, centre, outward point per cheek),
    /// projected and published while the guide is on. Render queue only.
    struct GuideOutline {var inner:[SurfaceAttachment];var outer:[SurfaceAttachment];var center:SurfaceAttachment;var outward:SurfaceAttachment}
    var guideOutlines:[GuideOutline]=[]
    var lastGuidePublish:Double = -.infinity,guidePublished=false
    /// When the outlines last had a tracked face; they stay up through a short loss instead of blinking.
    var guideSeen:Double = -.infinity
    static let guideHoldSeconds:Double=0.5
    var onBlushGuide:(@Sendable (BlushGuideSnapshot?)->Void)?
    var browSmoother=BrowObservationSmoother()
    /// Steadies the brow in ARKit's face space when ARKit tracks the face in the same frame; the image-space smoother is the fallback.
    var browStabilizer=BrowFaceStabilizer()
    var browStabilized=false
    /// The latest brow MediaPipe found (steadied), with its raw landmarks: drawn on every ARKit frame until the next arrives.
    var browLatest:(observation:BrowObservation,raw:BrowObservation,stabilized:Bool,time:Double)?
    /// A live frame is waiting on the render queue; later camera frames are skipped until it is drawn, so they never queue up.
    var browDrawPending=false
    var lastBrowDraw:Double = -.infinity
    /// The 3D hair brow: its mesh on the GPU, and the ARKit face mesh drawn as depth only so far hairs hide behind the face.
    var hairBuffer:MTLBuffer?,hairLODBuffer:MTLBuffer?,hairVertexCount=0,hairLODVertexCount=0
    var faceMeshVertices:[MTLBuffer]=[],faceMeshIndices:MTLBuffer?,faceMeshIndexCount=0
    var browLight:Float=1
    var browFaceTriangles:[UInt16]=[]
    var browTexture:MTLTexture?,browTextureKey:String?
    var browVertices:[MTLBuffer]=[],browIndices:MTLBuffer?
    var browMarkBuffers:[MTLBuffer?]=[nil,nil,nil]
    /// Developer-menu values read from UserDefaults, refreshed at most every half second.
    var browDebugCache=0,browDebugRead:Double = -.infinity
    /// Camera colour attachments (pixel format, width, height as the key) and the `camera` uniform built from them.
    var browCameraKey:SIMD3<Int>?,browCamera=SIMD4<Float>.zero
    /// Stands in for the face-skin mask until one arrives: nothing occluded.
    var emptyMask:MTLTexture?
    /// Hides the natural brow (brow-space push-pull fill, optional MI-GAN); nil if its shaders are unavailable.
    var eraser:BrowEraser?
    /// Bound in place of the eraser's fill when there is none, so the brow strip always has a texture array.
    var emptyFill:MTLTexture?
    var browStatus:String?? = .none
    var style:BlushPlacementStyle?,anchorID:UUID?,frameTime:Double=0
    var visibility=BeautyBlushVisibility(),blushVisibility=BeautyBlushVisibility(),lastSegment:Double=0
    let segmenter=HandOcclusionSegmenter(faceSkinOnly:true)
    var segmentationTask:Task<Void,Never>?
    var segmentationStarting=false,latestMask:OcclusionMask?
    var lastMaskTime:Double = -1
    var reportStart=0.0,reportFrames=0,gpuTimes:[Double]=[],ages:[Double]=[]
    var onStatus:(@Sendable (String?)->Void)?
    /// The tracking view's per-frame readout (nil when the brow is not in tracking view).
    var onTracking:(@Sendable (BrowTrackingSnapshot?)->Void)?
    var browResultTimes:[Double]=[]
    var browTrackerSubmitted=0,browTrackerDropped=0
    /// Tracking diagnostics are developer-only; publishing them at camera
    /// rate causes SwiftUI to rebuild dozens of labels unnecessarily.
    var lastTrackingPublish:Double = -.infinity
    /// The brow tutorial's brow outlines (view-normalized), about 30 times a second while the guide is on.
    var onBrowGuide:(@Sendable (BrowGuideSnapshot?)->Void)?
    /// Where the tutorial's comparison cuts the picture: the face's midline (view-normalized x), so each half is one side of the
    /// face wherever the person stands.
    var onSplit:(@Sendable (CGFloat)->Void)?
    var splitX:CGFloat=0.5,splitSent:CGFloat=0.5
    @discardableResult func updateSplit(_ x:CGFloat)->CGFloat {
        let target=min(0.8,max(0.2,x));splitX += (target-splitX)*0.4
        if abs(splitX-splitSent)>0.002 {splitSent=splitX;onSplit?(splitX)}
        return splitX
    }
    var lastBrowGuidePublish:Double = -.infinity
    var browGuidePublished=false
    var lastError:String?
    var presentedFrames=0,pigmentFrames=0,projectionErrorPixels:Double=0
    var maskAgeMilliseconds:Double = -1
    /// Shows or hides the Metal layer. SceneKit's view under it keeps running at full rate: slowing it also slowed the ARKit
    /// frames the brow is drawn from.
    @MainActor func setLayerShown(_ shown:Bool) {layer?.isHidden = !shown}
    @MainActor static func make(on view:BeautyBlushARView) async->BeautyBlushEngine? {
        do {
            let engine=try await Task.detached(priority:.userInitiated) { try BeautyBlushEngine() }.value
            guard view.window != nil else{return nil}
            view.beautyLayer.device=engine.device;view.beautyLayer.pixelFormat = .bgra8Unorm_srgb
            // Colour-managed as sRGB like ARSCNView's camera; with no colour space iOS shows the bytes unmanaged.
            view.beautyLayer.colorspace=CGColorSpace(name:CGColorSpace.sRGB)
            // Not framebuffer-only: the shutter copies the shown picture (`readScreen`).
            view.beautyLayer.framebufferOnly=false;view.beautyLayer.isOpaque=true;view.beautyLayer.isHidden=true
            view.beautyLayer.actions=["bounds":NSNull(),"position":NSNull(),"contents":NSNull()]
            view.beautyLayer.maximumDrawableCount=3;view.layer.addSublayer(view.beautyLayer)
            engine.layer=view.beautyLayer;view.beauty=engine;view.setNeedsLayout();return engine
        } catch { UserDefaults.standard.set("setup_error: \(error)",forKey:"beautyBlush.status");return nil }
    }
    init() throws {
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
        wire=try pipeline("blushFaceVertex","blushWireFragment")
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
        browTracker.onResult={ [weak self] result in self?.queue.async { [weak self] in
            guard let self else{return}
            self.lock.lock();let brow=self.settings.isBrow;self.lock.unlock()
            if brow {self.renderBrow(result)} else {self.collectBlushLandmarks(result)}
        } }
    }
    func setViewport(_ size:CGSize,orientation:UIInterfaceOrientation) {lock.lock();settings.viewport=size;settings.orientation=orientation;lock.unlock()}
    @MainActor func configure(_ c:EyebrowConfiguration?) {
        let enabled=c.map { $0.previewAfter && ($0.layered ? ($0.browLayer.on || $0.blushLayer.on):(($0.needsBlush || $0.needsBrow) && $0.showMakeupPreview)) } ?? false
        lock.lock()
        // The brow path runs whenever the brow is on and draws the blush in the same frame when that is on too.
        let nextBrow=c.map {$0.needsBrow} ?? false
        let previousBlushStyle=settings.style
        let previousIsBrow=settings.isBrow,previousEnabled=settings.enabled
        if settings.isBrow != nextBrow || settings.enabled != enabled {
            settings.epoch=UUID();setLayerShown(false)
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
        if let c {
            settings.comparisonSplit=c.comparisonSplit;settings.browOnlySide=c.browOnlySide;settings.mappingSide=c.mappingSide;settings.pigmentHalf=c.pigmentHalf ?? (c.comparisonSplit ? .left:.full);settings.isBrow=c.needsBrow;settings.withBlush=c.needsBlush;settings.browStyle=c.style;settings.browOverlay=c.browOverlay
            settings.style=c.blushStyle;settings.guide=c.showGuide || c.measuresBlushTarget;settings.mapping=c.showMappingFormula;settings.tracking=c.browTrackingOverlay
            // TEMP (Khalish 2026-11-10): natural-brow eraser off; the brow picture is drawn straight over the real brow.
            // Restore: settings.hideNatural=c.hideNaturalBrow
            settings.hideNatural=false
            let browDefault=SIMD3<Float>(0.2,0.13,0.09),blushDefault=SIMD3<Float>(0.9,0.3,0.45)
            settings.tint=c.layered ? c.browLayer.tint ?? browDefault:c.shadeTint ?? browDefault
            settings.intensity=c.layered ? c.browLayer.intensity:c.previewIntensity
            settings.blushTint=c.layered ? c.blushLayer.tint ?? blushDefault:c.shadeTint ?? blushDefault
            settings.blushIntensity=c.layered ? c.blushLayer.intensity:c.previewIntensity
        }
        if !enabled {setLayerShown(false)}
        // Nothing of ours on screen (e.g. the eyeliner tab): release the face landmarker so it does not compete with the
        // eyeliner's own MediaPipe detector. It starts again with the brow or the blush.
        let stopTracker = !enabled && (browTracker.isAvailable || browTrackerStarting)
        if stopTracker {browTrackerStarting=false;browFrames=[:]}
        if enabled && nextBrow,let overlay=settings.browOverlay {BrowSpriteStore.shared.prepare(overlay);if overlay.is3D {BrowHairStore.shared.prepare()}}
        let start=enabled && !segmenter.isAvailable && !segmentationStarting
        if start {segmentationStarting=true}
        // Blush needs MediaPipe too, only until its cheek fit is measured (`submitBlushLandmarks`).
        let startTracker=enabled && !browTracker.isAvailable && !browTrackerStarting
        if startTracker {browTrackerStarting=true}
        lock.unlock()
        if stopTracker {browTrackerTask?.cancel();browTrackerTask=nil;browTracker.stop()}
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
            visibility=BeautyBlushVisibility();blushVisibility=BeautyBlushVisibility();frameTime=0;anchorID=nil;style=nil;lastError=nil;lastSegment=0
            browSmoother.reset();browStabilizer.reset();browStatus = .none;browLatest=nil;lastBrowDraw = -.infinity;lastTrackingPublish = -.infinity
            lock.lock()
            attemptedBlushStyle=nil;lastBindAttempt = -.infinity;atlas=nil;blushLandmarks=nil
            lock.unlock()
            blushSamples=[];blushSampleAnchor=nil;atlasFromLandmarks=false
            guideOutlines=[];if guidePublished {onBlushGuide?(nil);guidePublished=false}
        }
        onStatus?(nil);onTracking?(nil)
    }

    func submit(_ frame:ARFrame,face:ARFaceAnchor?) {
        lock.lock();let s=settings
        guard s.enabled,s.viewport.width>0,s.viewport.height>0 else {lock.unlock();return}
        if s.isBrow {lock.unlock();submitBrow(frame,settings:s);return}
        let measured=face.map {blushLandmarks?.anchor==$0.identifier} ?? true
        let start = !busy
        if start {busy=true}
        lock.unlock()
        if !measured && s.style.isReferenceLook {submitBlushLandmarks(frame,settings:s)}
        guard start else {return}
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
    static func affine(_ a:CGAffineTransform)->simd_float4x4 {
        simd_float4x4(columns:(SIMD4(Float(a.a),Float(a.b),0,0),SIMD4(Float(a.c),Float(a.d),0,0),SIMD4(0,0,1,0),SIMD4(Float(a.tx),Float(a.ty),0,1)))
    }
    func texture(_ buffer:CVPixelBuffer,plane:Int,format:MTLPixelFormat)->(CVMetalTexture,MTLTexture)? {
        guard let cache=textureCache else{return nil};var cv:CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,format,CVPixelBufferGetWidthOfPlane(buffer,plane),CVPixelBufferGetHeightOfPlane(buffer,plane),plane,&cv)==kCVReturnSuccess,let cv,let t=CVMetalTextureGetTexture(cv) else{return nil}
        return(cv,t)
    }
    func render(_ frame:ARFrame,face anchor:ARFaceAnchor?,settings s:Settings) {
        guard inFlight.wait(timeout:.now()) == .success else{return}
        var committed=false
        defer {if !committed {inFlight.signal()}}
        guard CVPixelBufferGetPlaneCount(frame.capturedImage)>=2,let (cy,y)=texture(frame.capturedImage,plane:0,format:.r8Unorm),let (cc,cb)=texture(frame.capturedImage,plane:1,format:.rg8Unorm),
              let drawable=layer?.nextDrawable(),let command=commands.makeCommandBuffer() else{return}
        let frameSlot=slot%3;slot += 1
        let size=CGSize(width:drawable.texture.width,height:drawable.texture.height)
        ensureDepth(for:drawable)
        let blush=prepareBlush(frame,face:anchor,settings:s,frameSlot:frameSlot,size:size,command:command)
        var u=blush.u
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        var splitPixels=drawable.texture.width/2
        if let anchor {
            // The split follows the nose, not the anchor's origin: that sits inside the head, so a turned face put the cut on
            // a cheek and let the other cheek's colour show across the nose. 5.5 cm forward in face space is about the nose.
            let nose=anchor.transform*SIMD4<Float>(0,0,0.055,1)
            let world=SIMD3(nose.x,nose.y,nose.z)
            let rawSize=CGSize(width:CVPixelBufferGetWidth(frame.capturedImage),height:CVPixelBufferGetHeight(frame.capturedImage))
            let rp=frame.camera.projectPoint(world,orientation:.landscapeRight,viewportSize:rawSize)
            let centre=CGPoint(x:rp.x/rawSize.width,y:rp.y/rawSize.height).applying(frame.displayTransform(for:s.orientation,viewportSize:s.viewport))
            splitPixels=Int(updateSplit(centre.x)*CGFloat(drawable.texture.width))
        }
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        // The camera fills the view in every comparison layout; only the pigment is limited to its half.
        let half=splitPixels
        switch s.pigmentHalf {
        case .none:break
        case .full:encodeBlush(blush,e)
        case .left:e.setScissorRect(MTLScissorRect(x:0,y:0,width:max(1,half),height:drawable.texture.height));encodeBlush(blush,e)
        case .right:e.setScissorRect(MTLScissorRect(x:half,y:0,width:max(1,drawable.texture.width-half),height:drawable.texture.height));encodeBlush(blush,e)
        }
        e.endEncoding()
        if let anchor {
            // The split follows the nose, not the anchor's origin: that sits inside the head, so a turned face put the cut on
            // a cheek and let the other cheek's colour show across the nose. 5.5 cm forward in face space is about the nose.
            let nose=anchor.transform*SIMD4<Float>(0,0,0.055,1)
            let world=SIMD3(nose.x,nose.y,nose.z)
            let rawSize=CGSize(width:CVPixelBufferGetWidth(frame.capturedImage),height:CVPixelBufferGetHeight(frame.capturedImage))
            let rp=frame.camera.projectPoint(world,orientation:.landscapeRight,viewportSize:rawSize)
            let normalized=CGPoint(x:rp.x/rawSize.width,y:rp.y/rawSize.height)
            let expected=normalized.applying(frame.displayTransform(for:s.orientation,viewportSize:s.viewport))
            let clip=blush.projection*blush.view*SIMD4(world,1)
            let actual=CGPoint(x:CGFloat(clip.x/clip.w)*0.5+0.5,y:0.5-CGFloat(clip.y/clip.w)*0.5)
            projectionErrorPixels=hypot((expected.x-actual.x)*s.viewport.width,(expected.y-actual.y)*s.viewport.height)
        }
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { [weak self] _ in self?.queue.async { [weak self] in self?.presentedFrames += 1 } }
        #endif
        copyForReaders(drawable.texture,command,frame:frame)
        command.present(drawable)
        let ts=frame.timestamp
        if blush.tracked && blush.opacity>0.9 {pigmentFrames += 1;lastError=nil}
        let retained=FrameLifetime(y:cy,cb:cc,frame:frame)
        let completionGate=inFlight
        command.addCompletedHandler { [weak self] cb in
            completionGate.signal()
            withExtendedLifetime(retained) {}
            Task { @MainActor [weak self] in
                guard let self else{return};self.lock.lock();let show=self.settings.enabled && self.settings.epoch==s.epoch;self.lock.unlock()
                if show {self.setLayerShown(true)}
            }
            self?.queue.async { [weak self] in self?.report(cb,frameTimestamp:ts,maskFresh:blush.fresh,visibility:blush.opacity,isBrow:false) }
        }
        committed=true;command.commit()
    }
    /// Uploads the latest face-skin mask into this frame slot's texture. Returns the texture, its camera-to-mask
    /// transform and whether the mask is fresh enough to draw pigment over.
    func uploadMask(slot frameSlot:Int,capturedImage:CVPixelBuffer,maxAge:Double)->(MTLTexture?,simd_float4x4,Bool) {
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
    func ensureDepth(for drawable:CAMetalDrawable) {
        if depthTexture?.width != drawable.texture.width || depthTexture?.height != drawable.texture.height {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:drawable.texture.width,height:drawable.texture.height,mipmapped:false);d.storageMode = .private;d.usage = .renderTarget;depthTexture=device.makeTexture(descriptor:d)
        }
    }

    var browFaceVisible=false,browMaskFresh=false
    func report(_ cb:MTLCommandBuffer,frameTimestamp:Double,maskFresh:Bool,visibility:Double,isBrow:Bool) {
        let now=CACurrentMediaTime();if reportStart==0 {reportStart=now}
        reportFrames += 1;gpuTimes.append(max(0,cb.gpuEndTime-cb.gpuStartTime)*1000);ages.append(max(0,now-frameTimestamp)*1000)
        guard now-reportStart>=2 else{return}
        let sorted=ages.sorted(),p95=sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]
        var report:[String:Any]=["engine":isBrow ? "mediapipe_metal":"arkit_metal_uv","category":isBrow ? "eyebrow":"blush","fps_completed":Double(reportFrames)/(now-reportStart),"fps_presented":Double(presentedFrames)/(now-reportStart),"pigment_frames":pigmentFrames,"projection_error_pixels":projectionErrorPixels,"gpu_ms_mean":gpuTimes.reduce(0,+)/Double(gpuTimes.count),"frame_age_ms_p95":p95,"thermal_state":ProcessInfo.processInfo.thermalState.rawValue,"mask_fresh":maskFresh,"mask_age_ms":maskAgeMilliseconds,"segmenter_available":segmenter.isAvailable,"visibility":visibility,"error":lastError ?? "none","shader_error":cb.error?.localizedDescription ?? "none"]
        if isBrow {
            lock.lock(); let trackerSubmitted = browTrackerSubmitted, trackerDropped = browTrackerDropped; browTrackerSubmitted = 0; browTrackerDropped = 0; lock.unlock()
            report["landmark_latency_ms"] = browTracker.lastLatencyMs
            report["brow_tracker_available"] = browTracker.isAvailable
            report["brow_stabilized"] = browStabilized
            report["tracker_submitted"] = trackerSubmitted
            report["tracker_dropped"] = trackerDropped
            if let eraser { let m = eraser.modelMetrics; report["eraser_model_requests"] = m.requests; report["eraser_model_latency_ms"] = m.latencyMs }
        }
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
            b.paint=SIMD4(placement.pigmentFields[0].curvature,placement.style.isReferenceLook ? 1:0,placement.pigmentFields.allSatisfy(\.wash) ? 1:0,0)
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
    /// `luma`/`chroma` replace the flat mid-grey camera (n*n and n*n*2 bytes); `transfer709` tags it like ARKit does.
    static func renderPixelFixture(obstructed:Bool,intensity:Float,atlasValue:UInt8=255,luma:[UInt8]?=nil,chroma:[UInt8]?=nil,
                                   blend:BlushBlend = .pigment,transfer709:Bool=false,shade:SIMD3<Float>=SIMD3(0.8,0.05,0.15),size:Int=32)throws->Data {
        let engine=try BeautyBlushEngine(),d=engine.device,n=size
        func texture(_ format:MTLPixelFormat,_ bytes:[UInt8],_ row:Int)throws->MTLTexture {
            let desc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:n,height:n,mipmapped:false)
            desc.usage=[.shaderRead,.renderTarget];desc.storageMode = .shared
            guard let t=d.makeTexture(descriptor:desc) else{throw CocoaError(.featureUnsupported)}
            bytes.withUnsafeBytes {t.replace(region:MTLRegionMake2D(0,0,n,n),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:row)}
            return t
        }
        let y=try texture(.r8Unorm,luma ?? Array(repeating:128,count:n*n),n)
        let cb=try texture(.rg8Unorm,chroma ?? Array(repeating:128,count:n*n*2),n*2)
        let mask=try texture(.r8Unorm,Array(repeating:obstructed ? 255:0,count:n*n),n)
        let atlas=try texture(.rgba8Unorm,Array(repeating:atlasValue,count:n*n*4),n*4)
        let target=try texture(.bgra8Unorm_srgb,Array(repeating:0,count:n*n*4),n*4)
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:n,height:n,mipmapped:false);dd.storageMode = .private;dd.usage = .renderTarget
        guard let z=d.makeTexture(descriptor:dd),let command=engine.commands.makeCommandBuffer() else{throw CocoaError(.featureUnsupported)}
        let positions:[SIMD3<Float>]=[.init(-0.8,-0.8,0.2),.init(0.8,-0.8,0.2),.init(0.8,0.8,0.2),.init(-0.8,0.8,0.2)]
        let points=positions.map {Vertex(position:SIMD4($0,1),rest:SIMD4($0,1),uv:SIMD4(($0.x+1)/2,($0.y+1)/2,0,0))}
        let tris:[UInt16]=[0,1,2,0,2,3]
        guard let vb=points.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}),let ib=tris.withUnsafeBytes({d.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}) else{throw CocoaError(.featureUnsupported)}
        var u=Uniforms(mvp:matrix_identity_float4x4,rawFromClip:matrix_identity_float4x4,maskFromRaw:matrix_identity_float4x4,shade:SIMD4(shade,intensity),controls:SIMD4(engine.config.coverage,engine.config.absorption,engine.config.saturation,engine.config.pigment_mix),tracking:SIMD4(1,0,1/Float(n),1/Float(n)),camera:SIMD4(1,1,transfer709 ? 1:0,0),stretch:SIMD4(0.45,0.7,1.45,1.85),
                       blush:SIMD4(Float(blend.rawValue),0,engine.config.detail_radius_px,0))
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

// -Nimah: the shutter's copy of the picture on screen (camera + virtual makeup). `ARSCNView.snapshot()` only has the
// SceneKit camera under this layer, so the desired-look photo lost the blush and brow.
/// What the engine presented, with the camera frame it was drawn from: the feedback measures the face on that same frame,
/// so its points sit on the photo's pixels even when the head moved during the shutter.
struct ScreenShot:@unchecked Sendable {
    let pixels:ScreenPixels
    let frame:ARFrame
    var face:ARFaceAnchor? {frame.anchors.lazy.compactMap {$0 as? ARFaceAnchor}.first(where:\.isTracked)}
}
final class ScreenReader:@unchecked Sendable {
    private let lock=NSLock();private var done=false;private let deliver:@Sendable (ScreenShot?)->Void
    init(_ deliver:@escaping @Sendable (ScreenShot?)->Void) {self.deliver=deliver}
    func finish(_ shot:ScreenShot?) {
        lock.lock();let first = !done;done=true;lock.unlock()
        if first {deliver(shot)}
    }
}
extension BeautyBlushEngine {
    /// The next picture this engine presents and its camera frame, or nil when it draws nothing within `timeout`.
    func readScreen(timeout:Double=1.5) async->ScreenShot? {
        await withCheckedContinuation { continuation in
            let reader=ScreenReader {continuation.resume(returning:$0)}
            lock.lock();screenReaders.append(reader);lock.unlock()
            DispatchQueue.global().asyncAfter(deadline:.now()+timeout) {reader.finish(nil)}
        }
    }
    /// Copies the drawable into CPU memory for waiting shutters, after the frame's drawing and before it is presented.
    /// `frame` is the camera frame this drawable was drawn from (held only while a shutter waits).
    func copyForReaders(_ texture:MTLTexture,_ command:MTLCommandBuffer,frame:ARFrame) {
        lock.lock();let readers=screenReaders;screenReaders=[];lock.unlock()
        guard !readers.isEmpty else{return}
        let width=texture.width,height=texture.height,row=width*4
        guard texture.pixelFormat == .bgra8Unorm_srgb || texture.pixelFormat == .bgra8Unorm,
              let buffer=device.makeBuffer(length:row*height,options:.storageModeShared),
              let blit=command.makeBlitCommandEncoder() else {readers.forEach {$0.finish(nil)};return}
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:width,height:height,depth:1),
                  to:buffer,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*height)
        blit.endEncoding()
        command.addCompletedHandler { _ in
            let bytes=Array(UnsafeBufferPointer(start:buffer.contents().assumingMemoryBound(to:UInt8.self),count:row*height))
            let shot=ScreenShot(pixels:ScreenPixels(width:width,height:height,bytesPerRow:row,bytes:bytes),frame:frame)
            readers.forEach {$0.finish(shot)}
        }
    }
}
