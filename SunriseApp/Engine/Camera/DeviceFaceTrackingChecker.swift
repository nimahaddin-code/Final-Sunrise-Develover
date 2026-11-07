// -Nimah: DeviceFaceTrackingChecker.swift — implementasi MVP SunriseApp.
import ARKit

struct DeviceFaceTrackingChecker: FaceTrackingAvailabilityChecking {
    func availability() async -> FaceTrackingAvailability {
        #if targetEnvironment(simulator)
        return .unsupported(reason: "Simulator has no live AR face camera. Follow the manual tutorial, or run on a compatible iPhone.")
        #else
        return ARFaceTrackingConfiguration.isSupported ? .supported : .unsupported(reason: "This device does not support ARKit face tracking. You can still follow the manual tutorial.")
        #endif
    }
}
