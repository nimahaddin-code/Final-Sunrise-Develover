// -Nimah: Satu ARSession untuk seluruh modul; lease mencegah layar lama menghentikan modul baru.
import ARKit

@MainActor final class ARFaceTrackingManager {
    static let shared=ARFaceTrackingManager()
    private(set) lazy var session=ARSession()
    private var owner: UUID?
    private var onRevoked: (() -> Void)?
    func acquire(owner newOwner: UUID, onRevoked: @escaping () -> Void) {
        guard owner != newOwner else { return }
        let previous=self.onRevoked
        owner=newOwner; self.onRevoked=onRevoked
        previous?()
    }
    func owns(_ owner: UUID) -> Bool { self.owner==owner }
    @discardableResult func release(owner: UUID) -> Bool {
        guard self.owner==owner else { return false }
        session.pause(); session.delegate=nil
        self.owner=nil; onRevoked=nil
        return true
    }
}

enum FaceTrackingState: String, Sendable {
    case searching = "Searching for face"
    case detected = "Face detected"
    case lost = "Tracking lost"
    case unsupported = "Device unsupported"
    case denied = "Camera permission required"
}
