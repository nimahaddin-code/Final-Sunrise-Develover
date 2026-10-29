// Photo step after the tutorial: the live makeup camera in a coloured frame, then the captured picture as a polaroid.
// The picture stays in memory; it is only written anywhere when the person shares it.
import SwiftUI
import UIKit

/// The frame colour around the camera. The palette button at the bottom left steps through them.
enum PhotoTheme: CaseIterable {
    case pink, blue, white

    var next: PhotoTheme {
        switch self { case .pink: .blue; case .blue: .white; case .white: .pink }
    }
    var background: Color {
        switch self {
        case .pink: Color(red: 1.0, green: 0.35, blue: 0.66)
        case .blue: Color(red: 0.18, green: 0.87, blue: 0.98)
        case .white: Color(red: 0.98, green: 0.97, blue: 0.97)
        }
    }
    /// Controls drawn on the frame: white on the coloured frames, a soft pink on the white one.
    var control: Color { self == .white ? Color(red: 0.93, green: 0.55, blue: 0.62) : .white }
    var logo: String { self == .white ? "logo-burgundy" : "logo-white" }
    var name: LocalizedStringKey {
        switch self { case .pink: "Pink frame"; case .blue: "Blue frame"; case .white: "White frame" }
    }
}

/// The header and the control row of the photo screen; the camera card between them is the tutorial's own.
struct PhotoHeader: View {
    let theme: PhotoTheme
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Image(theme.logo)
                .resizable().scaledToFit()
                .frame(maxWidth: 140, maxHeight: 40)
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(theme.control.opacity(0.3)))
                        .foregroundStyle(theme.control)
                }
                .accessibilityLabel("Back to tutorial")
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, AppSpacing.small)
    }
}

struct PhotoControls: View {
    let theme: PhotoTheme
    @Binding var flashOn: Bool
    let onTheme: () -> Void
    let onShutter: () -> Void

    var body: some View {
        HStack {
            Button(action: onTheme) {
                Image(systemName: "paintpalette")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .foregroundStyle(theme.control)
                    .overlay(Circle().strokeBorder(theme.control, lineWidth: 2))
            }
            .accessibilityLabel("Change frame colour")
            .accessibilityValue(theme.name)
            .frame(maxWidth: .infinity)
            Button(action: onShutter) {
                Circle()
                    .fill(.white)
                    .frame(width: 74, height: 74)
                    .overlay(Circle().strokeBorder(theme.control.opacity(0.7), lineWidth: 4))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
            .accessibilityLabel("Take photo")
            .frame(maxWidth: .infinity)
            Button { flashOn.toggle() } label: {
                Image(systemName: flashOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .foregroundStyle(theme.control.opacity(flashOn ? 1 : 0.6))
            }
            .accessibilityLabel("Screen flash")
            .accessibilityValue(flashOn ? "On" : "Off")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, AppSpacing.small)
    }
}

/// The picture on a white polaroid card, in the design's proportions (card 393:557, picture 354:414, logo bottom right).
private struct PolaroidCard: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 393
            ZStack(alignment: .topLeading) {
                Color.white
                Color.clear
                    .frame(width: 354 * unit, height: 414 * unit)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                    .offset(x: 19 * unit, y: 32 * unit)
                Image("logo-white")
                    .resizable().scaledToFit()
                    .frame(width: 194 * unit)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, x: 2, y: 2)
                    .offset(x: 170 * unit, y: 462 * unit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .aspectRatio(393.0 / 557.0, contentMode: .fit)
    }
}

/// The captured photo as a polaroid, with retake, share and done.
struct PolaroidResultView: View {
    let image: UIImage
    let onRetake: () -> Void
    let onDone: () -> Void
    @State private var shareable: Image?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                PolaroidCard(image: image)
                    .frame(width: proxy.size.width * 0.786)
                    .shadow(color: .black.opacity(0.5), radius: 14, x: 8, y: 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your try-on photo")
                    .accessibilityAddTraits(.isImage)
                    .padding(.top, proxy.size.height * 0.13)
                HStack(spacing: 25) {
                    button("arrow.counterclockwise", "Retake photo", action: onRetake)
                    if let shareable {
                        ShareLink(item: shareable, preview: SharePreview("Try-on photo", image: shareable)) { icon("square.and.arrow.up") }
                            .accessibilityLabel("Share photo")
                    } else {
                        icon("square.and.arrow.up").opacity(0.5)
                    }
                    button("checkmark", "Done", action: onDone)
                }
                .padding(.top, proxy.size.height * 0.12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.wine.ignoresSafeArea())
        .task {
            // The polaroid, not the bare picture, is what gets shared.
            let renderer = ImageRenderer(content: PolaroidCard(image: image).frame(width: 393).padding(40).background(AppColors.wine))
            renderer.scale = 3
            if let rendered = renderer.uiImage { shareable = Image(uiImage: rendered) }
        }
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 32, weight: .medium))
            .frame(width: 78, height: 78)
            .background(AppColors.flamingo, in: Circle())
            .foregroundStyle(.white)
    }

    private func button(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol) }.accessibilityLabel(label)
    }
}


// MARK: Previews (layout only: the real camera needs a device)

#if DEBUG
private func sampleFace() -> UIImage {
    let size = CGSize(width: 600, height: 800)
    return UIGraphicsImageRenderer(size: size).image { context in
        let colors = [UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 1).cgColor, UIColor(red: 0.3, green: 0.2, blue: 0.18, alpha: 1).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
        context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }
}

/// Stand-in for the photo screen in `TutorialScreen`: same header, frame size rule and controls, with a grey camera.
private struct PhotoScreenPreview: View {
    @State var theme: PhotoTheme
    @State private var flashOn = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: AppSpacing.medium) {
                PhotoHeader(theme: theme) {}
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray.opacity(0.5))
                    .overlay(Image(uiImage: sampleFace()).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                    .frame(maxHeight: min(proxy.size.width * 300 / 208, proxy.size.height * 0.65))
                PhotoControls(theme: theme, flashOn: $flashOn, onTheme: { theme = theme.next }, onShutter: {})
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.medium)
        }
        .background(theme.background.ignoresSafeArea())
    }
}

#Preview("Photo - pink") { PhotoScreenPreview(theme: .pink) }
#Preview("Photo - blue") { PhotoScreenPreview(theme: .blue) }
#Preview("Photo - white") { PhotoScreenPreview(theme: .white) }
#Preview("Polaroid") { PolaroidResultView(image: sampleFace(), onRetake: {}, onDone: {}) }
#endif
