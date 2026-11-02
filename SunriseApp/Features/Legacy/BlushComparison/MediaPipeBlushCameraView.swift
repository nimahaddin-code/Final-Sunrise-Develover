import CoreVideo
import QuartzCore
import SwiftUI
import UIKit

/// Transient AV camera sample, not an ARFrame. Estimated landmark depth is never metric.
struct BlushCameraSample:@unchecked Sendable {
    let capturedImage:CVPixelBuffer
    let timestamp:Double
    let display:CGAffineTransform
    let epoch:UUID
    static func displayTransform(raw:CGSize,viewport:CGSize)->CGAffineTransform {
        guard raw.width>0,raw.height>0,viewport.width>0,viewport.height>0 else{return .identity}
        let imageAspect=raw.width/raw.height,viewAspect=viewport.width/viewport.height
        let x=max(1,imageAspect/viewAspect),y=max(1,viewAspect/imageAspect)
        // Upright, unmirrored capture; mirror exactly once for front-camera preview.
        return CGAffineTransform(a:-x,b:0,c:0,d:y,tx:(1+x)/2,ty:(1-y)/2)
    }
}

struct MediaPipeBlushCameraView:UIViewRepresentable {
    let camera:FaceCameraState
    let configuration:EyebrowConfiguration
    let active:Bool
    func makeCoordinator()->Coordinator {Coordinator(camera:camera)}
    func makeUIView(context:Context)->ComparisonView {
        let view=ComparisonView();context.coordinator.view=view
        view.onLayout={ [weak coordinator=context.coordinator] size in coordinator?.engine?.setViewport(size,orientation:.portrait)}
        return view
    }
    func updateUIView(_ view:ComparisonView,context:Context) {
        context.coordinator.configuration=configuration
        context.coordinator.engine?.configure(active ? configuration:nil)
        if active {context.coordinator.start()} else {context.coordinator.stop()}
    }
    static func dismantleUIView(_ view:ComparisonView,coordinator:Coordinator) {coordinator.stop()}

    @MainActor final class ComparisonView:UIView {
        override class var layerClass:AnyClass {CAMetalLayer.self}
        var metal:CAMetalLayer {layer as! CAMetalLayer}
        var onLayout:((CGSize)->Void)?
        override func layoutSubviews() {
            super.layoutSubviews();let scale=window?.screen.scale ?? 2
            metal.drawableSize=CGSize(width:bounds.width*scale,height:bounds.height*scale)
            onLayout?(bounds.size)
        }
    }
    @MainActor final class Coordinator {
        weak var view:ComparisonView?
        let state:FaceCameraState
        let capture=EyeCameraSession(pixelFormat:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,preferredFPS:60)
        var engine:BeautyBlushEngine?
        var configuration=EyebrowConfiguration()
        private var task:Task<Void,Never>?
        init(camera:FaceCameraState) {state=camera}
        func start() {
            guard task==nil,let view else{return}
            let capture=self.capture
            task=Task { @MainActor [weak self,weak view] in
                guard let self,let view else{return}
                await self.state.trackingManager.beginExternalCamera(stop:{await capture.stopAndWait()})
                guard !Task.isCancelled else{return}
                if self.engine==nil {self.engine=await BeautyBlushEngine.makeComparison(on:view.metal)}
                guard !Task.isCancelled,let engine=self.engine else{return}
                engine.onStatus={ [weak state=self.state] message in Task { @MainActor in state?.update(\.beautyStatus,message)} }
                engine.onTracking={ [weak state=self.state] value in Task { @MainActor in
                    state?.update(\.tracked,value?.tracked ?? false)
                    if UserDefaults.standard.integer(forKey:BlushDiagnostic.key)==BlushDiagnostic.landmarks.rawValue {state?.browTracking.snapshot=value}
                } }
                engine.setViewport(view.bounds.size,orientation:.portrait);engine.configure(self.configuration)
                do {
                    try await capture.start { [weak engine] buffer,time in
                        engine?.submitMediaPipe(buffer,timestamp:time.seconds)
                    }
                    if Task.isCancelled {await capture.stopAndWait()}
                } catch {self.state.beautyStatus="MediaPipe camera unavailable: \(error)"}
            }
        }
        func stop() {
            task?.cancel();task=nil;engine?.pause();capture.stop()
            state.browTracking.snapshot=nil
        }
    }
}
