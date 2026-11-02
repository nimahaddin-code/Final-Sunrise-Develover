protocol FaceTrackingAvailabilityChecking: Sendable {
    /// Availability is separate from camera permission and actual session tracking.
    func availability() async -> FaceTrackingAvailability
}
