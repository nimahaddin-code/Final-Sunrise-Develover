import ARKit
import SceneKit
import SwiftUI

/// One category's makeup on the face: its texture and how strongly it shows (0...1).
struct MakeupLayer: Equatable {
    var texture: UIImage?
    var intensity: Double
}

/// Lets SwiftUI take a photo of the camera feed with the makeup on it.
@MainActor final class ARSnapshotter {
    fileprivate weak var view: ARSCNView?

    func snapshot() -> UIImage? { view?.snapshot() }
}

/// Front camera feed with each makeup layer drawn on ARKit's face mesh, so it follows the face live.
struct MakeupARView: UIViewRepresentable {
    let session: ARSession
    let layers: [MakeupCategory: MakeupLayer]
    /// `false` hides all makeup, for comparing with the bare face.
    let showsMakeup: Bool
    let snapshotter: ARSnapshotter

    func makeCoordinator() -> MakeupFaceRenderer { MakeupFaceRenderer() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = false
        snapshotter.view = view
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        for category in MakeupCategory.allCases {
            guard let material = context.coordinator.materials[category] else { continue }
            let layer = layers[category]
            // An empty material would render as a white mask, so show nothing until there is makeup.
            material.diffuse.contents = layer?.texture ?? UIColor.clear
            material.transparency = showsMakeup ? CGFloat(layer?.intensity ?? 0) : 0
        }
    }
}

/// SceneKit calls these on its render thread; the shared materials are only changed through SceneKit.
///
/// Every category is its own copy of the face mesh, so layers blend on top of each other. The layers don't write
/// depth (they would hide each other); instead an invisible, slightly shrunken mesh writes depth first, so parts of
/// the face hidden behind the nose stay hidden.
final class MakeupFaceRenderer: NSObject, ARSCNViewDelegate {
    /// Blush first, liner on top.
    static let drawOrder: [MakeupCategory] = [.blush, .eyebrow, .eyeliner]

    let materials: [MakeupCategory: SCNMaterial] = Dictionary(uniqueKeysWithValues: MakeupCategory.allCases.map {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.clear
        material.diffuse.mipFilter = .linear
        material.transparencyMode = .aOne
        material.transparency = 0
        material.writesToDepthBuffer = false
        return ($0, material)
    })

    private let occluder: SCNMaterial = {
        let material = SCNMaterial()
        material.colorBufferWriteMask = []
        return material
    }()

    func renderer(_ renderer: any SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor, let device = renderer.device else { return nil }
        let root = SCNNode()
        // Filling the eye openings keeps liner drawn right on the lash line from being clipped.
        if let geometry = ARSCNFaceGeometry(device: device, fillMesh: true) {
            geometry.materials = [occluder]
            let node = SCNNode(geometry: geometry)
            node.renderingOrder = -1
            // About a millimetre behind the face surface, so the layers on the surface pass the depth test.
            node.scale = SCNVector3(0.99, 0.99, 0.99)
            root.addChildNode(node)
        }
        for (order, category) in Self.drawOrder.enumerated() {
            guard let geometry = ARSCNFaceGeometry(device: device, fillMesh: true),
                  let material = materials[category] else { continue }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.renderingOrder = order + 1
            root.addChildNode(node)
        }
        return root
    }

    func renderer(_ renderer: any SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let face = anchor as? ARFaceAnchor else { return }
        for child in node.childNodes {
            (child.geometry as? ARSCNFaceGeometry)?.update(from: face.geometry)
        }
    }
}
