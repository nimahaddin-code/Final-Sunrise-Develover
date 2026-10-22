import CoreGraphics
import Foundation

/// One eye's liner for the current frame, in captured-image pixels.
struct RenderedEye {
    let side: EyeSide
    let guide: LinerGuide
    /// 0...1; fades out as the eye closes and returns as it reopens.
    let alpha: Double
}

/// Landmarks in, liner geometry out: One Euro smoothing (with head motion removed through the rigid face anchors),
/// the per-user open-eye baseline and `LinerPathBuilder`. No camera, no UI, so it runs on synthetic landmarks in tests.
final class LinerTracker {
    var filterConfig = OneEuroConfig.steady
    var buildOptions = LinerBuildOptions()
    /// Fraction of THIS user's normal eye opening below which the liner starts to fade (relative, so hooded and
    /// monolid eyes with a small absolute opening still count as open).
    var openFractionThreshold: Double = 0.55
    /// A closed eye keeps its liner, on the closed lash line, like real liner. `false` fades it out as the eye closes.
    var keepsLinerWhenClosed = true
    /// A closing eye leaves less lid to show the liner on, so the liner gets thicker as the eye closes: a closed eye
    /// shows it `1 + closedThicknessBoost` times as thick.
    var closedThicknessBoost: CGFloat = 0.8

    /// The last frame's landmarks before and after smoothing, for the DEBUG dots.
    private(set) var lastRaw: [EyeLandmarks] = []
    private(set) var lastSmoothed: [EyeLandmarks] = []

    private let smoother = EyeLandmarksSmoother()
    private var baselines: [EyeSide: Double] = [:]

    func reset() {
        smoother.reset()
        baselines.removeAll()
    }

    func render(_ frame: EyeLandmarkFrame, spec: LinerSpec) -> [RenderedEye] {
        // ARKit's head anchors are steadier than MediaPipe's face points (and need no smoothing of their own), so head
        // motion is removed exactly and only real eye motion (blink, squint, a pulled lid) goes through the filter.
        let headAnchors = frame.context?.headAnchors ?? []
        let anchors = headAnchors.count >= 3
            ? headAnchors : smoother.smoothAnchors(frame.faceAnchors, t: frame.timestamp, config: filterConfig)
        var eyes: [EyeLandmarks] = []
        for (side, eye) in [(EyeSide.subjectLeft, frame.subjectLeft), (.subjectRight, frame.subjectRight)] {
            if let eye {
                eyes.append(smoother.smooth(eye, anchors: anchors, t: frame.timestamp, config: filterConfig))
            } else {
                smoother.reset(side: side)
                baselines[side] = nil
            }
        }
        lastRaw = frame.eyes
        lastSmoothed = eyes
        return eyes.compactMap { eye in
            let relative = openness(of: eye)
            let alpha = keepsLinerWhenClosed ? 1 : relative
            var options = buildOptions
            options.thicknessScale *= 1 + closedThicknessBoost * CGFloat(1 - relative)
            guard alpha > 0.01,
                  let guide = LinerPathBuilder.build(landmarks: eye, spec: spec, options: options) else { return nil }
            return RenderedEye(side: eye.side, guide: guide, alpha: alpha)
        }
    }

    /// 0 (closed) ... 1 (open) against this user's own normal opening.
    private func openness(of eye: EyeLandmarks) -> Double {
        let ratio = Double(eye.eyeOpenRatio)
        // The user's "normal opening": rises instantly, decays slowly, and only decays while the eye is open
        // (otherwise a long blink would pull the baseline down and a closed eye would count as open).
        var base = baselines[eye.side] ?? ratio
        if ratio >= base { base = ratio } else if ratio >= base * openFractionThreshold { base *= 0.995 }
        baselines[eye.side] = base
        let relative = ratio / max(base, 0.02)
        let low = openFractionThreshold * 0.4
        return clamp((relative - low) / max(openFractionThreshold - low, 1e-6), 0, 1)
    }
}
