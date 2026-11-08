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

    func reset() { desired = nil; result = nil }
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

    var nearby: [MakeupKitItem] {
        let face: LocalizedStringKey = switch self {
        case .blush: "no old makeup on"
        case .eyebrow: "no oil on the brows"
        case .eyeliner: "no oil all around the eyes"
        }
        let wipe = switch self {
        case .blush: MakeupKitItem(id: "pads", kind: .forMistakes, symbol: "circle", title: "Cotton pads", detail: "to apply the micellar water")
        case .eyebrow: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "to wipe small edges")
        case .eyeliner: MakeupKitItem(id: "buds", kind: .forMistakes, symbol: "circle", title: "Cotton buds", detail: "pointed ones fix small lines")
        }
        return [
            MakeupKitItem(id: "face", kind: .forMistakes, symbol: "face.smiling", title: "Clean, dry face", detail: face),
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
}

struct MakeupFeedback: Sendable, Equatable {
    /// 0...1 when the comparison gives one.
    var score: Double?
    var headline: String
    var comments: [String]
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
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: onGlass ? 1 : 0))
            Text(verbatim: handoff.styleTitle).lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(onGlass ? AppColors.snow : AppColors.onboardingInk)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background {
            if !onGlass { Capsule().fill(AppColors.dandanPink.opacity(0.1)) }
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
