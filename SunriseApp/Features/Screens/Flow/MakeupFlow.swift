// The one-tool makeup flow: pick a tool, try it on, photograph the desired look, prepare, follow the tutorial side by
// side, photograph the result, get feedback. Photos stay in memory for this run only; nothing is saved or uploaded.
import CoreImage
import SwiftUI
import UIKit

/// The two photos of one run. Owned by the root view and cleared when the flow returns home.
@MainActor final class MakeupFlowStore: ObservableObject {
    /// Taken after Try On with the chosen look drawn; nil when the camera could not take it (e.g. the Simulator).
    @Published var desired: UIImage?
    /// Taken after the tutorial with the real makeup on.
    @Published var result: UIImage?

    func store(_ image: UIImage?, for stage: CaptureStage) {
        switch stage {
        case .desired: desired = image
        case .result: result = image
        }
    }

    func image(for stage: CaptureStage) -> UIImage? {
        switch stage {
        case .desired: desired
        case .result: result
        }
    }

    /// -Nimah: the face measured at each shutter, for the blush feedback. Numbers only, memory only.
    var desiredScan: FaceScan?
    var resultScan: FaceScan?

    func store(_ scan: FaceScan?, for stage: CaptureStage) {
        switch stage {
        case .desired: desiredScan = scan
        case .result: resultScan = scan
        }
    }

    /// The bare camera at the desired-look shutter (no virtual makeup); the feedback's Before falls back to it when there is no try-on photo.
    var bare: UIImage?
    /// Developer read-out of each shutter (shown on the feedback screen with developer tools on).
    var diagnostics: [CaptureStage: CaptureDiagnostics] = [:]

    /// Where both eyes were on screen at each shutter (view points), to line the result photo up with the desired one.
    var eyes: [CaptureStage: EyePair] = [:]
    /// The result photo turned, scaled and moved so its eyes sit where the desired photo's eyes are: the Before / After
    /// slider shows this, so the split falls on the same place of the face. Nil when the eyes were not seen.
    var alignedResult: UIImage?
    /// The head's pose at each shutter (numbers only): the result photo must be taken in the desired photo's pose.
    var poses: [CaptureStage: CapturePoseReading] = [:]

    func reset() {
        desired = nil; result = nil; desiredScan = nil; resultScan = nil; bare = nil; diagnostics = [:]; eyes = [:]; alignedResult = nil; poses = [:]
    }
}

/// The two eye centres on screen, in view points (the photos are view-sized, so also photo points).
struct EyePair: Equatable, Sendable {
    var left: CGPoint
    var right: CGPoint
}

extension EyePair {
    /// The turn, scale and shift that carry `self` onto `target` (both eyes), or nil when it would be a big change
    /// (different poses, or an eye mis-read): then the photo is better left as taken.
    func transform(onto target: EyePair) -> CGAffineTransform? {
        let a = CGVector(dx: right.x - left.x, dy: right.y - left.y)
        let b = CGVector(dx: target.right.x - target.left.x, dy: target.right.y - target.left.y)
        let lengthA = hypot(a.dx, a.dy), lengthB = hypot(b.dx, b.dy)
        guard lengthA > 1, lengthB > 1 else { return nil }
        let scale = lengthB / lengthA
        var angle = atan2(b.dy, b.dx) - atan2(a.dy, a.dx)
        if angle > .pi { angle -= 2 * .pi } else if angle < -.pi { angle += 2 * .pi }
        guard (0.8...1.25).contains(scale), abs(angle) < 15 * .pi / 180 else { return nil }
        return CGAffineTransform(translationX: -left.x, y: -left.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: target.left.x, y: target.left.y))
    }

    /// `image` redrawn with its eyes on `target`'s eyes; uncovered edges are black.
    static func align(_ image: UIImage, from eyes: EyePair, to target: EyePair) -> UIImage? {
        guard let transform = eyes.transform(onto: target) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            context.cgContext.concatenate(transform)
            image.draw(at: .zero)
        }
    }
}

