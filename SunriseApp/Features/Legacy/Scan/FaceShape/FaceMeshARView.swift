import ARKit
import SceneKit
import SwiftUI

/// Front camera feed with ARKit's face mesh drawn as a wireframe that follows the face.
struct FaceMeshARView: UIViewRepresentable {
    let session: ARSession
    /// Gets this view, so the result can show the camera picture the person saw.
    var snapshotter: FaceSnapshotter?

    func makeCoordinator() -> FaceMeshRenderer { FaceMeshRenderer() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        snapshotter?.view = view
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

/// SceneKit calls these on its render thread; the class keeps no state.
final class FaceMeshRenderer: NSObject, ARSCNViewDelegate {
    func renderer(_ renderer: any SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor, let device = renderer.device,
              let geometry = ARSCNFaceGeometry(device: device) else { return nil }
        let material = geometry.firstMaterial
        material?.fillMode = .lines
        material?.lightingModel = .constant
        material?.diffuse.contents = UIColor(named: "Rose")?.withAlphaComponent(0.8)
        return SCNNode(geometry: geometry)
    }

    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let face = anchor as? ARFaceAnchor, let geometry = node.geometry as? ARSCNFaceGeometry else { return }
        geometry.update(from: face.geometry)
    }
}
