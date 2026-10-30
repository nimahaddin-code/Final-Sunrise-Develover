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
        var comparisonSplit=false;var enabled=false;var tint=SIMD3<Float>(0.9,0.3,0.45);var intensity:Float=0.72;var style=BlushPlacementStyle.cheekbone;var browStyle=EyebrowStyle.softNatural;var browOverlay:BrowOverlay?;var isBrow=false;var guide=false;var mapping=false;var tracking=false;var hideNatural=false;var viewport=CGSize.zero;var orientation=UIInterfaceOrientation.portrait;var epoch=UUID()
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
    var hairBuffer:MTLBuffer?,hairVertexCount=0
    var faceMeshVertices:[MTLBuffer]=[],faceMeshIndices:MTLBuffer?,faceMeshIndexCount=0
    var browLight:Float=1
    var browFaceTriangles:[UInt16]=[]
    var browTexture:MTLTexture?,browTextureKey:String?
    var browVertices:[MTLBuffer]=[],browIndices:MTLBuffer?
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
            view.beautyLayer.framebufferOnly=true;view.beautyLayer.isOpaque=true;view.beautyLayer.isHidden=true
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
            settings.comparisonSplit=c.comparisonSplit;settings.pigmentHalf=c.pigmentHalf ?? (c.comparisonSplit ? .left:.full);settings.isBrow=c.needsBrow;settings.withBlush=c.needsBlush;settings.browStyle=c.style;settings.browOverlay=c.browOverlay
            settings.style=c.blushStyle;settings.guide=c.showGuide;settings.mapping=c.showMappingFormula;settings.tracking=c.browTrackingOverlay;settings.hideNatural=c.hideNaturalBrow
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
            browSmoother.reset();browStabilizer.reset();browStatus = .none;browLatest=nil;lastBrowDraw = -.infinity
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
    static func affine(_ a:CGAffineTransform)->simd_float4x4 {
        simd_float4x4(columns:(SIMD4(Float(a.a),Float(a.b),0,0),SIMD4(Float(a.c),Float(a.d),0,0),SIMD4(0,0,1,0),SIMD4(Float(a.tx),Float(a.ty),0,1)))
    }
    func texture(_ buffer:CVPixelBuffer,plane:Int,format:MTLPixelFormat)->(CVMetalTexture,MTLTexture)? {
        guard let cache=textureCache else{return nil};var cv:CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,format,CVPixelBufferGetWidthOfPlane(buffer,plane),CVPixelBufferGetHeightOfPlane(buffer,plane),plane,&cv)==kCVReturnSuccess,let cv,let t=CVMetalTextureGetTexture(cv) else{return nil}
        return(cv,t)
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
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else{return}
        e.setRenderPipelineState(background);e.setDepthStencilState(noDepth);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:0);e.setFragmentTexture(y,index:0);e.setFragmentTexture(cb,index:1)
        e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        // The camera fills the view in every comparison layout; only the pigment is limited to its half.
        let half=drawable.texture.width/2
        switch s.pigmentHalf {
        case .none:break
        case .full:encodeBlush(blush,e)
        case .left:e.setScissorRect(MTLScissorRect(x:0,y:0,width:max(1,half),height:drawable.texture.height));encodeBlush(blush,e)
        case .right:e.setScissorRect(MTLScissorRect(x:half,y:0,width:max(1,drawable.texture.width-half),height:drawable.texture.height));encodeBlush(blush,e)
        }
        e.endEncoding()
        if let anchor {
            let world=SIMD3(anchor.transform.columns.3.x,anchor.transform.columns.3.y,anchor.transform.columns.3.z)
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
