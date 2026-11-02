import SwiftUI

/// Horizontal list of every eyebrow style, shown under the tool strip while the eyebrow tool is selected.
struct BrowStylePicker: View {
    let styles: [EyebrowStyle]
    let selected: EyebrowStyle
    let onSelect: (EyebrowStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                ForEach(styles) { style in
                    let isSelected = style == selected
                    Button { onSelect(style) } label: {
                        VStack(spacing: 4) {
                            BrowStyleThumbnail(style: style)
                                .frame(width: 72, height: 30)
                            Text(style.title)
                                .font(AppTypography.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(AppColors.flamingo.opacity(isSelected ? 0.32 : 0.16),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppColors.snow, lineWidth: isSelected ? 2 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(style.title))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// The style's brow outline: the same `BrowDesign` the live renderer draws, laid on a generic natural brow.
private struct BrowStyleThumbnail: View {
    let style: EyebrowStyle

    /// A typical natural brow centerline (fractions of brow width): head low, gentle rise to the arch, tail down.
    private static func baseline(_ t: Float) -> Float {
        t < 0.62 ? 0.07 * sin(t / 0.62 * .pi / 2) : 0.07 - 0.09 * pow((t - 0.62) / 0.38, 1.6)
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let points = BrowDesign.make(style: style)?.points ?? []
            // The live brow feathers its edges and fades in its head; at thumbnail size a softened half thickness and
            // a rounded head read the same way.
            let halves = points.indices.map { i -> Float in
                let window = points[max(0, i - 2)...min(points.count - 1, i + 2)]
                let t = points[i].w, head = min(1, t / 0.12)
                return window.map(\.z).reduce(0, +) / Float(window.count) * (0.35 + 0.65 * head.squareRoot())
            }
            Path { path in
                guard !points.isEmpty else { return }
                for edge in 0...1 {
                    for i in 0..<points.count {
                        let index = edge == 0 ? i : points.count - 1 - i
                        let p = points[index], half = halves[index]
                        let y = Self.baseline(p.x) + p.y + (edge == 0 ? half : -half)
                        let point = CGPoint(x: 4 + CGFloat(p.x) * (w - 8), y: h * 0.62 - CGFloat(y) * (w - 8))
                        if edge == 0 && i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                path.closeSubpath()
            }
            .fill(AppColors.snow)
        }
        .accessibilityHidden(true)
    }
}

/// Developer-only brow render views, to tell a texture/alpha problem from a landmark or placement problem.
enum BrowDebugView: Int, CaseIterable, Identifiable {
    case final, original, landmarks, contours, alphaMask, textureOnly, originalMask
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .final: "Final composite"
        case .original: "Original frame"
        case .landmarks: "Landmarks"
        case .contours: "Fit contours"
        case .alphaMask: "Alpha mask"
        case .textureOnly: "Texture only"
        case .originalMask: "Original brow mask"
        }
    }
}

/// Picks the `BrowDebugView` the brow engine renders; shown only while developer tools are on.
struct BrowDebugMenu: View {
    @AppStorage(BeautyBlushEngine.browDebugKey) private var view = BrowDebugView.final.rawValue
    /// Nose-side extension of the baked overlay. Changing it invalidates the
    /// sprite cache and re-bakes on the next camera frame.
    @AppStorage(BrowSpriteBaker.headUKey) private var headExtension = Double(BrowSpriteBaker.defaultHeadU)

    var body: some View {
        Menu {
            Picker("Brow view", selection: $view) {
                ForEach(BrowDebugView.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Section("Center gap") {
                Slider(value: $headExtension, in: -0.25...0, step: 0.01)
                Text(String(format: "%.0f%% nose-side extension", -headExtension * 100))
            }
        } label: {
            Label(BrowDebugView(rawValue: view)?.title ?? "Brow view", systemImage: "ladybug")
                .font(AppTypography.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(AppColors.cocoa.opacity(0.85), in: Capsule())
                .foregroundStyle(AppColors.snow)
        }
    }
}

/// Blush blend and diagnostic for side-by-side checks on device; shown only while developer tools are on.
/// English-only developer view: every string is verbatim, so none reaches `Localizable.xcstrings`.
struct BlushDebugMenu: View {
    @AppStorage(BeautyBlushEngine.blushBlendKey) private var blend = BlushBlend.pigment.rawValue
    @AppStorage(BeautyBlushEngine.blushDiagnosticKey) private var diagnostic = BlushDiagnostic.final.rawValue

    var body: some View {
        Menu {
            Picker(selection: $blend) {
                ForEach(BlushBlend.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
            } label: { Text(verbatim: "Blend") }
            Picker(selection: $diagnostic) {
                ForEach(BlushDiagnostic.allCases) { Text(verbatim: $0.title).tag($0.rawValue) }
            } label: { Text(verbatim: "Diagnostic") }
            Section {
                Text(verbatim: "ARKit face mesh + Metal (drawing)")
                Text(verbatim: "MediaPipe: cheek fit for the reference looks")
                Text(verbatim: "Banuba, BytePlus: SDK and licence not installed")
            } header: { Text(verbatim: "Tracker") }
        } label: {
            Label { Text(verbatim: "Blush lab") } icon: { Image(systemName: "ladybug") }
                .font(AppTypography.caption)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(AppColors.cocoa.opacity(0.85), in: Capsule())
                .foregroundStyle(AppColors.snow)
        }
    }
}
