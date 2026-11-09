// The one-tool makeup flow: pick a tool, try it on, photograph the desired look, prepare, follow the tutorial side by
// side, photograph the result, get feedback. Photos stay in memory for this run only; nothing is saved or uploaded.
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

    /// The bare camera at the desired-look shutter (no virtual makeup): the feedback's "Before".
    var bare: UIImage?
    /// Developer read-out of each shutter (shown on the feedback screen with developer tools on).
    var diagnostics: [CaptureStage: CaptureDiagnostics] = [:]

    func reset() { desired = nil; result = nil; desiredScan = nil; resultScan = nil; bare = nil; diagnostics = [:] }
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

    var line: String {
        "engine \(engine ? "yes" : "no") · layer \(layerShown ? "shown" : "hidden") · drawing \(engineOn ? "on" : "off") · "
            + "screen \(read.rawValue)\(readTries > 0 ? " (\(readTries)x, \(readMilliseconds) ms)" : "") · frames \(framesBefore) · "
            + "target \(outline ? "yes" : "no") · face \(face ? "yes" : "no")"
    }
}

extension TutorialHandoff {
    /// The chosen style's name, e.g. "Sunkissed blush", for the flow's captions.
    var styleTitle: String {
        switch tool {
        case .blush: String(localized: "\(blushStyle?.title ?? String(localized: "Your")) blush")
        case .eyebrow: String(localized: "\(browOverlay?.title ?? String(localized: "Natural")) brows")
        case .eyeliner: String(localized: "\(String(localized: linerLook.title)) eyeliner")
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
        }
    }

    /// What to keep nearby for mistakes: micellar water and what to wipe with.
    var nearby: [MakeupKitItem] {
        let wipe = switch self {
        case .blush: MakeupKitItem(id: "pads", kind: .forMistakes, symbol: "circle", title: "Cotton pads", detail: "to apply the micellar water")
        case .eyebrow: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "to wipe small edges")
        case .eyeliner: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "pointed ones fix small lines")
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
        guard let database = FeedbackDatabase.load() else { return await fallback.feedback(for: request, progress: progress) }
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
