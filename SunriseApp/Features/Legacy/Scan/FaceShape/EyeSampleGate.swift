import Foundation

/// Decides which camera frames are good enough to measure the eyes: the head is straight and both eyes are open.
enum EyeSampleGate {
    /// Blink blend shape weight above which an eye counts as closed or closing.
    static let maxBlink: Float = 0.3
    /// Squinting narrows the opening, which would read as a smaller `openness`.
    static let maxSquint: Float = 0.5
    /// Vision readings needed for a scan (about 1–2 seconds).
    static let requiredSamples = 8
    /// Run Vision on every n-th accepted frame.
    static let visionInterval = 5

    enum Verdict: Equatable { case accept, lookStraight, openEyes }

    static func verdict(isTracked: Bool, headIsStraight: Bool, blinkLeft: Float, blinkRight: Float,
                        squintLeft: Float, squintRight: Float) -> Verdict {
        guard isTracked, headIsStraight else { return .lookStraight }
        guard max(blinkLeft, blinkRight) <= maxBlink, max(squintLeft, squintRight) <= maxSquint else { return .openEyes }
        return .accept
    }
}
