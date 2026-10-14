/// Composition root only. Views receive individual dependencies through initializers.
struct AppContainer {
    let catalog: any ReferenceCatalogProviding
    let faceTracking: any FaceTrackingAvailabilityChecking
    let savedLooks: any SavedLooksStoring

    static func scaffold() -> AppContainer {
        AppContainer(catalog: MockReferenceCatalog(),
                     faceTracking: MockFaceTrackingChecker(),
                     savedLooks: MockSavedLooksStore())
    }
}
