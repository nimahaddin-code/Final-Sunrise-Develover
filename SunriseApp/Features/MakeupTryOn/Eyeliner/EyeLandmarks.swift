import CoreGraphics
import Foundation

/// "Left/right" = the SUBJECT's side (MediaPipe convention).
enum EyeSide: String, Hashable {
    case subjectRight
    case subjectLeft
}

/// All points are in PIXELS of the captured camera image (the unrotated sensor buffer), never normalized.
/// Isotropic units are required so perpendicular offsets are not skewed. Rotation and mirroring do not matter to the
/// geometry, which works in each eye's own frame; they only matter when mapping to the screen (see `ImageToViewMapping`).
struct EyeLandmarks: Equatable {
    var side: EyeSide
    var innerCorner: CGPoint
    var outerCorner: CGPoint
    var upperLid: [CGPoint]      // ordered inner -> outer
    var lowerLid: [CGPoint]      // ordered inner -> outer
    var browPoints: [CGPoint]    // ordered inner -> outer (last = brow tail)
    var eyeOpenRatio: CGFloat    // lid gap / eye width; ~0 when closed
    /// A skin point beside the outer corner, where the wing ends up. The detector does not report it: lid tracking
    /// follows it, and the wing stretches with it. `nil` = the wing keeps its rigid place.
    var wingAnchor: CGPoint? = nil
}

struct EyeLandmarkFrame {
    var imageSize: CGSize        // pixels of the captured image
    var timestamp: TimeInterval  // seconds, monotonic
    var subjectLeft: EyeLandmarks?
    var subjectRight: EyeLandmarks?
    var providerLatencyMs: Double
    /// Rigid mid-face points (nose bridge, cheeks) that do NOT move when the eyes close or the eye skin is stretched.
    var faceAnchors: [CGPoint] = []
    /// How to map this frame's image pixels to the screen, captured when the frame was submitted.
    var context: FrameContext?

    var eyes: [EyeLandmarks] { [subjectLeft, subjectRight].compactMap { $0 } }
}