/// -Nimah: what happened at a shutter, for developers: whether the makeup engine's picture could be read, the target
/// outline and the face. English only, like the other developer views.
struct CaptureDiagnostics: Hashable, Sendable {
    enum Read: String, Sendable { case notTried = "not tried", read = "read", timedOut = "timed out" }
    var engine = false, layerShown = false, engineOn = false
    var read = Read.notTried
    var readTries = 0, readMilliseconds = 0
    var framesBefore = 0
    var outline = false, face = false
    /// The face was measured on the frame the photo was drawn from (else on the live frame after it).
    var sameFrame = false

    var line: String {
        "engine \(engine ? "yes" : "no") · layer \(layerShown ? "shown" : "hidden") · drawing \(engineOn ? "on" : "off") · "
            + "screen \(read.rawValue)\(readTries > 0 ? " (\(readTries)x, \(readMilliseconds) ms)" : "") · frames \(framesBefore) · "
            + "target \(outline ? "yes" : "no") · face \(face ? "yes" : "no") · frame \(sameFrame ? "same" : "live")"
    }
}

extension TutorialHandoff {
    /// The chosen style's name, e.g. "Sunkissed blush", for the flow's captions.
    var styleTitle: String {
        switch tool {
        case .blush: String(localized: "\(blushStyle?.title ?? String(localized: "Your")) blush")
        case .eyebrow: String(localized: "\(browOverlay?.title ?? String(localized: "Natural")) brows")
        case .eyeliner: String(localized: "\(String(localized: linerLook.title)) eyeliner")
        case .lips: String(localized: "\(lipStyle.title) lips")
        }
    }
}

extension TryOnTool {
    /// What to have ready before the tutorial, as the brief lists it: the must-haves (cards) and what to keep nearby for
    /// mistakes (rows). Copy from the design; pictures are the `kit-*` image sets (an SF Symbol until one is filled).
    var mustHave: [MakeupKitItem] {
        switch self {
        case .blush: [
            MakeupKitItem(id: "blush", kind: .product, symbol: "paintpalette.fill", title: "Blush", detail: "Powder or cream",
                          info: .init(imageName: "kit-blush",
                                      text: "Colour for your cheeks. It comes as a powder in a compact, or a cream in a stick or small pot.",
                                      tip: "You'll tap it on the top of your cheeks.")),
            MakeupKitItem(id: "brush", kind: .tool, symbol: "paintbrush.pointed.fill", title: "Fluffy brush", detail: "Or your fingertips",
                          info: .init(imageName: "kit-fluffy-brush",
                                      text: "A big, soft, round brush. It spreads blush lightly, so you get a soft glow with no hard edges.",
                                      tip: "No brush? Your fingertips work too."))
        ]
        case .eyebrow: [
            MakeupKitItem(id: "pencil", kind: .product, symbol: "pencil", title: "Brow pencil", detail: "Lighter than your hair",
                          info: .init(imageName: "kit-brow-pencil",
                                      text: "A thin pencil for filling in brows. Pick a shade a little lighter than your hair so it looks natural.",
                                      tip: "Use short, hair-like strokes, not one line.")),
            MakeupKitItem(id: "spoolie", kind: .tool, symbol: "paintbrush.pointed.fill", title: "Spoolie", detail: "Combs brow hairs up",
                          info: .init(imageName: "kit-spoolie",
                                      text: "A small spiral brush, like a clean mascara wand. It combs brow hairs up and softens pencil lines.",
                                      tip: "Brush up before you fill, and again after."))
        ]
        case .eyeliner: [
            MakeupKitItem(id: "liner", kind: .product, symbol: "pencil", title: "Liquid liner", detail: "A felt-tip pen is easiest to control",
                          info: .init(imageName: "kit-liquid-liner",
                                      text: "Eyeliner in a pen. The felt tip draws a thin, dark line right along your upper lashes.",
                                      tip: "Hold it like a pen and draw short strokes."))
        ]
        // No pictures yet, so no popups: the cards show the symbols.
        case .lips: [
            MakeupKitItem(id: "lipstick", kind: .product, symbol: "mouth.fill", title: "Lipstick", detail: "A bullet or a liquid one"),
            MakeupKitItem(id: "lipliner", kind: .tool, symbol: "pencil", title: "Lip liner", detail: "Or the edge of your lipstick")
        ]
        }
    }

