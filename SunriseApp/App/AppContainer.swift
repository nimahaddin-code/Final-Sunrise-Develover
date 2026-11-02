// -Nimah: AppContainer.swift — implementasi MVP SunriseApp.
struct AppContainer {
    let faceTracking: any FaceTrackingAvailabilityChecking
    static func live() -> AppContainer {
        AppContainer(faceTracking: DeviceFaceTrackingChecker())
    }
}
