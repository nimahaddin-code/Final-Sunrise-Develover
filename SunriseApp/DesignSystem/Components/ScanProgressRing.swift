import SwiftUI

/// A circular progress ring like the App Store's install progress: it fills while the scan collects frames, shows the percentage
/// in the middle, and turns into a checkmark with a success tap when done.
struct ScanProgressRing: View {
    /// 0 to 1.
    let progress: Double
    var size: CGFloat = 56

    private var clamped: Double { min(1, max(0, progress)) }
    private var isDone: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.subtle.opacity(0.25), lineWidth: 6)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AppColors.rose, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: clamped)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(AppColors.rose)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(clamped, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: clamped))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.3), value: isDone)
        // A light tick at every tenth of the scan. The success tap at the end belongs to `ScanDoneBadge`.
        .sensoryFeedback(.impact(weight: .light), trigger: Int(clamped * 10)) { old, new in new > old && new < 10 }
        .accessibilityElement()
        .accessibilityLabel("Scan progress")
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview {
    VStack(spacing: 24) {
        ScanProgressRing(progress: 0.35)
        ScanProgressRing(progress: 1)
    }
    .padding()
}