    /// What to keep nearby for mistakes: micellar water and what to wipe with.
    var nearby: [MakeupKitItem] {
        let wipe = switch self {
        case .blush: MakeupKitItem(id: "pads", kind: .forMistakes, symbol: "circle", title: "Cotton pads", detail: "to apply the micellar water")
        case .eyebrow: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "to wipe small edges")
        case .eyeliner: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "pointed ones fix small lines")
        case .lips: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "to tidy the edge")
        }
        return [
            MakeupKitItem(id: "micellar", kind: .forMistakes, symbol: "drop", title: "Micellar water", detail: "wipes off mistakes",
                          info: .init(imageName: "kit-micellar-water",
                                      text: "A gentle cleansing water. Put a little on a cotton pad or bud and wipe a mistake away.",
                                      tip: "Wipe softly, let it dry, then try again.")),
            wipe
        ]
    }
}

struct MakeupKitItem: Identifiable {
    enum Kind {
        case product, tool, forMistakes

        var label: LocalizedStringKey {
            switch self {
            case .product: "Product"
            case .tool: "Tool"
            case .forMistakes: "For mistakes"
            }
        }
    }

    /// What the item's popup shows: its picture, what it is, and a tip.
    struct Info {
        let imageName: String
        let text: LocalizedStringKey
        let tip: LocalizedStringKey
    }

    let id: String
    let kind: Kind
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var info: Info? = nil
}

// MARK: Feedback

/// What the feedback step gets: the tool, the style and both photos (either may be missing).
struct MakeupFeedbackRequest: @unchecked Sendable {
    let tool: TryOnTool
    let styleTitle: String
    let desired: UIImage?
    let result: UIImage?
    var blushStyle: BlushPlacementStyle? = nil
    var linerLook: LinerLook? = nil
    var shade: MakeupShade? = nil
    var desiredScan: FaceScan? = nil
    var resultScan: FaceScan? = nil
}

struct MakeupFeedback: Sendable, Equatable {
    /// One message: what is off and how to fix it, from `makeup-feedback.database.json`.
    struct Item: Sendable, Hashable {
        var title: String
        var say: String
        var steps: [String]
        var band: FeedbackBand
        /// The database id of the rule, praise or photo check (for tests and calibration).
        var rule: String = ""
        /// Which side it is about (left, right, both); nil for photo checks and praise.
        var side: FeedbackSide? = nil
        /// The words that filled the message's placeholders ({zone}, {other}, ...; {part} comes from `side`), kept so a
        /// saved look can tell the same message again (`MyLookFeedback`).
        var values: [String: String] = [:]
    }

    /// -Nimah: where to show a fix on the result photo, for one side. Points are 0...1 of the result photo (x across, y
    /// down): the target as tried on, the target spots with no makeup ("add here") and the makeup outside it ("wipe off").
    struct Mark: Sendable, Equatable {
        var side: FeedbackSide
        var target: [CGPoint]
        var add: [CGPoint]
        var remove: [CGPoint]
    }

    /// One card of the feedback screen: a group of rules (placement, shape, ...) with its own score.
    struct Category: Sendable, Hashable, Identifiable {
        var id: String
        var title: String
        var symbol: String
        /// 0...1.
        var percent: Double
        /// Short: the worst message's title, or "Spot on".
        var label: String
        /// Every message of this group, worst first (shown when the card is opened).
        var items: [Item]
        /// What this percentage means (`makeup-score.database.json`), shown above the messages.
        var description: String = ""
    }

    /// One measured part of the result, e.g. placement: 0...1 and a short note ("A little high").
    struct Part: Sendable, Equatable {
        var value: Double
        var note: String
    }

    /// 0...1 when the comparison gives one.
    var score: Double?
    var headline: String
    var comments: [String]
    var items: [Item] = []
    var categories: [Category] = []
    /// One sentence for the score card: what to fix first, or the praise.
    var summary: String = ""
    /// Photo notes that did not stop the check (tilted a little, light changed).
    var notes: [Item] = []
    /// Where the makeup sits compared with the try-on; nil until the comparison measures it.
    var placement: Part? = nil
    /// How close the colour is to the shade tried on; nil until the comparison measures it.
    var shade: Part? = nil
    /// What went well (the database's praise), shown as ticks under the fixes.
    var praise: [Item] = []
    /// One per measured side, for the marked photo crop of the first fix.
    var marks: [Mark] = []

