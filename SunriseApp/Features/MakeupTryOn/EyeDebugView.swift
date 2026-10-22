import SwiftUI

/// Developer-tools readout (hidden until switched on with a long press, see `DeveloperTools`) of the measured eye values and how they became the eyeliner, for calibrating the thresholds.
struct EyeDebugView: View {
    let eyes: EyeScan?
    var overlay: LinerOverlayModel?
    @AppStorage("debugEyeLandmarks") private var showsLandmarks = false
    @AppStorage("debugOcclusionMask") private var showsMask = false
    @AppStorage("enableLidTracking") private var tracksLid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEVELOPER eye measurements").font(.caption.weight(.bold))
            Toggle("Show eyeliner landmark dots (red raw, green smoothed)", isOn: $showsLandmarks)
            Toggle("Lid tracking (experimental, for a pulled lid; re-open the try-on)", isOn: $tracksLid)
            Toggle("Show hand mask (red: hand seen, lid tracking follows the skin)", isOn: $showsMask)
            if let overlay { OverlayStatusLine(model: overlay) }
            if let eyes {
                let plan = EyelinerPlanner.plan(for: eyes)
                line("tilt L/R", String(format: "%.1f° / %.1f° (mean %.1f°)", eyes.tiltLeft, eyes.tiltRight, eyes.tilt))
                line("spacing", String(format: "%.3f eye widths", eyes.spacing))
                line("openness", String(format: "%.3f (round from %.2f)", eyes.openness, EyeScan.roundStart))
                line("samples / lid", "\(eyes.samples) / \(eyes.lidType.rawValue)")
                ForEach(EyeShape.allCases) { shape in
                    let score = eyes.scores[shape] ?? 0
                    line(shape.rawValue, String(format: "%.2f (x%.1f = %.2f)", score, shape.confidence,
                                                score * shape.confidence))
                }
                line("low confidence", eyes.isLowConfidence ? "yes, natural line" : "no")
                line("blend", plan.blend.map { "\($0.shape.rawValue) \(Int($0.weight * 100))%" }.joined(separator: ", "))
                line("wing", String(format: "%.2f long, %.0f°%@", plan.style.wingLength, plan.style.wingAngle,
                                    plan.wingRemoved ? " (removed, R4)" : ""))
            } else {
                Text("no eye measurements in this scan")
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func line(_ name: String, _ value: String) -> some View {
        Text("\(name): \(value)")
    }
}

private struct OverlayStatusLine: View {
    @ObservedObject var model: LinerOverlayModel
    var body: some View { Text(model.debugStatus.isEmpty ? "MediaPipe: waiting" : model.debugStatus) }
}

/// Developer mode (the readout above, landmark dots, hand mask, lid tracking switch): nothing of it shows until it is
/// switched on, with the ladybug button in the try-on toolbar (Debug builds) or by long-pressing the explanation text
/// under the eyeliner shades (any build).
enum DeveloperTools {
    static let key = "developerTools"
    static func isOn(_ stored: Bool) -> Bool { stored }
}
