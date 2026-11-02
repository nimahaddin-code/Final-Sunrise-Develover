import ARKit
import SceneKit

/// Takes the scan picture from the live camera view and places the measured lines on it.
///
/// The picture and the lines both come from the same `ARSCNView`, so they use the same mirroring and rotation: whatever the
/// person saw while scanning is what they see in the result. The picture is only returned, never stored.
@MainActor final class FaceSnapshotter {
    /// Set by `FaceMeshARView` when it creates its view.
    weak var view: ARSCNView?

    /// The camera picture without the mesh wireframe, cropped around the face, with `guide` drawn on it.
    /// `nil` when there is no face on screen or the lines cannot be placed.
    func capture(_ guide: FaceGuide) -> ScanSnapshot? {
        guard let view, view.bounds.width > 0, view.bounds.height > 0,
              let anchor = view.session.currentFrame?.anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first,
              let faceNode = view.node(for: anchor) else { return nil }

        let size = view.bounds.size
        func position(_ point: SIMD3<Float>) -> CGPoint? {
            let world = faceNode.convertPosition(SCNVector3(point), to: nil)
            let projected = view.projectPoint(world)
            // Behind the camera or off to infinity: not a place on the picture.
            guard projected.z > 0, projected.z < 1 else { return nil }
            return CGPoint(x: CGFloat(projected.x) / size.width, y: CGFloat(projected.y) / size.height)
        }
        guard let overlay = guide.overlay(project: position) else { return nil }

        // Hide the wireframe for the instant of the snapshot so the picture is the plain camera image.
        let shown = view.scene.rootNode.childNodes.filter { !$0.isHidden }
        shown.forEach { $0.isHidden = true }
        SCNTransaction.flush()
        let picture = view.snapshot()
        shown.forEach { $0.isHidden = false }

        guard let image = picture.cgImage else { return nil }
        return ScanSnapshot(image: image, overlay: overlay)
    }
}
