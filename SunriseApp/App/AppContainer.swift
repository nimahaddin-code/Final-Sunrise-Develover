// -Nimah: AppContainer.swift — implementasi MVP SunriseApp.
struct AppContainer {
    let catalog: any ReferenceCatalogProviding
    let faceTracking: any FaceTrackingAvailabilityChecking
    let savedLooks: any SavedLooksStoring
    static func live() -> AppContainer {
        AppContainer(catalog: BundledReferenceCatalog(), faceTracking: DeviceFaceTrackingChecker(), savedLooks: LocalSavedLooksStore())
    }
    static func scaffold() -> AppContainer {
        AppContainer(catalog: MockReferenceCatalog(), faceTracking: MockFaceTrackingChecker(), savedLooks: MockSavedLooksStore())
    }
}
