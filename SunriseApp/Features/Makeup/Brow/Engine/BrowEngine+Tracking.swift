// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): frame rate and temperature limits, handing camera frames to MediaPipe and drawing its results.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

extension BeautyBlushEngine {
    /// MediaPipe is paced separately from the camera compositor. Keeping the compositor at the camera's native rate
    /// avoids visible jumps between tracker results, while a 30 fps tracker budget leaves the shared GPU and Neural
    /// Engine enough time to draw each camera frame.
    static let browNominalTrackerFramesPerSecond:Double = 30
    /// How much brow work the phone's temperature allows. The brow tracker, the hand mask and the fill model share the GPU and
    /// Neural Engine; as the phone warms each is asked less often, and when it is hot the fill model stops (the push-pull fill
    /// still hides the natural brow).
    /// The camera session and compositor stay at their native rate. MediaPipe is deliberately capped so it cannot
    /// starve the compositor and cause the applied brow to stutter.
    struct BrowLoad:Equatable {
        var trackerFPS:Double?
        var drawFPS:Double?
        var maskInterval:Double
        /// Shortest time between fill-model requests; nil turns the model off.
        var modelInterval:Double?
        static func current(_ state:ProcessInfo.ThermalState)->BrowLoad {
            switch state {
            case .nominal:return BrowLoad(trackerFPS:browNominalTrackerFramesPerSecond,drawFPS:nil,maskInterval:1.0/15,modelInterval:BrowEraser.modelInterval)
            case .fair:return BrowLoad(trackerFPS:30,drawFPS:nil,maskInterval:1.0/10,modelInterval:0.5)
            default:return BrowLoad(trackerFPS:15,drawFPS:30,maskInterval:1.0/8,modelInterval:nil)
            }
        }
    }
    /// Whether a camera frame at `timestamp` is due, given the last one taken: time is cut into 1/maxFPS slots and
    /// one frame is taken per slot, so a 60 Hz camera gives 40 fps at a 40 cap (two frames of every three), not the 30 a minimum
    /// interval would round down to. A frame almost a whole interval after the last is also due, so camera timing jitter at a
    /// 60 cap does not drop frames that land in the same slot.
    static func browFrameDue(timestamp:Double,last:Double,maxFPS:Double?=nil)->Bool {
        guard let maxFPS,last.isFinite else {return true}
        return (timestamp*maxFPS+1e-6).rounded(.down)>(last*maxFPS+1e-6).rounded(.down) || timestamp-last>=0.9/maxFPS
    }
    /// The face ARKit tracked in this very frame, for steadying the brow in face space; nil when ARKit has none.
    func browFaceFrame(_ frame:ARFrame)->BrowFaceFrame? {
        guard case .normal=frame.camera.trackingState,let anchor=frame.anchors.compactMap({$0 as? ARFaceAnchor}).first(where:{$0.isTracked}) else {return nil}
        let geometry=anchor.geometry
        if browFaceTriangles.count != geometry.triangleIndices.count {browFaceTriangles=geometry.triangleIndices.map {UInt16(bitPattern:$0)}}
        let resolution=frame.camera.imageResolution
        return BrowFaceFrame(anchorID:anchor.identifier,vertices:geometry.vertices,triangles:browFaceTriangles,intrinsics:frame.camera.intrinsics,
                             imageSize:SIMD2(Float(resolution.width),Float(resolution.height)),faceToWorld:anchor.transform,cameraToWorld:frame.camera.transform)
    }
    /// Every camera frame: drawn now with the latest brow (moved by ARKit's face pose), like blush is drawn on every ARKit frame,
    /// and handed to MediaPipe when one is due, which only updates the brow. The camera picture no longer waits for MediaPipe.
    func submitBrow(_ frame:ARFrame,settings s:Settings) {
        let load=BrowLoad.current(ProcessInfo.processInfo.thermalState)
        let face=browFaceFrame(frame)
        drawLiveBrow(frame,face:face,settings:s,maxFPS:load.drawFPS)
        guard browTracker.isAvailable,!browTracker.isBusy,Self.browFrameDue(timestamp:frame.timestamp,last:lastBrowSubmit,maxFPS:load.trackerFPS) else {
            lock.lock(); browTrackerDropped += 1; lock.unlock()
            return
        }
        let (entry,up,_)=submitToBrowTracker(frame,face:face,settings:s)
        lock.lock(); browTrackerSubmitted += 1; lock.unlock()
        queue.async { [self] in
            // Hand/fringe occlusion uses the same face-skin mask as blush (15 Hz, less when the phone is warm). Only the brow
            // shape and the hidden natural brow draw over the face, so only they need it.
            guard s.browOverlay != nil || s.hideNatural,entry.frame.timestamp-lastSegment>=load.maskInterval,!segmenter.isBusy,segmenter.isAvailable else {return}
            lastSegment=entry.frame.timestamp
            segmenter.submit(.init(pixelBuffer:SendablePixelBuffer(buffer:entry.frame.capturedImage),timestamp:entry.frame.timestamp,headUp:up,headAnchors:[]))
        }
    }
    /// Hands one camera frame to MediaPipe (brow, or the blush cheek fit) and keeps it until the answer returns. Returns the kept
    /// frame, the screen's up direction in the captured image and whether the tracker took it.
    @discardableResult func submitToBrowTracker(_ frame:ARFrame,face:BrowFaceFrame?,settings s:Settings)->(entry:BrowFrame,up:CGPoint,accepted:Bool) {
        let buffer=frame.capturedImage
        let raw=CGSize(width:CVPixelBufferGetWidth(buffer),height:CVPixelBufferGetHeight(buffer))
        // The screen's up and across directions in the captured image pick the detector's rotation; no face tracker.
        let toRaw=frame.displayTransform(for:s.orientation,viewportSize:s.viewport).inverted()
        func direction(_ a:CGPoint,_ b:CGPoint)->CGPoint {
            let p=a.applying(toRaw),q=b.applying(toRaw)
            return CGPoint(x:(q.x-p.x)*raw.width,y:(q.y-p.y)*raw.height)
        }
        let up=direction(CGPoint(x:0.5,y:0.6),CGPoint(x:0.5,y:0.4)),across=direction(CGPoint(x:0.4,y:0.5),CGPoint(x:0.6,y:0.5))
        let entry=BrowFrame(frame:frame,epoch:s.epoch,face:face)
        lock.lock()
        browToken += 1;let token=browToken;lastBrowSubmit=frame.timestamp
        browFrames=browFrames.filter {token-$0.key<2};browFrames[token]=entry
        lock.unlock()
        guard browTracker.submit(BrowTrackerInput(pixelBuffer:SendablePixelBuffer(buffer:buffer),timestamp:frame.timestamp,headUp:up,headAcross:across,token:token)) else {
            lock.lock();browFrames[token]=nil;lock.unlock();return (entry,up,false)
        }
        return (entry,up,true)
    }
    /// A MediaPipe answer (render queue): steadies it in its own frame and keeps it as the brow the live frames draw.
    func renderBrow(_ result:BrowTrackerResult) {
        lock.lock();let entry=browFrames.removeValue(forKey:result.token);let s=settings;lock.unlock()
        guard let entry,s.enabled,s.isBrow,s.epoch==entry.epoch else {return}
        // With the blush on too, the same answers measure its cheek fit.
        if s.withBlush,let detected=result.observation {addBlushSample(detected,face:entry.face)}
        guard let detected=result.observation else {
            browSmoother.reset();browStabilizer.reset();browStabilized=false;browLatest=nil;return
        }
        if let face=entry.face,let steady=browStabilizer.stabilize(detected,face:face) {
            browSmoother.reset();browStabilized=true
            browLatest=(steady,detected,true,entry.frame.timestamp)
        } else {
            browStabilizer.reset();browStabilized=false
            browLatest=(browSmoother.smooth(detected),detected,false,entry.frame.timestamp)
        }
    }
    /// How long the last MediaPipe answer is drawn without a newer one (a lost face, a stalled tracker).
    static let browLatestMaxAge:Double=0.5
    /// Draws one live camera frame on the render queue with the latest brow. Skipped while a frame is still waiting there, and
    /// limited to `maxFPS`, so a slow GPU drops frames instead of falling behind the camera.
    func drawLiveBrow(_ frame:ARFrame,face:BrowFaceFrame?,settings s:Settings,maxFPS:Double?) {
        lock.lock()
        guard !browDrawPending,Self.browFrameDue(timestamp:frame.timestamp,last:lastBrowDraw,maxFPS:maxFPS) else {lock.unlock();return}
        browDrawPending=true;lastBrowDraw=frame.timestamp
        lock.unlock()
        queue.async { [self] in
            defer {lock.lock();browDrawPending=false;lock.unlock()}
            lock.lock();let current=settings.enabled && settings.isBrow && settings.epoch==s.epoch;lock.unlock()
            guard current,s.viewport.width>0,s.viewport.height>0 else {return}
            var observation:BrowObservation?,raw:BrowObservation?
            if let latest=browLatest,frame.timestamp-latest.time<Self.browLatestMaxAge {
                // Moved onto this frame by ARKit's pose when it was steadied on the face; otherwise drawn where it was seen.
                observation=latest.stabilized ? face.flatMap {browStabilizer.reproject(latest.observation,onto:$0)} ?? latest.observation:latest.observation
                raw=latest.raw
            }
            autoreleasepool {drawBrow(frame,observation:observation,raw:raw,face:face,settings:s)}
        }
    }
}
