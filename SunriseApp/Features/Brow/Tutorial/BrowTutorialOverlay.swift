import SwiftUI

/// Brow tutorial overlay (UX spec 3.2 and 3.4), anchored to each brow through `BrowGuideFeed`: the guide outline all the
/// time, and per step a tool (spoolie, pencil, cotton bud) doing the step over the part of the brow it concerns.
/// The animation runs 3 s and rests 2 s, then repeats. Reduce Motion shows its last frame and a still 40% highlight.
struct BrowTutorialOverlay: View {
    @ObservedObject var feed: BrowGuideFeed
    let step: Int
    var paused = false
    /// Draws only the brow on this half of the screen (the tutorial's comparison); nil draws both.
    var side: HorizontalEdge?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cycle: Double = 5, animation: Double = 3, pulsePeriod: Double = 2

    var body: some View {
        let still = reduceMotion || paused
        TimelineView(.animation(paused: still)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let local = reduceMotion ? Self.animation : time.truncatingRemainder(dividingBy: Self.cycle)
            let progress = min(1, local / Self.animation)
            GeometryReader { proxy in
                let all = feed.snapshot?.brows ?? []
                // The snapshot lists the screen's left brow first. With only one brow seen (a turned face), it is shown
                // only when it is on the side asked for, so the guide never lands on the other brow.
                let picked: [BrowGuideSnapshot.Brow] = switch (side, all.count) {
                case (nil, _): all
                case (let side?, 2): [side == .leading ? all[0] : all[1]]
                case (let side?, 1): ((all[0].upper.first?.x ?? 0.5) < 0.5) == (side == .leading) ? all : []
                default: []
                }
                let brows = picked.compactMap { Shape(brow: $0, size: proxy.size) }
                ZStack {
                    Canvas { g, _ in
                        // A soft dark edge keeps the white guide readable on bright skin and under the ring light.
                        g.addFilter(.shadow(color: .black.opacity(0.35), radius: 1.5, x: 0, y: 0))
                        for b in brows { draw(&g, b, time: time, progress: progress, still: reduceMotion) }
                    }
                    ForEach(brows.indices, id: \.self) { i in tool(brows[i], progress: progress) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Geometry

    /// One brow in view points: its outline, centreline and the fraction of the way along it where the arch is.
    struct Shape {
        let upper: [CGPoint], lower: [CGPoint]
        let height: CGFloat
        let arch: Double
        /// The brow's length in points and its slope (degrees, head to tail), so tools and marks scale and tilt with this face.
        let length: CGFloat
        let angle: Double
        /// 1 for an average brow on screen; bigger or smaller with the face's size and distance.
        var scale: CGFloat { max(0.55, min(1.7, length / 95)) }

        init?(brow: BrowGuideSnapshot.Brow, size: CGSize) {
            func scaled(_ p: [CGPoint]) -> [CGPoint] { p.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } }
            // Chaikin smoothing: the guide is the brow's own outline without landmark jitter or kinks.
            let up = Self.smooth(scaled(brow.upper)), low = Self.smooth(scaled(brow.lower))
            guard up.count > 1, low.count > 1 else { return nil }
            upper = up; lower = low
            let mid = (0...20).map { i in Self.point(up, Double(i) / 20).y + Self.point(low, Double(i) / 20).y }
            let top = mid.enumerated().min { $0.element < $1.element }?.offset ?? 10
            arch = max(0.4, min(0.7, Double(top) / 20))
            let head = Self.point(up, 0), tail = Self.point(up, 1)
            length = hypot(tail.x - head.x, tail.y - head.y)
            angle = atan2(Double(tail.y - head.y), Double(tail.x - head.x)) * 180 / .pi
            height = max(6, abs(Self.point(up, 0.5).y - Self.point(low, 0.5).y))
        }

        static func smooth(_ poly: [CGPoint], rounds: Int = 2) -> [CGPoint] {
            var p = poly
            for _ in 0..<rounds where p.count > 2 {
                var q = [p[0]]
                for i in 0..<(p.count - 1) {
                    let a = p[i], b = p[i + 1]
                    q.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                    q.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
                }
                q.append(p[p.count - 1])
                p = q
            }
            return p
        }

        static func point(_ poly: [CGPoint], _ f: Double) -> CGPoint {
            let lengths = zip(poly, poly.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
            let total = lengths.reduce(0, +)
            guard total > 0 else { return poly[0] }
            var left = CGFloat(max(0, min(1, f))) * total
            for (i, l) in lengths.enumerated() {
                if left <= l || i == lengths.count - 1 {
                    let k = l > 0 ? min(1, left / l) : 0
                    return CGPoint(x: poly[i].x + (poly[i + 1].x - poly[i].x) * k, y: poly[i].y + (poly[i + 1].y - poly[i].y) * k)
                }
                left -= l
            }
            return poly[0]
        }

        func center(_ f: Double) -> CGPoint {
            let a = Self.point(upper, f), b = Self.point(lower, f)
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        /// The outline between two fractions of the way along the brow.
        func region(_ from: Double, _ to: Double) -> Path {
            let steps = 12
            let top = (0...steps).map { Self.point(upper, from + (to - from) * Double($0) / Double(steps)) }
            let bottom = (0...steps).map { Self.point(lower, from + (to - from) * Double($0) / Double(steps)) }
            var p = Path()
            p.addLines(top); p.addLines(bottom.reversed()); p.closeSubpath()
            return p
        }
        var outline: Path { region(0, 1) }
        var marks: [Double] { [0, arch, 1] }
    }

    // MARK: Drawing

    private func dotted(_ scale: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: 2 * scale, lineCap: .round, dash: [0.1, 6 * scale]) }

    private func pulse(_ time: Double, still: Bool) -> Double {
        still ? 0.4 : 0.2 + 0.3 * (0.5 - 0.5 * cos(2 * .pi * time / Self.pulsePeriod))
    }

    private func draw(_ g: inout GraphicsContext, _ b: Shape, time: Double, progress: Double, still: Bool) {
        let glow = AppColors.flamingo
        switch step {
        case 2: g.fill(b.region(b.arch, 1), with: .color(glow.opacity(pulse(time, still: still))))
        case 3: g.fill(b.region(0, b.arch), with: .color(glow.opacity(pulse(time, still: still))))
        case 4:
            // Just outside the outline: a band, not the brow.
            g.stroke(b.outline, with: .color(glow.opacity(pulse(time, still: still))), lineWidth: max(10 * b.scale, b.height * 0.9))
        default: break
        }
        g.stroke(b.outline, with: .color(AppColors.snow.opacity(0.95)), style: dotted(b.scale))
        if step >= 1 {
            for (i, f) in b.marks.enumerated() where step > 1 || still || progress > Double(i) / 3 {
                let c = b.center(f)
                let r: CGFloat = 4.5 * b.scale
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(glow))
                g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white), lineWidth: 1.5)
            }
        }
        if step == 2 {
            // The strokes the pencil has made so far, arch to tail.
            let reach = b.arch + (1 - b.arch) * progress
            for k in 0..<6 {
                let f = b.arch + (reach - b.arch) * Double(k) / 5
                guard f <= reach else { continue }
                let c = b.center(f)
                var s = Path(); s.move(to: CGPoint(x: c.x - 3, y: c.y + b.height * 0.25)); s.addLine(to: CGPoint(x: c.x + 3, y: c.y - b.height * 0.25))
                g.stroke(s, with: .color(glow), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    // MARK: Tools

    /// Where the tool's working end is and how it moves, per step.
    private func spot(_ b: Shape, progress p: Double) -> (point: CGPoint, press: Double) {
        switch step {
        case 0:
            // Upward flicks through the brow, front to tail.
            let sweep = (p * 6).truncatingRemainder(dividingBy: 1)
            let base = b.center(p)
            return (CGPoint(x: base.x, y: base.y + b.height * (0.9 - 1.8 * sweep)), 1)
        case 1:
            let i = min(2, Int(p * 3)), u = (p * 3).truncatingRemainder(dividingBy: 1)
            return (b.center(b.marks[i]), sin(.pi * min(1, u * 1.2)))
        case 2:
            let f = b.arch + (1 - b.arch) * p
            let wobble = sin(p * 40) * b.height * 0.25
            let c = b.center(f)
            return (CGPoint(x: c.x, y: c.y + wobble), 1)
        case 3:
            let f = b.arch * (1 - p)
            let c = b.center(f)
            return (CGPoint(x: c.x, y: c.y + sin(p * 30) * b.height * 0.3), 1)
        default:
            let c = Shape.point(b.upper, p)
            return (CGPoint(x: c.x, y: c.y - b.height * 0.7), 1)
        }
    }

    @ViewBuilder private func tool(_ b: Shape, progress p: Double) -> some View {
        let s = spot(b, progress: p)
        if step == 0 || step == 3 {
            // Handle to the left, bristles to the right: the bristles' tip is the point.
            let k = b.scale
            SpoolieIcon()
                .frame(width: SpoolieIcon.size.width, height: SpoolieIcon.size.height)
                .scaleEffect(k, anchor: UnitPoint(x: 0.97, y: 0.5))
                .rotationEffect(.degrees(-18 + b.angle * 0.5), anchor: UnitPoint(x: 0.97, y: 0.5))
                .position(x: s.point.x - (SpoolieIcon.size.width / 2 - 3) * k, y: s.point.y)
        } else {
            let symbol = step == 4 ? "pencil.tip" : "pencil"
            Image(systemName: symbol)
                .font(.system(size: 30 * b.scale))
                .foregroundStyle(AppColors.snow)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .rotationEffect(.degrees((step == 4 ? 20 : 0) + b.angle * 0.5))
                .scaleEffect(1 - 0.1 * (1 - s.press))
                // The tool's working end is near its lower left: put that on the point, lifted a little when not pressing.
                .position(x: s.point.x + 11 * b.scale, y: s.point.y - 13 * b.scale - 8 * (1 - s.press))
        }
    }
}

/// A spoolie drawn like the design's: a ribbed raspberry handle, a small metal collar, a thin wire and a fluffy cream brush.
struct SpoolieIcon: View {
    static let size = CGSize(width: 112, height: 30)
    private static let handle = Color(red: 0xC4 / 255, green: 0x24 / 255, blue: 0x5C / 255)
    private static let cream = Color(red: 0xF4 / 255, green: 0xEE / 255, blue: 0xE4 / 255)

    var body: some View {
        Canvas { g, size in
            let mid = size.height / 2
            // Ribbed handle.
            let grip = CGRect(x: 0, y: 3, width: 36, height: size.height - 6)
            g.fill(Path(roundedRect: grip, cornerRadius: 7), with: .color(Self.handle))
            g.drawLayer { layer in
                layer.clip(to: Path(roundedRect: grip, cornerRadius: 7))
                var x: CGFloat = 3
                while x < grip.maxX {
                    var rib = Path(); rib.move(to: CGPoint(x: x, y: grip.minY)); rib.addLine(to: CGPoint(x: x, y: grip.maxY))
                    layer.stroke(rib, with: .color(.black.opacity(0.28)), lineWidth: 1.4)
                    x += 4.5
                }
                layer.fill(Path(CGRect(x: grip.minX, y: grip.minY, width: grip.width, height: 5)), with: .color(.white.opacity(0.22)))
            }
            // Collar and wire.
            let collar = CGRect(x: 36, y: mid - 6, width: 12, height: 12)
            g.fill(Path(roundedRect: collar, cornerRadius: 2.5), with: .color(.white.opacity(0.92)))
            g.stroke(Path(roundedRect: collar, cornerRadius: 2.5), with: .color(.gray.opacity(0.7)), lineWidth: 0.8)
            var wire = Path(); wire.move(to: CGPoint(x: 48, y: mid)); wire.addLine(to: CGPoint(x: 86, y: mid))
            g.stroke(wire, with: .color(.gray.opacity(0.8)), lineWidth: 2)
            g.stroke(wire, with: .color(.white), lineWidth: 1)
            // Brush: an oval of cream bristles.
            let brush = CGRect(x: 82, y: mid - 7.5, width: 28, height: 15)
            g.fill(Path(ellipseIn: brush), with: .color(Self.cream))
            for i in 0..<9 {
                let x = brush.minX + 4 + CGFloat(i) * 2.6
                var hair = Path(); hair.move(to: CGPoint(x: x, y: brush.minY + 2)); hair.addLine(to: CGPoint(x: x + 1, y: brush.maxY - 2))
                g.stroke(hair, with: .color(.gray.opacity(0.25)), lineWidth: 0.7)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
