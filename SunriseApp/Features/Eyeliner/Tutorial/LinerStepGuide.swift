import SwiftUI

/// The three eyeliner steps from the UX spec. Captions are the same for every look: the look only changes where the
/// dots and the outline sit on the face.
enum LinerTutorialStep: Int, CaseIterable {
    case markDots, connect, fill

    static var count: Int { allCases.count }

    var caption: LocalizedStringKey {
        switch self {
        case .markDots: "Mark 4 points along the eyeliner guide."
        case .connect: "Connect the dots to create a thin eyeliner outline."
        case .fill: "Fill in the eyeliner frame, keeping it close to your lashes."
        }
    }

    var label: LocalizedStringKey { "STEP \(rawValue + 1) OF \(Self.count)" }
}

/// Where the guide's dots, lines and filled band sit on one eye, in the overlay's image space.
struct LinerStepGeometry {
    /// The lash line, inner start to outer corner.
    let lash: [CGPoint]
    /// The lower line of puppy, foxy and arabian, from its start.
    let lower: [CGPoint]
    /// The closed liner outlines: the upper liner with its wing merged in, and the wing on its own when it starts apart
    /// from the liner (`upperLiner` alone stops at the outer corner and leaves the wing out).
    let shapes: [[CGPoint]]
    /// Winged looks: the outer corner, the wing's end and a point on the lid (the wing's triangle). Other looks: four
    /// points along the lash curve, inner corner first, then the lower line's start when it has one.
    let dots: [CGPoint]
    /// Which dot is the wing's end (drawn a little bigger); nil without a wing.
    let tipIndex: Int?
    /// What the pen follows on the fill step: the lash line, or the wing's triangle.
    let penPath: [CGPoint]

    /// `showsLower`: only the look that really has a lower line (Arabian) gets its dot, dashes and fill.
    /// `wing`: the look is taught by its wing only (`LinerLook.hasWing`): dots, outline and fill are the triangle at the
    /// outer corner. Otherwise only the line along the lash curve is taught, with no dot toward a wing.
    init(_ guide: LinerGuide, showsLower: Bool = false, wing: Bool = false) {
        // `upperLiner` is the lash-line side followed by the outer edge reversed, so its first half is the lash line.
        let lash = Array(guide.upperLiner.prefix(guide.upperLiner.count / 2))
        let lower = showsLower ? Array(guide.lowerLiner.prefix(guide.lowerLiner.count / 2)) : []
        self.lash = lash
        if wing, let tip = guide.anchors.wingTip, lash.count > 2, let outer = lash.last {
            // The wing, shaped by the eye: from the outer corner straight out to the tip, back to the lid about 70% along
            // the lash line in a soft curve that dips toward the eye, then along the lash line itself to the outer corner.
            // Dots stay three: outer corner, tip, lid point.
            let lidIndex = Int(Double(lash.count - 1) * 0.7)
            let lid = lash[lidIndex]
            let control = CGPoint(x: (tip.x + lid.x) / 2 + (outer.x - (tip.x + lid.x) / 2) * 0.35,
                                  y: (tip.y + lid.y) / 2 + (outer.y - (tip.y + lid.y) / 2) * 0.35)
            let top = (1...9).map { i -> CGPoint in
                let t = CGFloat(i) / 10, u = 1 - t
                return CGPoint(x: u * u * tip.x + 2 * u * t * control.x + t * t * lid.x,
                               y: u * u * tip.y + 2 * u * t * control.y + t * t * lid.y)
            }
            let wingShape = [outer, tip] + top + Array(lash[lidIndex...])
            self.lower = []
            self.shapes = [wingShape]
            self.dots = [outer, tip, lid]
            self.tipIndex = 1
            self.penPath = wingShape
            return
        }
        self.lower = lower
        // The line along the lash curve only: `upperLiner` stops at the outer corner, without the wing.
        self.shapes = [guide.upperLiner]
        var dots: [CGPoint] = []
        if lash.count > 3, let last = lash.last {
            dots = [lash[0], lash[(lash.count - 1) / 3], lash[(lash.count - 1) * 2 / 3], last]
        } else {
            dots = [guide.anchors.upperStart, guide.anchors.outerCorner]
        }
        if let start = lower.first { dots.append(start) }
        self.dots = dots
        self.tipIndex = nil
        self.penPath = lash
    }
}

/// The detector's "could not start" note. Its own view, so only it listens to the model's published changes.
private struct UnavailableNote: View {
    @ObservedObject var model: LinerOverlayModel

