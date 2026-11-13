import SwiftUI

/// The lips guide for one step, drawn over the camera on the person's own lips: the marks to make (step 1), the dashed
/// outline to draw (step 2) and the area to fill (step 3), each with a short animation (3 s, then a 2 s pause, repeating,
/// like the eyeliner's). Nothing is drawn on the lips themselves. Reduce Motion shows the last frame as a still picture.
struct LipStepGuide: View {
    /// Not observed: the canvas reads the newest frame on every tick, so a published frame must not rebuild this view too.
    let model: LipOverlayModel
    /// 0: mark, 1: connect, 2: fill (`GuidedTutorialModel.lipLessons`).
    let step: Int
    let style: LipStyle
    /// A camera message is showing, or the phone is hot: the animation holds where it is.
    var paused = false
    /// A camera message is showing: the whole guide fades to 30%.
    var dimmed = false
    /// Draws only this half of the lips (the tutorial's one side at a time).
    var side: HorizontalEdge?
    @Environment(\.cameraZoom) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = StepClock()

    /// A frame older than this is not drawn (the face was lost).
    static let maxAge: CFTimeInterval = 0.4
    /// Ring positions that get a mark: the corners, the cupid's bow and the middle of the lower lip.
    static let marks = [LipOverlayFrame.rightCorner, LipOverlayFrame.rightPeak, LipOverlayFrame.upperMiddle, LipOverlayFrame.leftPeak,
                        LipOverlayFrame.leftCorner, LipOverlayFrame.lowerMiddle]
    private let pink = Color(red: 0.93, green: 0.38, blue: 0.68)

    var body: some View {
        GeometryReader { proxy in
            // Always ticking, so the guide keeps following the lips while the animation is held. The animation's own clock
            // only runs while there is a fresh frame to draw on.
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 / 30 : 1 / 60)) { timeline in
                let live = model.frame.map { CACurrentMediaTime() - $0.receivedAt <= Self.maxAge } ?? false
                let elapsed = clock.advance(to: timeline.date, paused: paused || reduceMotion || !live)
                canvas(elapsed: elapsed, stamp: model.frame?.receivedAt ?? 0)
            }
            // The overlay model maps the lips to this view's size, so it must be told before it can run.
            .onChange(of: proxy.size, initial: true) { _, size in model.viewport = size }
        }
        .opacity(dimmed ? 0.3 : 1)
        .animation(.easeInOut(duration: 0.25), value: dimmed)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// `stamp` is the newest frame's time: it changes with every tracking frame, so the canvas has a new input to redraw on
    /// even while the animation's own clock is held.
    private func canvas(elapsed: TimeInterval, stamp: CFTimeInterval) -> some View {
        Canvas { context, size in
            _ = stamp
            guard let frame = model.frame, CACurrentMediaTime() - frame.receivedAt <= Self.maxAge,
                  frame.outer.count == LipLandmarks.ringCount, frame.inner.count == LipLandmarks.ringCount else { return }
            // Reduce Motion: the last frame of the animation, and a still highlight at 40%.
            let loop = reduceMotion ? LinerStepGuide.playLength : elapsed.truncatingRemainder(dividingBy: LinerStepGuide.loopLength)
            let progress = min(loop / LinerStepGuide.playLength, 1)
            let playing = !reduceMotion && loop < LinerStepGuide.playLength
            let pulse = reduceMotion ? 0.4 : 0.35 - 0.15 * cos(elapsed * .pi)
            let thin = 1 / zoom
            let width = frame.width
            let ring = LipShape.guideRing(frame, style: style)
            let cut = frame.splitX
            // A soft dark edge keeps the white guide readable on light and dark lips alike.
            context.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0))

            // The outline and the fill, cut at the middle of the lips when one side is being done.
            context.drawLayer { half in
                if let side {
                    half.clip(to: Path(CGRect(x: side == .leading ? 0 : cut, y: 0,
                                              width: side == .leading ? cut : size.width - cut, height: size.height)))
                }
                let outline = CGMutablePath()
                LipShape.addSmooth(ring, to: outline)
                if step == 1 {
                    half.stroke(Path(outline).trimmedPath(from: 0, to: progress), with: .color(.white),
                                style: StrokeStyle(lineWidth: max(width * 0.012, 1.2 * thin), lineCap: .round,
                                                   dash: [max(width * 0.02, 2 * thin), max(width * 0.028, 3 * thin)]))
                } else if step >= 2 {
                    half.fill(Path(LipShape.ring(ring, minus: frame.inner)), with: .color(pink.opacity(pulse)), style: FillStyle(eoFill: true))
                    half.stroke(Path(outline), with: .color(.white.opacity(0.8)),
                                style: StrokeStyle(lineWidth: max(width * 0.01, 1 * thin), lineCap: .round))
                }
            }

            // The marks of the side being done (the ones in the middle belong to both sides).
            let radius = max(width * 0.02, 1.6 * thin)
            let dots = Self.marks.map { ring[$0] }.filter { point in
                guard let side else { return true }
                return side == .leading ? point.x <= cut + radius : point.x >= cut - radius
            }
            if step == 0, playing, !dots.isEmpty {
                // Each mark in turn gets a ring that spreads and fades: where to tap the lipstick.
                let slot = 1 / Double(dots.count)
                let index = min(Int(progress / slot), dots.count - 1)
                let local = (progress - Double(index) * slot) / slot
                let spread = max(width * (0.03 + 0.07 * local), 2 * thin)
                let target = dots[index]
                context.stroke(Path(ellipseIn: CGRect(x: target.x - spread, y: target.y - spread, width: spread * 2, height: spread * 2)),
                               with: .color(pink.opacity(1 - local)), style: StrokeStyle(lineWidth: max(width * 0.01, 1.5 * thin)))
            }
            for point in dots {
                let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(pink))
                context.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: max(radius * 0.3, 0.6 * thin)))
            }
        }
    }
}
