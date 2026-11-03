import CoreGraphics
import Foundation

/// The last eye measurement that MediaPipe delivered, kept so the liner can be drawn on every ARKit frame:
/// moved with ARKit's head tracking, which also works when a hand covers part of the face and the detector loses it,
/// and which hides the detector's one-to-two-frame delay.
struct LinerSolution {
    /// How long a measurement stays on screen without a newer one, and when it starts to fade.
    static let holdDuration: CFTimeInterval = 2.0
    static let fadeStart: CFTimeInterval = 0.6

    var eyes: [RenderedEye]
    var raw: [EyeLandmarks]
    var smoothed: [EyeLandmarks]
    /// Where ARKit's face reference points were in the camera image when this was measured (pixels).
    var references: [CGPoint]
    var time: CFTimeInterval

    /// 1 while fresh, fading to 0 at `holdDuration`.
    func fade(at now: CFTimeInterval) -> Double {
        let age = now - time
        if age <= Self.fadeStart { return 1 }
        return max(0, 1 - (age - Self.fadeStart) / (Self.holdDuration - Self.fadeStart))
    }

    /// The measurement carried to where the head is now (`references` are the same points in the current frame);
    /// `nil` once it is too old to trust.
    func moved(to references: [CGPoint], now: CFTimeInterval)
        -> (eyes: [RenderedEye], raw: [EyeLandmarks], smoothed: [EyeLandmarks])? {
        let fade = fade(at: now)
        guard fade > 0.01 else { return nil }
        // A head cannot grow or shrink by more than this between a measurement and a later frame; a reading that
        // says so is broken (for example collapsed points), and the liner stays where it was instead of collapsing.
        let transform = SimilarityTransform(from: self.references, to: references).flatMap { t -> SimilarityTransform? in
            let scale = (t.zr * t.zr + t.zi * t.zi).squareRoot()
            return scale > 0.5 && scale < 2 ? t : nil
        }
        let eyes = self.eyes.map { eye in
            RenderedEye(side: eye.side, guide: transform.map { eye.guide.transformed(by: $0) } ?? eye.guide,
                        alpha: eye.alpha * fade)
        }
        return (eyes, transform.map { t in raw.map { $0.transformed(by: t) } } ?? raw,
                transform.map { t in smoothed.map { $0.transformed(by: t) } } ?? smoothed)
    }
}
