// -Nimah: Native depth + pigmen vertex dan strip attachment; tidak ada atlas pada makeup live.
import SwiftUI
import ARKit
import SceneKit
import Metal

struct LiveGuideView: UIViewRepresentable {
    @ObservedObject var camera: FaceCameraState
    let referenceID: String
    let active: Bool
    // -Nimah: Region configuration memungkinkan modul lain memakai foundation sesi yang sama.
    var eyebrowConfiguration: EyebrowConfiguration? = nil
    // Called on the session queue for every frame with a tracked face, so another overlay can share this camera.
    var onFrame: (@Sendable (ARFrame, ARFaceAnchor) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera, referenceID: referenceID, manager:camera.trackingManager) }
    func makeUIView(context: Context) -> ARSCNView {
        let view=BeautyBlushARView(frame:.zero)
        view.session=camera.trackingManager.session
        view.scene=SCNScene(); view.delegate=context.coordinator
        view.preferredFramesPerSecond=60
        view.rendersContinuously=true; view.isJitteringEnabled=false
        view.antialiasingMode = .multisampling4X
        view.automaticallyUpdatesLighting=false
        Task { [weak view,coordinator=context.coordinator] in
            guard let view else{return}
            if let beauty=await BeautyBlushEngine.make(on:view) {coordinator.installBeauty(beauty)} else {coordinator.camera.beautyStatus=String(localized:"Blush renderer is unavailable")}
        }
        camera.view=view
        camera.stopSession = { [weak coordinator=context.coordinator, weak view] in if let view { coordinator?.pause(view) } }
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.configure(visible:camera.overlay && active, step:camera.guideStep, mode:camera.previewMode,
            fullLook:camera.previewFullLook, strength:camera.previewStrength, previous:camera.showPreviousSteps,
            style:camera.eyelinerStyle, debug:camera.debugMode, eyebrows:eyebrowConfiguration)
        context.coordinator.configureBeauty(eyebrowConfiguration,visible:camera.overlay && active)
        context.coordinator.setFrameHandler(onFrame)
        if active && camera.authorized && camera.failure == nil { context.coordinator.start(view) }
        else { context.coordinator.pause(view) }
    }
    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.pause(view)
        coordinator.detach(view)
        view.delegate=nil
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, @unchecked Sendable {
        let queue=DispatchQueue(label:"sunrise.face-session")
        private let fitQueue=DispatchQueue(label:"sunrise.face-surface-fit",qos:.userInitiated)
        fileprivate let camera: FaceCameraState
        private let manager: ARFaceTrackingManager
        private let leaseID=UUID()
        private let eyebrowPipeline=EyebrowTrackingPipeline()
        private let referenceID: String
        private let lock=NSLock()
        private var settings=Settings()
        private var beauty:BeautyBlushEngine?
        @MainActor func installBeauty(_ engine:BeautyBlushEngine) {
            engine.onStatus={ [weak camera] message in Task { @MainActor in camera?.update(\.beautyStatus,message) } }
            engine.onTracking={ [weak feed=camera.browTracking] snapshot in Task { @MainActor in feed?.snapshot=snapshot } }
            lock.lock();beauty=engine;lock.unlock()
            let s=snapshot().0;lock.lock();let active=sessionActive;lock.unlock();engine.configure(s.visible && active ? s.eyebrows:nil)
        }
        @MainActor func configureBeauty(_ config:EyebrowConfiguration?,visible:Bool) {
            lock.lock();let engine=beauty;lock.unlock();engine?.configure(visible ? config:nil)
        }
        private var frameHandler: (@Sendable (ARFrame, ARFaceAnchor) -> Void)?
        private var tracked=false, fitAllowed=false
        private var generation=UUID()
        private var sessionActive=false
        private var activeAnchorID: UUID?
        private var lastFrameArrival: TimeInterval=0
        private struct StyleResult { let style: EyelinerStyle; let region: EyelinerRegion }
        private var pendingStyles: [UUID:StyleResult]=[:]
        private var pending: (id:UUID, profile:SurfaceRenderProfile)?
        // -Nimah: running/desiredRunning hanya MainActor; readiness/pose hanya session queue.
        private var running=false, desiredRunning=false
        /// Another screen took the camera lease. This screen must not take it back until it has been paused: two screens that
        /// are both active during a push (Try On under the tutorial) would otherwise hand the camera back and forth, each time
        /// publishing from a view update, until the app stops responding.
        private var revoked=false
        private var readiness=TrackingReadiness()
        private var previousPosition: SIMD3<Float>?
        private var previousRotation: simd_quatf?
        private var lastReport: TimeInterval=0
        private var fitStable=false
        // -Nimah: Render-state dan node hanya diakses melalui callback renderer SceneKit.
        private var faces: [UUID:RenderFace]=[:]
        private struct Settings {
            var visible=false
            var step: TutorialStep = .blush
            var mode: MakeupPreviewMode = .pointsAndLook
            var fullLook=false
            var previous=false
            var style=EyelinerStyle()
            var debug: LiveGuideDebugMode = .off
            var strength: Float=0.8
            var eyebrows: EyebrowConfiguration?
        }
        private final class RenderFace {
            let depth: ARSCNFaceGeometry
            let depthNode: SCNNode
            let makeupNode: SCNNode
            let dots=SCNNode()
            let eyebrowRenderer=EyebrowSceneRenderer()
            let previewRenderer=FaceRegionPreviewRenderer()
            let blushPreviewRenderer=FaceRegionPreviewRenderer()
            let foreheadRenderer=ForeheadSceneRenderer()
            let blushRenderer=ForeheadSceneRenderer()
            let trackingDots=FaceTrackingDotsRenderer()
            let diagnostic: ARSCNFaceGeometry
            let diagnosticNode: SCNNode
            let labels=SCNNode()
            let eyelinerRoot=SCNNode()
            var eyeliner: EyelinerRegion?
            var eyelinerNodes: [SCNNode]=[]
            var eyelinerDots: [SCNNode]=[]
            var eyelinerStyle: EyelinerStyle?
            var styleJobInFlight=false
            var lastMessage: String?
            var generation=UUID()
            var debugMode: LiveGuideDebugMode = .off
            let material=SCNMaterial()
            var profile: SurfaceRenderProfile?
            var fitRequested=false
            var reported=false
            var drawnStep: TutorialStep?
            var colorKey: String?
            var colorSource: SCNGeometrySource?
            // The face mesh topology never changes, so it is copied once, not on every rendered frame.
            var triangles: [Int16]?
            init?(device: MTLDevice) {
                guard let depth=ARSCNFaceGeometry(device:device,fillMesh:false), let diagnostic=ARSCNFaceGeometry(device:device,fillMesh:false) else { return nil }
                self.depth=depth
                self.diagnostic=diagnostic; diagnosticNode=SCNNode(geometry:diagnostic)
                let debugMaterial=EyelinerRenderer.material(tint:.cyan)
                debugMaterial.fillMode = .lines; diagnostic.materials=[debugMaterial]
                diagnosticNode.renderingOrder=3; diagnosticNode.position.z=0.0008
                diagnosticNode.isHidden=true
                eyelinerRoot.renderingOrder=2; labels.renderingOrder=10
                depthNode=SCNNode(geometry:depth); makeupNode=SCNNode()
                let occluder=SCNMaterial(); occluder.colorBufferWriteMask=[]; occluder.writesToDepthBuffer=true
                occluder.isDoubleSided=false; depth.materials=[occluder]; depthNode.renderingOrder = -10
                // -Nimah: Alpha vertex menyisakan kulit asli di luar area makeup.
                material.lightingModel = .constant; material.blendMode = .alpha
                material.transparencyMode = .aOne
                material.writesToDepthBuffer=false; material.readsFromDepthBuffer=true
                material.isDoubleSided=false
                makeupNode.renderingOrder=0
                makeupNode.position.z=0.0006; makeupNode.isHidden=true
                dots.renderingOrder=10
            }
        }
        @MainActor init(camera:FaceCameraState,referenceID:String,manager:ARFaceTrackingManager) {
            self.camera=camera; self.referenceID=referenceID; self.manager=manager
        }
        func configure(visible:Bool,step:TutorialStep,mode:MakeupPreviewMode,fullLook:Bool,strength:Float,previous:Bool,style:EyelinerStyle,debug:LiveGuideDebugMode,eyebrows:EyebrowConfiguration?) {
            lock.lock(); defer { lock.unlock() }
            settings.visible=visible; settings.step=step; settings.mode=mode
            settings.fullLook=fullLook; settings.strength=max(0,min(1,strength))
            settings.previous=previous; settings.style=style.clamped; settings.debug=debug; settings.eyebrows=eyebrows
        }
        func setFrameHandler(_ handler: (@Sendable (ARFrame, ARFaceAnchor) -> Void)?) { lock.lock(); frameHandler=handler; lock.unlock() }
        private func snapshot() -> (Settings,Bool,Bool,UUID) {
            lock.lock(); defer { lock.unlock() }; return (settings,sessionActive && tracked && ProcessInfo.processInfo.systemUptime-lastFrameArrival<0.35,fitAllowed,generation)
        }
        private func isCurrent(_ value: UUID, anchorID: UUID? = nil) -> Bool {
            lock.lock(); defer { lock.unlock() }; return sessionActive && generation==value && (anchorID == nil || activeAnchorID==anchorID)
        }
        private func setTracking(_ value:Bool,canFit:Bool) { lock.lock(); tracked=value && sessionActive; fitAllowed=canFit && sessionActive; lastFrameArrival=ProcessInfo.processInfo.systemUptime; lock.unlock() }
        @MainActor func start(_ view:ARSCNView) {
            desiredRunning=true
            guard !running,!revoked,ARFaceTrackingConfiguration.isSupported else { return }
            manager.acquire(owner:leaseID) { [weak self] in
                guard let self else { return }
                self.desiredRunning=false; self.running=false; self.revoked=true; self.invalidateSession(); self.camera.suspend()
                if let oldView=self.camera.view {self.detach(oldView)}
            }
            if view.session !== manager.session {view.session=manager.session}
            view.session.delegate=self; view.session.delegateQueue=queue
            view.rendersContinuously=true
            running=true
            eyebrowPipeline.reset()
            // Each camera session fits the face in front of it.
            LaunchMakeupFit.shared.clear()
            lock.lock(); generation=UUID(); pending=nil; pendingStyles=[:]; activeAnchorID=nil; sessionActive=true; tracked=false; fitAllowed=false; lock.unlock()
            camera.update(\.fitReady,false); camera.update(\.fitMessage,"Look straight ahead with relaxed eyes and lips while the surface is fitted")
            queue.async { self.readiness.reset(); self.previousPosition=nil; self.previousRotation=nil; self.lastReport=0; self.fitStable=false }
            let configuration=ARFaceTrackingConfiguration(); configuration.maximumNumberOfTrackedFaces=1
            view.session.run(configuration,options:[.resetTracking,.removeExistingAnchors])
        }
        // A retained navigation screen must not keep an ARSCNView attached to another screen's session.
        @MainActor func detach(_ view:ARSCNView) {
            if view.session === manager.session {view.session=ARSession()}
        }
        @MainActor func pause(_ view:ARSCNView) {
            revoked=false
            // A paused screen under another one (Try On below the tutorial) must not keep drawing, or retaining, camera frames.
            view.rendersContinuously=false
            lock.lock();let engine=beauty;lock.unlock();engine?.pause()
            desiredRunning=false; setTracking(false,canFit:false)
            lock.lock(); generation=UUID(); pending=nil; pendingStyles=[:]; activeAnchorID=nil; sessionActive=false; lock.unlock()
            eyebrowPipeline.reset()
            guard running || manager.owns(leaseID) else { detach(view); return }
            manager.release(owner:leaseID); running=false; camera.suspend()
            detach(view)
        }
        func renderer(_ renderer:SCNSceneRenderer,nodeFor anchor:ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor,let device=renderer.device,let face=RenderFace(device:device) else { return nil }
            let root=SCNNode(); root.isHidden=true
            root.addChildNode(face.eyebrowRenderer.root)
            root.addChildNode(face.foreheadRenderer.root)
            root.addChildNode(face.blushRenderer.root)
            root.addChildNode(face.previewRenderer.root); root.addChildNode(face.blushPreviewRenderer.root); root.addChildNode(face.trackingDots.root)
            root.addChildNode(face.depthNode); root.addChildNode(face.makeupNode); root.addChildNode(face.dots)
            root.addChildNode(face.eyelinerRoot); root.addChildNode(face.diagnosticNode); root.addChildNode(face.labels)
            face.generation=snapshot().3
            lock.lock(); activeAnchorID=anchor.identifier; lock.unlock()
            eyebrowPipeline.reset(anchorID:anchor.identifier)
            faces[anchor.identifier]=face
            return root
        }
        func renderer(_ renderer:SCNSceneRenderer,didUpdate node:SCNNode,for anchor:ARAnchor) {
            guard let anchor=anchor as? ARFaceAnchor,let face=faces[anchor.identifier] else { return }
            let (options,trackingOK,canFit,jobGeneration)=snapshot()
            let anchorID=anchor.identifier
            guard face.generation==jobGeneration && isCurrent(jobGeneration,anchorID:anchorID) else { node.isHidden=true; return }
            if let configuration=options.eyebrows {
                renderEyebrows(face,node:node,anchor:anchor,configuration:configuration,trackingOK:trackingOK,visible:options.visible)
                return
            }
            lock.lock()
            if let ready=pending,ready.id==anchor.identifier { face.profile=ready.profile; pending=nil }
            lock.unlock()
            if face.profile==nil && !face.fitRequested && canFit {
                // -Nimah: Fit/attachment bekerja sekali di worker queue saat ekspresi netral, bukan tiap frame.
                let vertices=Array(anchor.geometry.vertices), triangles=Array(anchor.geometry.triangleIndices)
                face.fitRequested=true
                let left=anchor.leftEyeTransform.columns.3, right=anchor.rightEyeTransform.columns.3
                let eyes=[SIMD3(left.x,left.y,left.z),SIMD3(right.x,right.y,right.z)]
                let id=anchor.identifier
                fitQueue.async {
                    let profile=FaceSurfaceProfile.make(vertices:vertices,triangles:triangles,eyeCenters:eyes)
                        .map { SurfaceRenderProfile(surface:$0,vertices:vertices,triangles:triangles) }
                    self.lock.lock()
                    let current=self.sessionActive && self.generation==jobGeneration && self.activeAnchorID==id
                    if current,let profile { self.pending=(id,profile) }
                    self.lock.unlock()
                    if current && profile==nil { Task { @MainActor in guard self.isCurrent(jobGeneration,anchorID:anchorID) else { return }; self.camera.fitMessage="Surface fit unavailable. Retry with your face centered, or use manual mode." } }
                }
            }
            if let profile=face.profile, !face.reported {
                face.reported=true
                Task { @MainActor in
                    guard self.isCurrent(jobGeneration,anchorID:anchorID) else { return }
                    if !self.camera.fitReady { self.camera.fitReady=true; self.camera.fitMessage=profile.surface.status }
                }
            }
            let applicable=referenceID=="sculpted-glam" || options.step == .blush
            node.isHidden = !anchor.isTracked || !trackingOK || !options.visible || options.mode == .original || !applicable || face.profile==nil
            guard !node.isHidden, let profile=face.profile else { return }
            SCNTransaction.begin(); SCNTransaction.disableActions=true
            // -Nimah: Geometri native dipakai ulang; transform pose tetap milik ARKit.
            face.depth.update(from:anchor.geometry)
            // -Nimah: Satu scope eksplisit untuk warna dan panduan. Tidak ada full look default.
            let selected=MakeupLayerSelection.layers(step:options.step,fullLook:options.fullLook && referenceID=="sculpted-glam",previous:options.previous)
            let eyesOpen=(anchor.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0)<0.5 && (anchor.blendShapes[.eyeBlinkRight]?.floatValue ?? 0)<0.5
            let mouthClosed=(anchor.blendShapes[.jawOpen]?.floatValue ?? 0)<0.25
            let expressionSafe=(!selected.contains(.eyeshadow) || eyesOpen) && (!selected.contains(.lips) || mouthClosed)
            face.makeupNode.isHidden = !options.mode.showsMakeup || selected.allSatisfy { $0 == .eyeliner } || !expressionSafe
            let full=options.fullLook && referenceID=="sculpted-glam"
            let key=full ? "full" : options.step.rawValue+(options.previous ? "-previous" : "")
            if face.colorKey != key {
                // -Nimah: Warna mengikuti ID vertex, persis seperti titik; tidak ada sampling atlas.
                face.colorSource=SurfaceMakeupRenderer.colorSource(SurfaceMakeupRenderer.colors(surface:profile.surface,steps:selected,referenceID:referenceID))
                face.material.diffuse.contents=UIColor.white
                face.colorKey=key
            }
            if let source=face.colorSource {
                face.makeupNode.geometry=SurfaceMakeupRenderer.geometry(vertices:Array(anchor.geometry.vertices),triangles:profile.triangles,colorSource:source,material:face.material)
            }
            face.material.transparency=CGFloat(options.strength)
            face.dots.isHidden = !options.mode.showsPoints || options.step == .eyeliner || !expressionSafe
            let indices=profile.surface.guides[options.step] ?? []
            if face.drawnStep != options.step {
                face.dots.childNodes.forEach { $0.removeFromParentNode() }
                for _ in indices { face.dots.addChildNode(makeDot()) }
                face.drawnStep=options.step
            }
            for (dot,index) in zip(face.dots.childNodes,indices) where index < anchor.geometry.vertices.count {
                let vertex=anchor.geometry.vertices[index]
                dot.position=SCNVector3(vertex.x,vertex.y,vertex.z+0.0014)
            }
            updateEyeliner(face,anchor:anchor,profile:profile,options:options,selected:selected)
            updateDebug(face,anchor:anchor,options:options)
            let status: String
            if selected.contains(.eyeliner) { status=face.eyeliner?.reason ?? "Eyeliner not fitted" }
            else { status="\(options.step.title) · experimental surface estimate; device validation pending" }
            let expressionNote=selected.contains(.eyeliner) && !eyesOpen ? " · blinking eye hidden" : (!expressionSafe ? " · color layer hidden during expression" : "")
            let styleNote=selected.contains(.eyeliner) && face.eyelinerStyle != options.style ? " · updating style" : ""
            let message=(full ? "Full look preview · " : "Tutorial · ")+status+expressionNote+styleNote
            if face.lastMessage != message {
                face.lastMessage=message
                Task { @MainActor in
                    guard self.isCurrent(jobGeneration,anchorID:anchorID) else { return }
                    self.camera.renderMessage=message
                }
            }
            SCNTransaction.commit()
        }
        // -Nimah: Modul eyebrow hanya merender guide, tanpa makeup/atlas atau sesi kamera tambahan.
        private func renderEyebrows(_ face:RenderFace,node:SCNNode,anchor:ARFaceAnchor,configuration:EyebrowConfiguration,trackingOK:Bool,visible:Bool) {
            node.isHidden = !anchor.isTracked || !trackingOK || !visible
            guard !node.isHidden else { return }
            SCNTransaction.begin(); SCNTransaction.disableActions=true
            face.makeupNode.isHidden=true; face.dots.isHidden=true; face.eyelinerRoot.isHidden=true; face.labels.isHidden=true
            face.depth.update(from:anchor.geometry)
            let result=eyebrowPipeline.snapshot(style:configuration.style,foreheadStyle:(configuration.region == .forehead || configuration.showAllRegions) ? configuration.foreheadStyle : nil,height:configuration.foreheadHeight,includeBrow:configuration.needsBrow,blushStyle:configuration.needsBlush ? configuration.blushStyle : nil)
            let vertices=Array(anchor.geometry.vertices)
            // The Metal engine draws the brow, its guide and mapping lines from MediaPipe landmarks; the mesh guide is
            // only the fallback when Metal is unavailable.
            lock.lock();let metalBrow=beauty != nil;lock.unlock()
            face.eyebrowRenderer.update(guide:configuration.needsBrow && !metalBrow ? result.guide : nil,vertices:vertices,configuration:configuration)
            face.foreheadRenderer.update(guide:result.foreheadGuide,vertices:vertices,configuration:configuration)
            face.blushRenderer.update(blush:result.blushGuide,vertices:vertices,configuration:configuration)
            if face.triangles == nil { face.triangles=Array(anchor.geometry.triangleIndices) }
            let triangles=face.triangles ?? []
            if configuration.layered {
                // Home screen: brow and blush previews are separate layers with their own shade and strength.
                var brow=configuration; brow.region = .eyebrows; brow.showMakeupPreview=configuration.browLayer.on
                brow.previewIntensity=configuration.browLayer.intensity; brow.shadeTint=configuration.browLayer.tint
                var blush=configuration; blush.region = .blush; blush.showMakeupPreview=configuration.blushLayer.on
                blush.previewIntensity=configuration.blushLayer.intensity; blush.shadeTint=configuration.blushLayer.tint
                lock.lock();let usesBeauty=beauty != nil;lock.unlock()
                if usesBeauty {brow.showMakeupPreview=false}
                face.previewRenderer.update(brow:result.guide,forehead:nil,vertices:vertices,triangles:triangles,configuration:brow)
                if usesBeauty {blush.showMakeupPreview=false}
                face.blushPreviewRenderer.update(brow:nil,forehead:nil,blush:result.blushGuide,vertices:vertices,triangles:triangles,configuration:blush)
            } else {
                var preview=configuration
                lock.lock();let usesBeauty=beauty != nil;lock.unlock()
                if usesBeauty && (preview.region == .blush || preview.region == .eyebrows) {preview.showMakeupPreview=false}
                face.previewRenderer.update(brow:result.guide,forehead:result.foreheadGuide,blush:result.blushGuide,vertices:vertices,triangles:triangles,configuration:preview)
            }
            face.trackingDots.update(vertices:vertices,visible:configuration.showTrackingPoints)
            face.diagnosticNode.isHidden = !configuration.debugMesh
            if configuration.debugMesh {
                face.diagnostic.update(from:anchor.geometry)
                if face.diagnostic.firstMaterial?.fillMode != .lines {
                    let material=EyelinerRenderer.material(tint:.cyan); material.fillMode = .lines; face.diagnostic.materials=[material]
                }
            }
            SCNTransaction.commit()
        }
        // -Nimah: Attachment dibentuk ulang hanya ketika style berubah; pose tiap frame memakai vertex terbaru.
        private func updateEyeliner(_ face: RenderFace, anchor: ARFaceAnchor, profile: SurfaceRenderProfile, options: Settings, selected: [TutorialStep]) {
            if face.eyeliner == nil { installRegion(profile.defaultEyeliner,style:EyelinerStyle(),on:face) }
            lock.lock(); let ready=pendingStyles.removeValue(forKey:anchor.identifier); lock.unlock()
            if let ready {
                face.styleJobInFlight=false
                if ready.style==options.style { installRegion(ready.region,style:ready.style,on:face) }
            }
            if face.eyelinerStyle != options.style && !face.styleJobInFlight {
                face.styleJobInFlight=true
                let ticket=face.generation,id=anchor.identifier,style=options.style
                // -Nimah: Binding style di worker agar slider tidak membekukan renderer AR.
                fitQueue.async {
                    let region=EyelinerRegion.make(vertices:profile.restVertices,triangles:profile.triangles,rims:profile.surface.eyeRims,style:style)
                    self.lock.lock()
                    if self.sessionActive && self.generation==ticket && self.activeAnchorID==id { self.pendingStyles[id]=StyleResult(style:style,region:region) }
                    self.lock.unlock()
                }
            }
            let vertices=Array(anchor.geometry.vertices)
            face.eyelinerRoot.isHidden = !selected.contains(.eyeliner) && options.debug != .regions
            for (i,eye) in (face.eyeliner?.eyes ?? []).enumerated() {
                let leftSide: EyelinerRegion.Side=anchor.leftEyeTransform.columns.3.x<0 ? .negativeX : .positiveX
                let blink=anchor.blendShapes[eye.side==leftSide ? .eyeBlinkLeft : .eyeBlinkRight]?.floatValue ?? 0
                let node=face.eyelinerNodes[i], dots=face.eyelinerDots[i]
                node.isHidden = blink>=0.5 || (!options.mode.showsMakeup && options.debug != .regions)
                dots.isHidden = blink>=0.5 || (!options.mode.showsPoints && options.debug != .regions)
                let tint: UIColor=options.debug == .regions ? (eye.side == .negativeX ? .cyan : .magenta) : UIColor(red:0.09,green:0.045,blue:0.035,alpha:1)
                let material=node.geometry?.firstMaterial ?? EyelinerRenderer.material()
                material.diffuse.contents=tint; material.transparency=CGFloat(options.strength)
                node.geometry=EyelinerRenderer.geometry(eye:eye,vertices:vertices,material:material)
                for (dot,attachment) in zip(dots.childNodes,eye.guides) {
                    if let p=attachment.position(in:vertices,lift:0.0012) { dot.position=SCNVector3(p.x,p.y,p.z) }
                    else { dot.isHidden=true }
                }
                let label=face.labels.childNodes[i]
                label.isHidden=blink>=0.5
                (label.geometry as? SCNText)?.string="\(eye.side==leftSide ? "LEFT EYE" : "RIGHT EYE") / \(eye.side.rawValue)"
                if let p=eye.guides.first?.position(in:vertices,lift:0.002) { label.position=SCNVector3(p.x,p.y+0.008,p.z) }
            }
        }
        private func installRegion(_ region: EyelinerRegion, style: EyelinerStyle, on face: RenderFace) {
            face.eyelinerStyle=style; face.eyeliner=region
            face.eyelinerRoot.childNodes.forEach { $0.removeFromParentNode() }
            face.labels.childNodes.forEach { $0.removeFromParentNode() }
            face.eyelinerNodes=[]; face.eyelinerDots=[]
            for eye in region.eyes {
                let node=SCNNode(); face.eyelinerRoot.addChildNode(node); face.eyelinerNodes.append(node)
                let dots=SCNNode(); face.eyelinerRoot.addChildNode(dots); face.eyelinerDots.append(dots)
                for _ in eye.guides { dots.addChildNode(makeDot()) }
                face.labels.addChildNode(LiveGuideDiagnostics.label("EYE \(eye.side.rawValue)"))
            }
        }
        private func updateDebug(_ face: RenderFace, anchor: ARFaceAnchor, options: Settings) {
            face.diagnosticNode.isHidden=options.debug != .wireframe && options.debug != .uv
            face.labels.isHidden=options.debug != .regions
            if !face.diagnosticNode.isHidden { face.diagnostic.update(from:anchor.geometry) }
            if face.debugMode != options.debug {
                face.debugMode=options.debug
                let material=EyelinerRenderer.material(tint:.cyan)
                if options.debug == .uv { material.diffuse.contents=LiveGuideDiagnostics.atlas() }
                else { material.fillMode = .lines }
                face.diagnostic.materials=[material]
            }
            if options.debug != .off {
                let debug="anchor \(anchor.identifier.uuidString.prefix(8)) · step \(options.step.rawValue) · full \(options.fullLook) · vertex colors · regions \(face.eyeliner?.eyes.count ?? 0)/2"
                Task { @MainActor in if self.isCurrent(face.generation,anchorID:anchor.identifier) { self.camera.debugMessage=debug } }
            }
        }
        // -Nimah: Kamera dapat terus merender walau anchor tidak mengirim update saat tracking hilang.
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let (options,trackingOK,_,current)=snapshot()
            if !trackingOK || !options.visible || options.mode == .original {
                for face in faces.values { face.depthNode.parent?.isHidden=true }
            }
            for face in faces.values where face.generation != current { face.depthNode.parent?.isHidden=true }
        }
        private func makeDot() -> SCNNode {
            let shell=SCNSphere(radius:0.0014); shell.segmentCount=8
            let material=SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents=UIColor.white
            shell.materials=[material]
            let node=SCNNode(geometry:shell)
            let inner=SCNSphere(radius:0.0009); inner.segmentCount=8
            let tint=SCNMaterial(); tint.lightingModel = .constant; tint.diffuse.contents=UIColor(red:0.72,green:0.18,blue:0.35,alpha:1)
            inner.materials=[tint]; let center=SCNNode(geometry:inner); center.position.z=0.0009
            node.addChildNode(center); return node
        }
        func renderer(_ renderer:SCNSceneRenderer,didRemove node:SCNNode,for anchor:ARAnchor) {
            faces.removeValue(forKey:anchor.identifier)
            lock.lock()
            pendingStyles.removeValue(forKey:anchor.identifier)
            let removedActive=activeAnchorID==anchor.identifier
            if removedActive { activeAnchorID=nil; pending=nil }
            lock.unlock()
            // -Nimah: didRemove anchor lama tidak boleh menghapus mapping anchor baru.
            if removedActive { eyebrowPipeline.reset() }
        }
        func session(_ session:ARSession,didUpdate frame:ARFrame) {
            // -Nimah: Abaikan callback/Task tertunda setelah pause, refit atau interruption.
            lock.lock(); let ticket=generation, active=sessionActive; lock.unlock()
            guard active else { return }
            let face=frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
            lock.lock();let beautyEngine=beauty;lock.unlock();beautyEngine?.submit(frame,face:face)
            lock.lock(); let handler=frameHandler; lock.unlock()
            if let face,face.isTracked,let handler { handler(frame,face) }
            let normal:Bool
            if case .normal=frame.camera.trackingState { normal=true } else { normal=false }
            let isTracked=normal && face?.isTracked==true
            var relative=matrix_identity_float4x4
            if let face { relative=simd_inverse(frame.camera.transform)*face.transform }
            let relaxed=face.map { ($0.blendShapes[.jawOpen]?.floatValue ?? 0)<0.20 && ($0.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0)<0.25 && ($0.blendShapes[.eyeBlinkRight]?.floatValue ?? 0)<0.25 } ?? false
            setTracking(isTracked,canFit:isTracked && self.fitStable && relaxed && abs(relative.columns.2.z)>0.85)
            let options=snapshot().0
            if let configuration=options.eyebrows {
                if isTracked,let face {
                    if configuration.usesLaunchFit {
                        // Brow/cheek attachments are fitted from this live camera, then followed by ARKit tracking.
                        if relaxed && abs(relative.columns.2.z)>0.94 && !LaunchMakeupFit.shared.hasFit {
                            LaunchMakeupFit.shared.fitLive(FaceLandmarkFrame(frame:frame,anchor:face))
                        }
                        eyebrowPipeline.followLaunchFit(anchorID:face.identifier,vertices:Array(face.geometry.vertices),
                            triangles:Array(face.geometry.triangleIndices),timestamp:frame.timestamp,style:configuration.style,
                            blushStyle:configuration.needsBlush ? configuration.blushStyle : nil,
                            eyeCenters:[face.leftEyeTransform,face.rightEyeTransform].map { SIMD3($0.columns.3.x,$0.columns.3.y,$0.columns.3.z) })
                    } else {
                    eyebrowPipeline.observe(frame:frame,anchor:face,canCalibrate:self.fitStable && relaxed && abs(relative.columns.2.z)>0.85,style:configuration.style,foreheadStyle:(configuration.region == .forehead || configuration.showAllRegions) ? configuration.foreheadStyle : nil,height:configuration.foreheadHeight,blushStyle:configuration.needsBlush ? configuration.blushStyle : nil)
                    }
                } else { eyebrowPipeline.trackingLost() }
            }
            guard frame.timestamp-lastReport>=0.1 else { return }; lastReport=frame.timestamp
            let position=SIMD3(relative.columns.3.x,relative.columns.3.y,relative.columns.3.z)
            let rotation=simd_quatf(relative)
            let steady=isTracked && previousPosition.map { simd_distance($0,position)<0.008 }==true && previousRotation.map { abs(simd_dot($0.vector,rotation.vector))>0.999 }==true
            previousPosition=isTracked ? position : nil; previousRotation=isTracked ? rotation : nil
            let ready=readiness.update(timestamp:frame.timestamp,tracked:isTracked,steady:steady)
            fitStable=ready
            let distance=isTracked ? Double(simd_length(position)) : nil
            let brow=options.eyebrows.map { eyebrowPipeline.snapshot(style:$0.style,foreheadStyle:($0.region == .forehead || $0.showAllRegions) ? $0.foreheadStyle : nil,height:$0.foreheadHeight,includeBrow:$0.showAllRegions || ($0.layered && $0.browLayer.on),blushStyle:$0.needsBlush ? $0.blushStyle : nil) }
            Task { @MainActor in
                guard self.isCurrent(ticket) else { return }
                if let brow {
                    self.camera.update(\.eyebrowWasTracked, self.camera.eyebrowWasTracked || isTracked)
                    self.camera.update(\.eyebrowGuideReady, brow.ready)
                    self.camera.update(\.fitReady, brow.ready)
                    // -Nimah: Explain the gate that is actually preventing a new scan.
                    let scanMessage = brow.ready ? brow.message : (!relaxed ? "Buka kedua mata, rilekskan mulut, dan lihat lurus ke kamera." : (relative.columns.2.z <= 0.94 ? "Luruskan wajah menghadap kamera; jangan menoleh atau menunduk." : (!self.fitStable ? "Tahan iPhone dan kepala tetap stabil sebentar. Scan dimulai saat gerakan berkurang." : brow.message)))
                    self.camera.update(\.eyebrowMessage, isTracked ? scanMessage : (self.camera.eyebrowWasTracked ? "Tracking lost · guides hidden; face the camera to remap" : "Position your face in the frame"))
                    let confidence=brow.confidence.map { String(format:"%.2f",$0) } ?? "—"
                    self.camera.update(\.eyebrowDebug, "Vision face confidence \(confidence) · mapped brows \(brow.guide?.curves.count ?? 0)/2 · style \(options.eyebrows?.style.rawValue ?? "—")")
                }
                self.camera.report(tracked:isTracked,ready:ready); self.camera.update(\.distanceMeters, distance.map { ($0*100).rounded()/100 })
            }
        }
        private func invalidateSession() {
            lock.lock(); sessionActive=false; tracked=false; fitAllowed=false
            generation=UUID(); activeAnchorID=nil; pending=nil; pendingStyles=[:]; lock.unlock()
            eyebrowPipeline.reset()
        }
        func sessionWasInterrupted(_ session:ARSession) {
            invalidateSession()
            readiness.reset(); fitStable=false; setTracking(false,canFit:false)
            Task { @MainActor in self.camera.suspend(); self.camera.message="Camera interrupted. Resume when the interruption ends." }
        }
        func sessionInterruptionEnded(_ session:ARSession) {
            Task { @MainActor in self.running=false; self.camera.suspend(); if self.desiredRunning,self.manager.owns(self.leaseID),let view=self.camera.view,UIApplication.shared.applicationState == .active { self.start(view) } }
        }
        func session(_ session:ARSession,didFailWithError error:Error) {
            invalidateSession()
            setTracking(false,canFit:false); let message=error.localizedDescription
            Task { @MainActor in self.camera.suspend(); self.camera.failure=message; self.running=false }
        }
    }
}
