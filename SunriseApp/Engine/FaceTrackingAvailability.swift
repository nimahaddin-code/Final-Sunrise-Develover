enum FaceTrackingAvailability: Equatable, Sendable {
    case notChecked
    case supported
    case unsupported(reason: String)
}
