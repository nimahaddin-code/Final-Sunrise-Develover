import SwiftUI

/// Where the camera is shown. The checks differ a little between Try On and the tutorial.
enum CameraGuidanceContext: Equatable, Sendable { case tryOn, tutorial }

/// Camera problems, in priority order (lowest raw value wins). Each line tells her what to do next; none says what went wrong.
/// Wording and timing follow the dandan camera and tutorial UX spec.
enum CameraMessage: Int, CaseIterable, Comparable, Sendable {
    case phoneWarm = 0
    case tooDark, backlit, noFace, faceLost, multipleFaces, faceCovered, tooClose, tooFar, tiltedPhone, headTurned, movingFast

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// How long the problem must last before the message shows.
    var showDelay: TimeInterval {
        switch self {
        case .phoneWarm: 0
        case .faceLost: 2
        case .movingFast: 1.5
        default: 1
        }
    }

    /// How long the problem must stay clear before the message hides.
    static let hideDelay: TimeInterval = 0.5

    func text(lightOn: Bool) -> LocalizedStringKey {
        switch self {
        case .phoneWarm: "Your phone is warm. Let's take a short break."
        case .tooDark: lightOn ? "Still a bit dark. Try facing a lamp or window." : "It's a bit dark. Tap the light or face a window."
        case .backlit: "Turn so the light is in front of you."
        case .noFace: "I can't see you yet. Hold your phone like a mirror."
        case .faceLost: "I'll wait here. Come back when you're ready."
        case .multipleFaces: "Let's keep it to just you in the frame."
        case .faceCovered: "Move your hair or hands so I can see your face."
        case .tooClose: "Move your phone back a little."
        case .tooFar: "Pinch the screen to zoom in."
        case .tiltedPhone: "Hold your phone straight, at eye level."
        case .headTurned: "Face your phone straight on."
        case .movingFast: "Nice and slow, so I can keep up."
        }
    }
}
