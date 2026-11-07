// -Nimah: Blush tab of the guided tutorial (moved from GuidedTutorialView.swift, no change). The shared tutorial screen,
// tabs, comparison and photo are in TryOn/Shared/Tutorial.
import SwiftUI

extension GuidedTutorialModel {
    /// The Blush tab's two steps (UX spec 3.5). "Dab" works for cream and powder alike; the caption is the whole instruction.
    static let blushLessons = [
        FaceGuideLesson(title: String(localized: "Tap a little blush into the small circle."),
                        instruction: String(localized: "Just a tiny bit, babe. You can always add more, so starting light is the secret.")),
        FaceGuideLesson(title: String(localized: "Now dab outward, blending into your skin."),
                        instruction: String(localized: "Soft little taps, no rush. You're doing so good.")),
        FaceGuideLesson(title: String(localized: "Buff in small circles, sweeping out, until the edge melts away."),
                        instruction: String(localized: "See that glow coming in? Trust the process, it's all coming together.")),
    ]
}

/// Blush tutorial overlay (UX spec 3.2 and 3.5), anchored to each cheek through `BlushGuideFeed`.
/// Step 1: the inner dotted circle, and a fingertip dabbing inside it with a pink tap ring.
/// Step 2: the outer dotted line too, the ring between them pulsing 20%-50% every 2 s, and the fingertip dabbing outward.
/// The dab animation runs 3 s, rests 2 s and repeats. Reduce Motion shows its last frame and a still 40% highlight.
struct BlushTutorialOverlay: View {
    @ObservedObject var feed: BlushGuideFeed
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thermal = ProcessInfo.processInfo.thermalState

    static let cycle: Double = 5, animation: Double = 3, pulsePeriod: Double = 2
    /// Three dabs start at these times within the cycle, each `dab` seconds long.
    static let dabStarts: [Double] = [0.25, 1.15, 2.05], dab: Double = 0.8

    var body: some View {
        // Only a critical phone pauses the loop: AR plus MediaPipe reach `.serious` quickly, and a still guide reads as
        // broken. The overlay itself stays.
        let paused = reduceMotion || thermal == .critical
        TimelineView(.animation(paused: paused)) { context in
            let t = paused ? Self.animation - 0.001 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Canvas { g, _ in
                    // A soft dark edge keeps the white guide readable on bright skin and under the ring light.
                    g.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0))
                    draw(&g, time: t, still: paused)
                }
                if let cheeks = feed.snapshot?.cheeks {
                    ForEach(cheeks.indices, id: \.self) { i in fingertip(cheeks[i], time: t, still: paused) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermal = ProcessInfo.processInfo.thermalState
        }
    }

