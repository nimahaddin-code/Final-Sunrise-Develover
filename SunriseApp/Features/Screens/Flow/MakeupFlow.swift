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
    /// Where the face feature must sit in the capture frame, as fractions of the camera card. Placeholder positions until
    /// the design is final; nothing checks yet that the feature really is inside.
    var captureRegion: CGRect {
        switch self {
        case .eyebrow: CGRect(x: 0.08, y: 0.22, width: 0.84, height: 0.18)
        case .eyeliner: CGRect(x: 0.08, y: 0.28, width: 0.84, height: 0.15)
        case .blush: CGRect(x: 0.06, y: 0.36, width: 0.88, height: 0.26)
        }
    }

    var captureHint: LocalizedStringKey {
        switch self {
        case .eyebrow: "Fit both brows inside the frame"
        case .eyeliner: "Fit both eyes inside the frame"
        case .blush: "Fit both cheeks inside the frame"
        }
    }

    /// The tools and products to have ready before the tutorial. Placeholder list until the design team's copy arrives.
    var kit: [MakeupKitItem] {
        switch self {
        case .blush:
            // -Nimah: the blush kit is kept in one place, `BlushInfo`, with its pictures.
            ToolInfo.blush(TutorialHandoff(tool: .blush, shades: [:], intensities: [:])).kitItems
        case .eyebrow: [
            MakeupKitItem(id: "spoolie", symbol: "scribble.variable", title: "Spoolie", detail: "To brush the hairs up and blend."),
            MakeupKitItem(id: "pencil", symbol: "pencil", title: "Brow pencil", detail: "Close to the shade you tried."),
            MakeupKitItem(id: "bud", symbol: "drop", title: "Cotton bud", detail: "To clean up the edges.")
        ]
        case .eyeliner: [
            MakeupKitItem(id: "liner", symbol: "pencil.tip", title: "Eyeliner", detail: "Pen, gel or pencil, in the shade you tried."),
            MakeupKitItem(id: "bud", symbol: "drop", title: "Cotton bud", detail: "With a little micellar water for mistakes."),
            MakeupKitItem(id: "light", symbol: "sun.max", title: "Bright, soft light", detail: "Face a window, or switch on the screen light.")
        ]
        }
    }
}

struct MakeupKitItem: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    /// An asset shown instead of the symbol, when the tool has a picture of the item.
    var imageName: String? = nil
}

extension ToolInfo {
    /// Tools then products, as cards for the get-ready page. Texts are already localised, so they are shown as they are.
    var kitItems: [MakeupKitItem] {
        (tools + products).map { item in
            MakeupKitItem(id: item.id, symbol: item.symbol, title: LocalizedStringKey(stringLiteral: item.name),
                          detail: LocalizedStringKey(stringLiteral: item.detail), imageName: item.imageName)
        }
    }
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

/// The frame the face feature must sit in, like an ID-card photo frame: the card dimmed except for a cut-out shaped like
/// the feature (one rectangle round both eyes, two brows or two cheeks), its outline, corner brackets round the area, and the hint below.
struct FeatureFrameOverlay: View {
    let tool: TryOnTool
    var highlight: Color = AppColors.snow
    var showsHint = true

    var body: some View {
        GeometryReader { proxy in
            let region = tool.captureRegion
            let rect = CGRect(x: region.minX * proxy.size.width, y: region.minY * proxy.size.height,
                              width: region.width * proxy.size.width, height: region.height * proxy.size.height)
            let cutout = FeatureFrameShape.path(for: tool, in: rect)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addPath(cutout)
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                cutout.stroke(highlight, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                FeatureFrameShape.corners(around: rect.insetBy(dx: -10, dy: -14))
                    .stroke(highlight, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if showsHint {
                    Text(tool.captureHint)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.snow)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(AppColors.captionFill.opacity(0.85), in: Capsule())
                        .frame(width: proxy.size.width)
                        .offset(y: rect.maxY + 26)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Feature outlines for the capture frame: a rectangle round both eyes, else one shape per side of the face, drawn inside the tool's capture region. The camera
/// is mirrored, so the left shape on screen is the user's right side; each pair is symmetric about the region's middle.
enum FeatureFrameShape {
    static func path(for tool: TryOnTool, in rect: CGRect) -> Path {
        // Both eyes in one rounded rectangle.
        if tool == .eyeliner { return Path(roundedRect: rect, cornerRadius: 24, style: .continuous) }
        var path = Path()
        for leading in [true, false] {
            switch tool {
            case .eyeliner: break
            case .eyebrow: path.addPath(brow(in: rect, leading: leading))
            case .blush: path.addPath(cheek(in: rect, leading: leading))
            }
        }
        return path
    }

    /// A brow band: thick, rounded head by the nose, rising to the arch about two thirds out, tapering to the tail.
    static func brow(in rect: CGRect, leading: Bool) -> Path {
        let width = rect.width * 0.42
        let height = min(width / 3.2, rect.height)
        let box = side(of: rect, width: width, height: height, leading: leading)
        // x runs from the tail (0) to the head (1).
        let point = { (x: CGFloat, y: CGFloat) in
            CGPoint(x: leading ? box.minX + x * box.width : box.maxX - x * box.width, y: box.minY + y * box.height)
        }
        var path = Path()
        path.move(to: point(0, 0.62))
        path.addCurve(to: point(0.34, 0.02), control1: point(0.08, 0.36), control2: point(0.2, 0.04))
        path.addCurve(to: point(1, 0.42), control1: point(0.56, 0), control2: point(0.86, 0.18))
        path.addCurve(to: point(0.98, 0.96), control1: point(1.04, 0.6), control2: point(1.03, 0.86))
        path.addCurve(to: point(0.34, 0.5), control1: point(0.8, 0.82), control2: point(0.56, 0.5))
        path.addCurve(to: point(0, 0.62), control1: point(0.18, 0.5), control2: point(0.06, 0.56))
        path.closeSubpath()
        return path
    }

    /// A cheek oval tilted up toward the temple.
    static func cheek(in rect: CGRect, leading: Bool) -> Path {
        let width = rect.width * 0.36
        let height = min(width * 0.62, rect.height)
        let box = side(of: rect, width: width, height: height, leading: leading)
        let tilt = CGAffineTransform(translationX: box.midX, y: box.midY)
            .rotated(by: (leading ? 1 : -1) * .pi / 14)
            .translatedBy(x: -box.midX, y: -box.midY)
        return Path(ellipseIn: box).applying(tilt)
    }

    /// ID-card style corner brackets round the capture area.
    static func corners(around rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.22
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        return path
    }

    /// One side's box: the outer edge on the region's edge, vertically centred.
    private static func side(of rect: CGRect, width: CGFloat, height: CGFloat, leading: Bool) -> CGRect {
        CGRect(x: leading ? rect.minX : rect.maxX - width, y: rect.midY - height / 2, width: width, height: height)
    }
}
