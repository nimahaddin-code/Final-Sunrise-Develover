import Combine

@MainActor final class FaceCalibrationViewModel: ObservableObject {
    @Published private(set) var availability: FaceTrackingAvailability = .notChecked
    private let checker: any FaceTrackingAvailabilityChecking
    init(checker: any FaceTrackingAvailabilityChecking) { self.checker = checker }
    func loadAvailability() async { availability = await checker.availability() }
}
