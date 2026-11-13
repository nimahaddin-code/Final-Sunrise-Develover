// -Nimah: AppContainer.swift — implementasi MVP SunriseApp.
struct AppContainer {
    let faceTracking: any FaceTrackingAvailabilityChecking
    /// Compares the desired-look photo with the result. Placeholder until the real comparison is plugged in here.
    var feedback: any MakeupFeedbackProviding = MeasuredFeedbackProvider()
    /// -Nimah: finished looks, saved on this phone only (My Looks).
    var myLooks: MyLookStore = .live()
    static func live() -> AppContainer {
        AppContainer(faceTracking: DeviceFaceTrackingChecker())
    }
}
