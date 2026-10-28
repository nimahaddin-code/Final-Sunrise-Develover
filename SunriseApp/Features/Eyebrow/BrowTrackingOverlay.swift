import SwiftUI

/// One frame of MediaPipe brow tracking for the tracking view. Positions are normalized to the camera view (0...1).
struct BrowTrackingSnapshot: Equatable, Sendable {
    struct Label: Equatable, Sendable {
        let text: String
        let x: Float
        let y: Float
    }
    var faceFound: Bool
    /// Within the head-turn limit, so a brow shape would be drawn.
    var tracked = false
    var yaw: Float = 0
    var pitch: Float = 0
    var roll: Float = 0
    var meshPoints = 0
    var latencyMs: Double = 0
    var rate: Double = 0
    var labels: [Label] = []
}

@MainActor final class BrowTrackingFeed: ObservableObject {
    @Published var snapshot: BrowTrackingSnapshot?
}

/// Labels the MediaPipe landmark indices next to the points the Metal engine draws, plus a head-pose and timing
/// readout and a colour legend. Developer view: English only, like Scan Debug.
struct BrowTrackingOverlayView: View {
    @ObservedObject var feed: BrowTrackingFeed

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let snapshot = feed.snapshot, snapshot.faceFound {
                    ForEach(Array(snapshot.labels.enumerated()), id: \.offset) { _, label in
                        Text(label.text)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 1)
                            .position(x: CGFloat(label.x) * proxy.size.width, y: CGFloat(label.y) * proxy.size.height - 9)
                    }
                }
                readout.padding(AppSpacing.small)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "MediaPipe face landmarker")
                .font(.caption2.weight(.bold))
            if let s = feed.snapshot, s.faceFound {
                Text(verbatim: String(format: "yaw %+.0f°  pitch %+.0f°  roll %+.0f°", s.yaw, s.pitch, s.roll))
                Text(verbatim: String(format: "%d points · %.0f ms · %.0f fps%@", s.meshPoints, s.latencyMs, s.rate,
                                      s.tracked ? "" : " · head turned too far"))
            } else {
                Text(verbatim: "No face")
            }
            legend("upper brow", .init(red: 1, green: 0.25, blue: 0.2))
            legend("lower brow", .init(red: 1, green: 0.6, blue: 0.1))
            legend("raw (before smoothing)", .init(white: 0.7))
            legend("fitted centerline", .init(red: 1, green: 0.9, blue: 0.1))
            legend("brow frame (shape area)", .init(red: 0.1, green: 0.85, blue: 1))
            legend("eye corners · iris · nose", .init(red: 1, green: 0.2, blue: 0.9))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: text)
        }
    }
}
