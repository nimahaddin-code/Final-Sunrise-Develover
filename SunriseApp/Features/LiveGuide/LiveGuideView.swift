// -Nimah: LiveGuideView.swift — implementasi MVP SunriseApp.
import SwiftUI
import ARKit
import SceneKit

struct LiveGuideView: UIViewRepresentable {
    @ObservedObject var camera: FaceCameraState
    let color: UIColor
    let active: Bool
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera, color: color) }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        // -Nimah: Session dan renderer callback memakai serial queue yang sama, terpisah dari UI.
        view.session.delegateQueue = context.coordinator.queue
        camera.view = view
        camera.stopSession = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.pause(view) }
        }
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {
        let overlay = camera.overlay
        context.coordinator.updateOverlay(overlay)
        if active && camera.authorized && camera.failure == nil { context.coordinator.start(view) }
        else { context.coordinator.pause(view) }
    }
    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.pause(view); view.delegate = nil; view.session.delegate = nil
    }
    // -Nimah: Delegate bukan MainActor; state UI selalu dikirim balik ke MainActor.
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, @unchecked Sendable {
        let queue = DispatchQueue(label: "sunrise.face-session")
        private let camera: FaceCameraState
        private let color: SIMD3<Float>
        private let lock = NSLock()
        private var showOverlay = false
        private var trackingAllowed = false
        private var running = false
        private var desiredRunning = false
        private var readiness = TrackingReadiness()
        private var previousPosition: SIMD3<Float>?
        private var previousRotation: simd_quatf?
        private var lastReport: TimeInterval = 0
        // -Nimah: SceneKit mesh dihitung di render thread; tidak dibaca oleh UI/session queue.
        private var masks: [UUID: [SCNVector4]] = [:]
        init(camera: FaceCameraState, color: UIColor) {
            self.camera = camera
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            self.color = SIMD3(Float(r), Float(g), Float(b))
        }
        func updateOverlay(_ value: Bool) { lock.lock(); showOverlay = value; lock.unlock() }
        private var visible: Bool { lock.lock(); defer { lock.unlock() }; return showOverlay && trackingAllowed }
        private func allowTracking(_ value: Bool) { lock.lock(); trackingAllowed = value; lock.unlock() }
        @MainActor func start(_ view: ARSCNView) {
            desiredRunning = true
            guard !running, ARFaceTrackingConfiguration.isSupported else { return }
            running = true; allowTracking(false)
            queue.async { self.readiness.reset(); self.previousPosition = nil; self.previousRotation = nil; self.lastReport = 0 }
            let configuration = ARFaceTrackingConfiguration()
            configuration.maximumNumberOfTrackedFaces = 1
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        @MainActor func pause(_ view: ARSCNView) {
            desiredRunning = false; allowTracking(false)
            guard running else { return }
            view.session.pause(); running = false; camera.suspend()
        }
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor else { return nil }
            return SCNNode()
        }
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let face = anchor as? ARFaceAnchor else { return }
            if masks[face.identifier] == nil {
                masks[face.identifier] = face.geometry.vertices.map { v in
                    SCNVector4(color.x, color.y, color.z, BlushMask.weight(x: v.x, y: v.y, z: v.z))
                }
            }
            guard let colors = masks[face.identifier] else { return }
            // -Nimah: Semua vertex dan indeks berasal dari face mesh terkini, bukan posisi layar.
            let vertices = face.geometry.vertices.map { SCNVector3($0.x, $0.y, $0.z + 0.0005) }
            let vertexSource = SCNGeometrySource(vertices: vertices)
            let colorSource = SCNGeometrySource(data: colors.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color,
                vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector4>.stride)
            let indices = face.geometry.triangleIndices
            let element = SCNGeometryElement(data: indices.withUnsafeBufferPointer { Data(buffer: $0) }, primitiveType: .triangles,
                primitiveCount: face.geometry.triangleCount, bytesPerIndex: MemoryLayout<Int16>.size)
            let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant; material.diffuse.contents = UIColor.white
            material.blendMode = .alpha; material.writesToDepthBuffer = false
            material.isDoubleSided = false; geometry.materials = [material]
            node.geometry = geometry
            node.isHidden = !face.isTracked || !visible
        }
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) { masks.removeValue(forKey: anchor.identifier) }
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard frame.timestamp - lastReport >= 0.1 else { return }; lastReport = frame.timestamp
            let face = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
            let normal: Bool
            if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
            let tracked = face?.isTracked == true && normal
            // -Nimah: Sembunyikan mesh juga saat kamera limited, bukan hanya saat anchor hilang.
            allowTracking(tracked)
            var steady = false
            if tracked, let face {
                let p = SIMD3(face.transform.columns.3.x, face.transform.columns.3.y, face.transform.columns.3.z)
                let q = simd_quatf(face.transform)
                steady = previousPosition.map { simd_distance($0, p) < 0.008 } == true && previousRotation.map { abs(simd_dot($0.vector, q.vector)) > 0.999 } == true
                previousPosition = p; previousRotation = q
            } else { previousPosition = nil; previousRotation = nil }
            let ready = readiness.update(timestamp: frame.timestamp, tracked: tracked, steady: steady)
            Task { @MainActor in self.camera.report(tracked: tracked, ready: ready) }
        }
        func sessionWasInterrupted(_ session: ARSession) {
            readiness.reset(); allowTracking(false)
            Task { @MainActor in self.camera.suspend(); self.camera.message = "Camera interrupted. Resume when the interruption ends." }
        }
        func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in
                self.running = false; self.camera.suspend()
                if self.desiredRunning, let view = self.camera.view, UIApplication.shared.applicationState == .active { self.start(view) }
            }
        }
        func session(_ session: ARSession, didFailWithError error: Error) {
            allowTracking(false)
            let message = error.localizedDescription
            Task { @MainActor in self.camera.suspend(); self.camera.failure = message; self.running = false }
        }
    }
}
