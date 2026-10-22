#if DEBUG
import SwiftUI

/// Debug-only readout of the measured eye values and how they became the eyeliner, for calibrating the thresholds.
struct EyeDebugView: View {
    let eyes: EyeScan?
    var overlay: LinerOverlayModel?
    @AppStorage("debugEyeLandmarks") private var showsLandmarks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEBUG eye measurements").font(.caption.weight(.bold))
            Toggle("Show eyeliner landmark dots (red raw, green smoothed)", isOn: $showsLandmarks)
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
#endif
