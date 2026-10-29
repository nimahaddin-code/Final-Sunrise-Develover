// MediaPipe brow path of the shared makeup engine (`BeautyBlushEngine`, which blush also draws with): frame rate and temperature limits, handing camera frames to MediaPipe and drawing its results.
// The engine's stored state, setup and shared camera/mask work stay in Features/BeautyBlush/BeautyBlushEngine.swift.
@preconcurrency import ARKit
@preconcurrency import MetalKit
import SwiftUI

extension BeautyBlushEngine {
    /// The brow (camera picture and brow together) is redrawn at most this often, so it is not redrawn on every 60 Hz camera frame.
    static let browMaxFramesPerSecond:Double=60
    /// How much brow work the phone's temperature allows. The brow tracker, the hand mask and the fill model share the GPU and
    /// Neural Engine; as the phone warms each is asked less often, and when it is hot the fill model stops (the push-pull fill
    /// still hides the natural brow).
    struct BrowLoad:Equatable {
        var trackerFPS:Double
        var maskInterval:Double
        /// Shortest time between fill-model requests; nil turns the model off.
        var modelInterval:Double?
        static func current(_ state:ProcessInfo.ThermalState)->BrowLoad {
            switch state {
            case .nominal:return BrowLoad(trackerFPS:browMaxFramesPerSecond,maskInterval:1.0/15,modelInterval:BrowEraser.modelInterval)
            case .fair:return BrowLoad(trackerFPS:40,maskInterval:1.0/10,modelInterval:0.5)
            default:return BrowLoad(trackerFPS:20,maskInterval:1.0/8,modelInterval:nil)
            }
        }
    }
    /// Whether a camera frame at `timestamp` is due, given the last one handed to MediaPipe: time is cut into 1/maxFPS slots and
    /// one frame is taken per slot, so a 60 Hz camera gives 40 fps at a 40 cap (two frames of every three), not the 30 a minimum
    /// interval would round down to. A frame almost a whole interval after the last is also due, so camera timing jitter at a
    /// 60 cap does not drop frames that land in the same slot.
    static func browFrameDue(timestamp:Double,last:Double,maxFPS:Double=browMaxFramesPerSecond)->Bool {
        guard last.isFinite else {return true}
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
    /// Hands this frame to MediaPipe unless one is still being processed; it is drawn when its landmarks return.
    func submitBrow(_ frame:ARFrame,settings s:Settings) {
        let load=BrowLoad.current(ProcessInfo.processInfo.thermalState)
        guard browTracker.isAvailable,!browTracker.isBusy,Self.browFrameDue(timestamp:frame.timestamp,last:lastBrowSubmit,maxFPS:load.trackerFPS) else {return}
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
            // Hand/fringe occlusion uses the same face-skin mask as blush (15 Hz, less when the phone is warm). Only the brow
            // shape and the hidden natural brow draw over the face, so only they need it.
            guard s.browOverlay != nil || s.hideNatural,entry.frame.timestamp-lastSegment>=load.maskInterval,!segmenter.isBusy,segmenter.isAvailable else {return}
            lastSegment=entry.frame.timestamp
            segmenter.submit(.init(pixelBuffer:SendablePixelBuffer(buffer:entry.frame.capturedImage),timestamp:entry.frame.timestamp,headUp:up,headAnchors:[]))
        }
    }
    func renderBrow(_ result:BrowTrackerResult) {
        lock.lock();let entry=browFrames.removeValue(forKey:result.token);let s=settings;lock.unlock()
        guard let entry,s.enabled,s.isBrow,s.epoch==entry.epoch,s.viewport.width>0,s.viewport.height>0 else {return}
        autoreleasepool {drawBrow(entry.frame,observation:result.observation,face:entry.face,settings:s)}
    }
}
