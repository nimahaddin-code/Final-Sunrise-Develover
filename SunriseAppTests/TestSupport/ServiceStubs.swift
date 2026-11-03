import Foundation
@testable import SunriseApp

/// A face-tracking checker that reports a fixed result, for tests that build the makeup view models without ARKit.
struct MockFaceTrackingChecker: FaceTrackingAvailabilityChecking {
    let result: FaceTrackingAvailability
    init(result: FaceTrackingAvailability = .notChecked) { self.result = result }
    func availability() async -> FaceTrackingAvailability { result }
}