    /// What to fix, worst first: the measured messages without photo checks and praise.
    var fixes: [Item] { items.filter { $0.band != .ok && $0.side != nil } }

    /// The marks for an item's side: one, or both sides for an item about both.
    func marks(for item: Item) -> [Mark] {
        guard let side = item.side else { return [] }
        return marks.filter { !$0.target.isEmpty && (side == .both || $0.side == side) }
    }
}

/// Compares the desired-look photo with the result. The real comparison (placement from coordinates) is built
/// separately; `PlaceholderFeedbackProvider` stands in until then.
protocol MakeupFeedbackProviding: Sendable {
    /// `progress` gets 0...1 while it works, for the loading screen.
    func feedback(for request: MakeupFeedbackRequest, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> MakeupFeedback
}

/// Waits about two seconds and returns fixed text. Not a real result: it never looks at the photos.
struct PlaceholderFeedbackProvider: MakeupFeedbackProviding {
    func feedback(for request: MakeupFeedbackRequest, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> MakeupFeedback {
        for step in 1...20 {
            try? await Task.sleep(for: .milliseconds(100))
            await progress(Double(step) / 20)
        }
        return MakeupFeedback(score: nil,
                              headline: String(localized: "Feedback is coming soon"),
                              comments: [String(localized: "Placement feedback for your \(request.styleTitle) will show here.")])
    }
}

/// -Nimah: the measured comparison for every tool (`BlushFeedback`, `BrowFeedback`, `EyelinerFeedback`); the placeholder
/// only when the database cannot be read.
struct MeasuredFeedbackProvider: MakeupFeedbackProviding {
    var fallback: any MakeupFeedbackProviding = PlaceholderFeedbackProvider()

    func feedback(for request: MakeupFeedbackRequest, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> MakeupFeedback {
        // Lips are not measured yet: the placeholder says so.
        guard request.tool != .lips, let database = FeedbackDatabase.load() else { return await fallback.feedback(for: request, progress: progress) }
        await progress(0.1)
        let language = FeedbackLanguage.current
        let tool = request.tool
        let blush = BlushFeedbackInput(before: request.desiredScan, hadBeforePhoto: request.desired != nil, after: request.resultScan,
                                       style: request.blushStyle,
                                       shade: request.shade.map { SIMD3($0.red, $0.green, $0.blue) })
        let line = LineFeedbackInput(before: request.desiredScan, hadBeforePhoto: request.desired != nil, after: request.resultScan,
                                     look: request.linerLook?.rawValue,
                                     shade: request.shade.map { SIMD3($0.red, $0.green, $0.blue) })
        let result = await Task.detached(priority: .userInitiated) { () -> MakeupFeedback in
            switch tool {
            case .blush: BlushFeedback.evaluate(blush, database: database, language: language)
            case .eyebrow: BrowFeedback.evaluate(line, database: database, language: language)
            case .eyeliner: EyelinerFeedback.evaluate(line, database: database, language: language)
            // Not reached: lips left above.
            case .lips: MakeupFeedback(score: nil, headline: "", comments: [])
            }
        }.value
        // A short, steady finish so the loading screen does not flash.
        for step in 2...10 {
            try? await Task.sleep(for: .milliseconds(60))
            await progress(Double(step) / 10)
        }
        return result
    }
}

// MARK: Shared controls

/// The flow's full-width pink "Continue" / "Next" button (the old "Go to Tutorial" style).
struct FlowPrimaryButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let symbol { Image(systemName: symbol) }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(AppColors.snow)
            .frame(maxWidth: .infinity, minHeight: 60)
            // Native glass over a solid pink, so the wine background cannot show through and dull it.
            .background(Capsule().fill(AppColors.prepPink))
            .glassCapsule(tint: AppColors.prepPink.opacity(0.35))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

/// A grey rounded box with a label, standing in for artwork the design team has not delivered yet.
struct FlowPlaceholderBox: View {
    let label: LocalizedStringKey
    var symbol = "photo"

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppColors.snow.opacity(0.12))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: symbol).font(.title2)
                    Text(label).font(.footnote)
                }
                .foregroundStyle(AppColors.snow.opacity(0.7))
            }
            .accessibilityElement(children: .combine)
    }
}


