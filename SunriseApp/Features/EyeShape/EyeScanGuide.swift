import Foundation
import simd

/// What to tell the person during the eye scan, most urgent first.
enum EyeScanGuidance: Equatable, Sendable {
    case findFace, moveCloser, moveBack, lookStraight, raisePhone, lowerPhone, openEyes, holdStill
}

/// One camera frame, judged. `measurements` is only set when the frame is good enough to count.
struct EyeScanFrame: Equatable, Sendable {
    var guidance: EyeScanGuidance
    var measurements: EyeMeasurements?
}

/// Decides whether a frame is usable and what to say if it is not. Pure, so it is tested without a camera.
///
/// The limits are starting guesses (about arm's length, within roughly 10 degrees of straight on); tune them on a device.
enum EyeScanGuide {
    /// `EyeScanLandmarks.headTurn` beyond this is a turned head.
    static let maxHeadTurn: Float = 0.12
    /// `EyeScanLandmarks.headPitch` beyond this (10°, the face scan's `HeadPose` limit) means the phone is not at eye level.
    static let maxHeadPitch: Float = .pi / 18
    /// Distance between the two eye centres as a fraction of the image width. About 0.17 at 30 cm on an iPhone.
    static let eyeSeparationRange: ClosedRange<Float> = 0.12...0.35

    static func evaluate(_ landmarks: EyeScanLandmarks?, imageWidth: Float) -> EyeScanFrame {
        guard let landmarks, imageWidth > 0, !landmarks.first.lid.isEmpty, !landmarks.second.lid.isEmpty else {
            return EyeScanFrame(guidance: .findFace)
        }
        func center(_ points: [SIMD2<Float>]) -> SIMD2<Float> { points.reduce(.zero, +) / Float(points.count) }
        let separation = simd_distance(center(landmarks.first.lid), center(landmarks.second.lid)) / imageWidth
        if separation < eyeSeparationRange.lowerBound { return EyeScanFrame(guidance: .moveCloser) }
        if separation > eyeSeparationRange.upperBound { return EyeScanFrame(guidance: .moveBack) }
        if let turn = landmarks.headTurn, abs(turn) > maxHeadTurn { return EyeScanFrame(guidance: .lookStraight) }
        if let pitch = landmarks.headPitch {
            if pitch > maxHeadPitch { return EyeScanFrame(guidance: .raisePhone) }
            if pitch < -maxHeadPitch { return EyeScanFrame(guidance: .lowerPhone) }
        }
        guard let measurements = EyeMeasurer.measure(landmarks) else { return EyeScanFrame(guidance: .findFace) }
        if measurements.openness < EyeMeasurer.minimumOpenness { return EyeScanFrame(guidance: .openEyes) }
        return EyeScanFrame(guidance: .holdStill, measurements: measurements)
    }
}