    private func path(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for q in points.dropFirst() { p.addLine(to: q) }
        p.closeSubpath()
        return p
    }
    private var dotted: StrokeStyle { StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.1, 7]) }

    private func draw(_ g: inout GraphicsContext, time t: Double, still: Bool) {
        guard let cheeks = feed.snapshot?.cheeks else { return }
        for c in cheeks {
            let inner = path(c.inner), outer = path(c.outer)
            if step >= 1 {
                // The ring between the two lines: 20% to 50% and back every 2 s, or a still 40%.
                let wave = 0.5 - 0.5 * cos(2 * .pi * t / Self.pulsePeriod)
                var ring = outer; ring.addPath(inner)
                g.fill(ring, with: .color(AppColors.flamingo.opacity(still ? 0.4 : 0.2 + 0.3 * wave)), style: FillStyle(eoFill: true))
                g.stroke(outer, with: .color(AppColors.snow.opacity(0.95)), style: dotted)
            }
            g.stroke(inner, with: .color(AppColors.snow.opacity(step >= 1 ? 0.7 : 0.95)), style: dotted)
            if step == 2 {
                // The way to sweep: from the centre of the cheek out along the look's direction, dashes marching outward.
                let end = CGPoint(x: c.center.x + (c.outward.x - c.center.x) * 1.15, y: c.center.y + (c.outward.y - c.center.y) * 1.15)
                var line = Path(); line.move(to: c.center); line.addLine(to: end)
                let phase = still ? 0 : -t * 18
                g.stroke(line, with: .color(AppColors.snow.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6], dashPhase: phase))
                let angle = atan2(end.y - c.center.y, end.x - c.center.x), head: CGFloat = 11
                var arrow = Path()
                arrow.move(to: CGPoint(x: end.x - head * cos(angle - 0.5), y: end.y - head * sin(angle - 0.5)))
                arrow.addLine(to: end)
                arrow.addLine(to: CGPoint(x: end.x - head * cos(angle + 0.5), y: end.y - head * sin(angle + 0.5)))
                g.stroke(arrow, with: .color(AppColors.snow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Where each of the three dabs lands: around the centre of the small circle, or stepping outward to the outer line.
    private func targets(_ c: BlushGuideSnapshot.Cheek) -> [CGPoint] {
        let d = CGPoint(x: c.outward.x - c.center.x, y: c.outward.y - c.center.y)
        func along(_ k: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: c.center.x + d.x * k - d.y * side, y: c.center.y + d.y * k + d.x * side)
        }
        return step == 0 ? [along(0), along(0.25, 0.2), along(-0.2, -0.15)] : [along(0.65), along(0.95, 0.15), along(1.25, -0.1)]
    }

    static func fingerPosition(_ points: [CGPoint], local: Double, index: Int, u: Double) -> CGPoint {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k) }
        if local < dabStarts[0] { return lerp(points[points.count - 1], points[0], local / dabStarts[0]) }
        return lerp(index > 0 ? points[index - 1] : points[0], points[index], min(1, u * 3))
    }

    @ViewBuilder private func fingertip(_ c: BlushGuideSnapshot.Cheek, time t: Double, still: Bool) -> some View {
        if step == 2 { buffing(c, time: t, still: still) } else { dabbing(c, time: t, still: still) }
    }

    /// Step 3: the fingertip sweeps outward along the look's direction twice in the 3 s, turning small circles as it goes.
    @ViewBuilder private func buffing(_ c: BlushGuideSnapshot.Cheek, time t: Double, still: Bool) -> some View {
        let d = CGPoint(x: c.outward.x - c.center.x, y: c.outward.y - c.center.y)
        let xs = c.outer.map(\.x)
        let k = max(0.7, min(1.6, ((xs.max() ?? 0) - (xs.min() ?? 0)) / 120))
        let local = still ? Self.animation * 0.7 : t.truncatingRemainder(dividingBy: Self.cycle)
        let p = min(1, local / Self.animation)
        let sweep = 0.1 + 1.0 * (p * 2).truncatingRemainder(dividingBy: 1)
        let swirl = p * 2 * .pi * 7
        let radius = hypot(d.x, d.y) * 0.1
        let target = CGPoint(x: c.center.x + d.x * sweep + cos(swirl) * radius, y: c.center.y + d.y * sweep + sin(swirl) * radius)
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 34 * k))
            .foregroundStyle(AppColors.snow)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(0.95)
            .position(x: target.x + 9 * k, y: target.y + 15 * k - 5 * k)
    }

    @ViewBuilder private func dabbing(_ c: BlushGuideSnapshot.Cheek, time t: Double, still: Bool) -> some View {
        let points = targets(c)
        let local = still ? Self.animation - 0.001 : t.truncatingRemainder(dividingBy: Self.cycle)
        // Which dab, how far into it (0...1), and how hard the finger presses (0 up, 1 on the skin).
        let index = Self.dabStarts.lastIndex { $0 <= local } ?? 0
        let u = max(0, min(1, (local - Self.dabStarts[index]) / Self.dab))
        let press = local < Self.dabStarts[0] ? 0 : sin(Double.pi * min(1, u * 1.25))
        // Before the first dab the finger glides back from where the last cycle ended; it never disappears, and it rests on
        // the last dab through the 2 s pause.
        let target = Self.fingerPosition(points, local: local, index: index, u: u)
        let visible: Double = 1
        let ringProgress = still ? 0.6 : max(0, min(1, (u - 0.35) / 0.65))
        // The finger and its ring scale with this cheek's size on screen (face size and distance).
        let xs = c.outer.map(\.x)
        let k = max(0.7, min(1.6, ((xs.max() ?? 0) - (xs.min() ?? 0)) / 120))
        ZStack {
            Circle()
                .stroke(AppColors.flamingo, lineWidth: 2.5)
                .frame(width: (10 + 30 * ringProgress) * k, height: (10 + 30 * ringProgress) * k)
                .opacity((still ? 0.6 : (u > 0.35 && local < Self.animation ? 1 - ringProgress : 0)) * visible)
                .position(points[index])
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 34 * k))
                .foregroundStyle(AppColors.snow)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .scaleEffect(1 - 0.08 * press)
                // The symbol's fingertip is near its top left: put that point on the cheek, lifted while not pressing.
                .position(x: target.x + 9 * k, y: target.y + 15 * k - 14 * k * (1 - press))
                .opacity(visible)
        }
    }
}