/// The chosen style's name with a dot of its shade: glass over the capture camera, pale pink on the brief.
struct StylePill: View {
    let handoff: TutorialHandoff
    var onGlass = false

    private var dot: Color {
        if let shade = handoff.shades[handoff.tool] { return Color(red: shade.red, green: shade.green, blue: shade.blue) }
        return switch handoff.tool {
        case .blush: Color(red: 0xF4 / 255, green: 0x9A / 255, blue: 0xB8 / 255)
        case .eyebrow: Color(red: 0x6B / 255, green: 0x4A / 255, blue: 0x35 / 255)
        case .eyeliner: AppColors.buttonInk
        case .lips: Color(red: 0xC7 / 255, green: 0x1A / 255, blue: 0x2B / 255)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: onGlass ? 9 : 16, height: onGlass ? 9 : 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: onGlass ? 1 : 0))
            Text(verbatim: handoff.styleTitle).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(onGlass ? AppColors.snow : AppColors.onboardingInk)
        .padding(.leading, onGlass ? 12 : 10)
        .padding(.trailing, onGlass ? 12 : 14)
        .frame(minHeight: onGlass ? 30 : nil)
        // Light pages: the design's 154 x 40 capsule.
        .frame(width: onGlass ? nil : 154, height: onGlass ? nil : 40)
        .background {
            // Light pages (brief): the design's soft grey capsule.
            if !onGlass { Capsule().fill(Color.black.opacity(0.06)) }
        }
        .modifier(PillGlass(on: onGlass))
        .accessibilityElement(children: .combine)
    }
}

private struct PillGlass: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on { content.glassEffect(.regular, in: .capsule) } else { content }
    }
}

/// A perspective map of the picture plane (3 x 3, last entry 1), fitted to many matching face points: unlike the two-eye
/// fit it also takes out small differences in head turn and nod between the two photos, so the result photo is redrawn as if
/// taken from the desired photo's angle (for the face; good for the few degrees the capture screen still allows).
struct FaceHomography: Equatable {
    /// Row-major h11 ... h32; h33 = 1.
    var h: [Double]