    var body: some View {
        if let reason = model.unavailableReason {
            // The eye detector could not start: say so instead of silently drawing nothing.
            Text(reason).font(.footnote).padding(8).background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white).frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// Counts only the time the animation actually ran, so it carries on from where it stopped after a pause.
final class StepClock {
    private var last: Date?
    private var elapsed: TimeInterval = 0

    func advance(to now: Date, paused: Bool) -> TimeInterval {
        // A long gap (the timeline was paused) must not count: cap one tick.
        if let last, !paused { elapsed += min(now.timeIntervalSince(last), 0.25) }
        last = now
        return elapsed
    }
}

/// The eyeliner guide for one step, drawn over the camera: the guide's dots, and the step's animation (3 s, then a 2 s
/// pause, repeating). The animation is only a demonstration; nothing is drawn on the lid. Reduce Motion shows the last
/// frame as a still picture.
struct LinerStepGuide: View {
    /// Not observed: the canvas reads the newest frame on every tick, so a published frame must not rebuild this view too.
    let model: LinerOverlayModel
    let step: LinerTutorialStep
    /// A camera message is showing, or the phone is hot: the animation holds where it is.
    var paused = false
    /// A camera message is showing: the whole guide fades to 30%.
    var dimmed = false
    /// Draws only on this half of the view (the tutorial's side-by-side comparison).
    var side: HorizontalEdge?
    /// The look has a lower line, so the guide shows its dot, outline and fill.
    var showsLower = false
    /// The look is winged: the guide teaches only the wing's triangle (`LinerStepGeometry(wing:)`).
    var teachesWing = false
    @Environment(\.cameraZoom) private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = StepClock()

    static let playLength: TimeInterval = 3
    static let loopLength: TimeInterval = 5
    private let pink = Color(red: 0.93, green: 0.38, blue: 0.68)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Always ticking, so the dots keep following the face while the animation is held. The animation's own
                // clock only runs while the liner has a fresh frame to draw on: a gap in tracking must not use it up unseen.
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 / 30 : 1 / 60)) { timeline in
                    let live = model.frame.map { CACurrentMediaTime() - $0.receivedAt <= LinerOverlayRenderer.maxAge } ?? false
                    let elapsed = clock.advance(to: timeline.date, paused: paused || reduceMotion || !live)
                    canvas(elapsed: elapsed, stamp: model.frame?.receivedAt ?? 0)
                }
                UnavailableNote(model: model)
            }
            // The overlay model builds the liner in this view's size, so it must be told before it can run.
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
            guard let frame = model.frame, CACurrentMediaTime() - frame.receivedAt <= LinerOverlayRenderer.maxAge else { return }
            if let side {
                let cut = frame.splitX(fallback: size.width / 2)
                context.clip(to: Path(CGRect(x: side == .leading ? 0 : cut, y: 0,
                                             width: side == .leading ? cut : size.width - cut, height: size.height)))
            }
            // Reduce Motion: the last frame of the animation, and a still highlight at 40%.
            let loop = reduceMotion ? Self.playLength : elapsed.truncatingRemainder(dividingBy: Self.loopLength)
            let progress = min(loop / Self.playLength, 1)
            let playing = !reduceMotion && loop < Self.playLength
            let pulse = reduceMotion ? 0.4 : 0.35 - 0.15 * cos(elapsed * .pi)
            let thin = 1 / zoom
            // A soft dark edge keeps the white guide readable on bright skin, under the ring light and on dark skin alike. It is a
            // canvas filter, not a `.shadow` modifier, so the canvas itself is redrawn every tick.
            context.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0))
            for eye in frame.eyes where eye.alpha > 0.05 {
                let geometry = LinerStepGeometry(eye.guide, showsLower: showsLower, wing: teachesWing)
                let map = { (points: [CGPoint]) in points.map { frame.mapping.map($0) } }
                let inner = frame.mapping.map(eye.guide.anchors.innerCorner)
                let outer = frame.mapping.map(eye.guide.anchors.outerCorner)
                let eyeWidth = hypot(outer.x - inner.x, outer.y - inner.y)
                // The face's roll on screen (the eye axis, whichever way this eye faces): the pen leans with the head.
                var roll = atan2(outer.y - inner.y, outer.x - inner.x) * 180 / .pi
                if roll > 90 { roll -= 180 } else if roll < -90 { roll += 180 }
                let dots = map(geometry.dots)
                var penTip: CGPoint?

                switch step {
                case .markDots:
                    if playing { penTip = tapAnimation(&context, dots: dots, progress: progress, eyeWidth: eyeWidth, thin: thin) }
                case .connect:
                    let paths = (geometry.shapes.map { Self.path(map($0), closed: true) } + [Self.path(map(geometry.lower))])
                        .filter { !$0.isEmpty }
                        .map { $0.trimmedPath(from: 0, to: progress) }
                    let style = StrokeStyle(lineWidth: max(eyeWidth * 0.018, 1.2 * thin), lineCap: .round,
                                            dash: [max(eyeWidth * 0.03, 2 * thin), max(eyeWidth * 0.04, 3 * thin)])
                    for path in paths { context.stroke(path, with: .color(.white), style: style) }
                    if playing, let first = paths.first { penTip = first.currentPoint }
                case .fill:
                    for shape in geometry.shapes where shape.count > 2 {
                        let outline = Self.path(map(shape), closed: true)
                        context.stroke(outline, with: .color(.white.opacity(0.8)),
                                       style: StrokeStyle(lineWidth: max(eyeWidth * 0.014, 1 * thin), lineCap: .round))
                        context.fill(outline, with: .color(pink.opacity(pulse)))
                    }
                    if geometry.lower.count > 1 {
                        let lowerPath = Self.path(map(geometry.lower))
                        context.stroke(lowerPath, with: .color(pink.opacity(pulse + 0.2)),
                                       style: StrokeStyle(lineWidth: max(eyeWidth * 0.035, 2 * thin), lineCap: .round))
                        context.stroke(lowerPath, with: .color(.white.opacity(0.8)),
                                       style: StrokeStyle(lineWidth: max(eyeWidth * 0.012, 1 * thin), lineCap: .round))
                    }
                    let pen = map(geometry.penPath)
                    if playing, pen.count > 1 {
                        // Back and forth along the lash line (or round the wing), a bit under two passes in 3 s.
                        let along = 0.5 - 0.5 * cos(progress * .pi * 3)
                        penTip = Self.path(pen).trimmedPath(from: 0, to: along).currentPoint
                    }
                }

                drawDots(&context, dots: dots, tipIndex: geometry.tipIndex, eyeWidth: eyeWidth, thin: thin, pulse: pulse)
                if let penTip { drawPen(&context, tip: penTip, eyeWidth: eyeWidth, roll: roll) }
            }
        }
    }

    /// Step 1: the pen goes to each dot in order and taps it; a ring spreads from the tapped dot. Returns the pen's tip.
    private func tapAnimation(_ context: inout GraphicsContext, dots: [CGPoint], progress: Double, eyeWidth: Double, thin: CGFloat) -> CGPoint? {
        guard !dots.isEmpty else { return nil }
        let slot = 1 / Double(dots.count)
        let index = min(Int(progress / slot), dots.count - 1)
        let local = (progress - Double(index) * slot) / slot
        let target = dots[index]
        let from = index == 0 ? target : dots[index - 1]
        // First 40% of the slot: travel; the rest: tap, with a ring growing and fading.
        let travel = min(local / 0.4, 1)
        let tip = CGPoint(x: from.x + (target.x - from.x) * travel, y: from.y + (target.y - from.y) * travel)
        if local > 0.4 {
            let ring = (local - 0.4) / 0.6
            let radius = max(eyeWidth * (0.03 + 0.08 * ring), 2 * thin)
            let rect = CGRect(x: target.x - radius, y: target.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(pink.opacity(1 - ring)), style: StrokeStyle(lineWidth: max(eyeWidth * 0.012, 1.5 * thin)))
        }
        return tip
    }

    private func drawDots(_ context: inout GraphicsContext, dots: [CGPoint], tipIndex: Int?, eyeWidth: Double, thin: CGFloat, pulse: Double) {
        for (index, point) in dots.enumerated() {
            // The wing's end is a little bigger than the others.
            let isTip = index == tipIndex
            // Dots scale with the eye on screen; the floor keeps them visible when the eye is tiny.
            let radius = max(eyeWidth * (isTip ? 0.034 : 0.025), (isTip ? 1.8 : 1.4) * thin)
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(pink))
            context.stroke(dot, with: .color(.white), style: StrokeStyle(lineWidth: max(radius * 0.3, 0.6 * thin)))
            // The order to work in: numbers on the first two steps, and "Start here" on the inner corner on all three.
            let fontSize = min(max(eyeWidth * 0.11, 9), 15)
            if index == 0 {
                let halo = radius * (2.2 + 0.8 * pulse)
                context.stroke(Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                               with: .color(pink.opacity(0.9)), style: StrokeStyle(lineWidth: max(1.4 * thin, 1)))
                context.draw(Text("Start here").font(.system(size: fontSize, weight: .semibold)).foregroundStyle(.white),
                             at: CGPoint(x: point.x, y: point.y - radius * 2.2 - fontSize * 1.1))
            } else if step != .fill {
                context.draw(Text("\(index + 1)").font(.system(size: fontSize, weight: .semibold)).foregroundStyle(.white),
                             at: CGPoint(x: point.x, y: point.y - radius - fontSize * 0.9))
            }
        }
    }

    /// A simple liner pen, tilted, with its tip on `tip`.
    private func drawPen(_ context: inout GraphicsContext, tip: CGPoint, eyeWidth: Double, roll: Double) {
        let length = min(max(eyeWidth * 0.9, 36), 90)
        let width = length * 0.12
        var pen = context
        pen.translateBy(x: tip.x, y: tip.y)
        pen.rotate(by: .degrees(30 + roll))
        let body = Path(roundedRect: CGRect(x: -width / 2, y: -length, width: width, height: length * 0.82), cornerRadius: width / 2)
        pen.fill(body, with: .color(AppColors.snow))
        pen.stroke(body, with: .color(AppColors.wine.opacity(0.6)), lineWidth: 0.8)
        var nib = Path()
        nib.move(to: CGPoint(x: -width / 2, y: -length * 0.18))
        nib.addLine(to: CGPoint(x: width / 2, y: -length * 0.18))
        nib.addLine(to: .zero)
        nib.closeSubpath()
        pen.fill(nib, with: .color(AppColors.wine))
        pen.fill(Path(CGRect(x: -width / 2, y: -length * 0.55, width: width, height: length * 0.08)), with: .color(AppColors.flamingo))
    }

    private static func path(_ points: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }
}