    func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let w = h[6] * x + h[7] * y + 1
        return CGPoint(x: (h[0] * x + h[1] * y + h[2]) / w, y: (h[3] * x + h[4] * y + h[5]) / w)
    }

    /// Least squares over the pairs (direct linear transform, points centred and scaled first for a stable solve).
    /// Nil with fewer than 8 pairs or a degenerate fit.
    static func fit(from source: [CGPoint], to target: [CGPoint]) -> FaceHomography? {
        guard source.count == target.count, source.count >= 8 else { return nil }
        func normaliser(_ points: [CGPoint]) -> (cx: Double, cy: Double, s: Double) {
            let cx = points.map { Double($0.x) }.reduce(0, +) / Double(points.count)
            let cy = points.map { Double($0.y) }.reduce(0, +) / Double(points.count)
            let mean = points.map { hypot(Double($0.x) - cx, Double($0.y) - cy) }.reduce(0, +) / Double(points.count)
            return (cx, cy, mean > 0 ? sqrt(2) / mean : 1)
        }
        let ns = normaliser(source), nt = normaliser(target)
        // Normal equations AᵀA x = Aᵀb for the 8 unknowns.
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var atb = [Double](repeating: 0, count: 8)
        for (p, q) in zip(source, target) {
            let x = (Double(p.x) - ns.cx) * ns.s, y = (Double(p.y) - ns.cy) * ns.s
            let u = (Double(q.x) - nt.cx) * nt.s, v = (Double(q.y) - nt.cy) * nt.s
            for (row, b) in [([x, y, 1, 0, 0, 0, -u * x, -u * y], u), ([0, 0, 0, x, y, 1, -v * x, -v * y], v)] {
                for i in 0..<8 {
                    atb[i] += row[i] * b
                    for j in 0..<8 { ata[i][j] += row[i] * row[j] }
                }
            }
        }
        guard let n = solve(ata, atb) else { return nil }
        // Undo the normalisation: H = Tt⁻¹ · Hn · Ts.
        let hn = [[n[0], n[1], n[2]], [n[3], n[4], n[5]], [n[6], n[7], 1]]
        let ts = [[ns.s, 0, -ns.s * ns.cx], [0, ns.s, -ns.s * ns.cy], [0, 0, 1]]
        let ttInverse = [[1 / nt.s, 0, nt.cx], [0, 1 / nt.s, nt.cy], [0, 0, 1]]
        let m = multiply(ttInverse, multiply(hn, ts))
        guard abs(m[2][2]) > 1e-12 else { return nil }
        let k = 1 / m[2][2]
        return FaceHomography(h: [m[0][0], m[0][1], m[0][2], m[1][0], m[1][1], m[1][2], m[2][0], m[2][1]].map { $0 * k })
    }

    /// The fit for two captures: their mesh points that face the camera in both photos.
    static func fit(result: CapturePoseReading, desired: CapturePoseReading) -> FaceHomography? {
        guard result.meshPoints.count == desired.meshPoints.count, result.meshFront.count == result.meshPoints.count,
              desired.meshFront.count == desired.meshPoints.count else { return nil }
        let pairs = result.meshPoints.indices.filter { result.meshFront[$0] && desired.meshFront[$0] }
        return fit(from: pairs.map { result.meshPoints[$0] }, to: pairs.map { desired.meshPoints[$0] })
    }

    /// Whether the map only nudges the picture (corners move under 20% of its size): otherwise the poses were too
    /// different, or a point was misread, and the photo is better left alone.
    func isGentle(for size: CGSize) -> Bool {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        return corners.allSatisfy { c in
            let m = apply(c)
            return m.x.isFinite && m.y.isFinite && hypot(m.x - c.x, m.y - c.y) < 0.2 * max(size.width, size.height)
        }
    }

    /// `image` redrawn through the map; uncovered edges are black.
    func warp(_ image: UIImage) -> UIImage? {
        guard isGentle(for: image.size), let input = CIImage(image: image),
              let filter = CIFilter(name: "CIPerspectiveTransform") else { return nil }
        let scale = image.scale, height = image.size.height
        // Core Image counts pixels from the bottom left.
        func vector(_ p: CGPoint) -> CIVector {
            let m = apply(p)
            return CIVector(x: m.x * scale, y: (height - m.y) * scale)
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(CGPoint(x: 0, y: 0)), forKey: "inputTopLeft")
        filter.setValue(vector(CGPoint(x: image.size.width, y: 0)), forKey: "inputTopRight")
        filter.setValue(vector(CGPoint(x: 0, y: height)), forKey: "inputBottomLeft")
        filter.setValue(vector(CGPoint(x: image.size.width, y: height)), forKey: "inputBottomRight")
        let frame = CGRect(x: 0, y: 0, width: image.size.width * scale, height: height * scale)
        guard let output = filter.outputImage?.composited(over: CIImage(color: .black).cropped(to: frame)).cropped(to: frame),
              let cg = CIContext().createCGImage(output, from: frame) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } }
    }

    /// Gaussian elimination with partial pivoting.
    private static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        var m = a, v = b
        let n = v.count
        for c in 0..<n {
            guard let pivot = (c..<n).max(by: { abs(m[$0][c]) < abs(m[$1][c]) }), abs(m[pivot][c]) > 1e-12 else { return nil }
            m.swapAt(c, pivot); v.swapAt(c, pivot)
            for r in (c + 1)..<n {
                let f = m[r][c] / m[c][c]
                guard f != 0 else { continue }
                for k in c..<n { m[r][k] -= f * m[c][k] }
                v[r] -= f * v[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            x[r] = (v[r] - ((r + 1)..<n).reduce(0) { $0 + m[r][$1] * x[$1] }) / m[r][r]
        }
        return x
    }
}
