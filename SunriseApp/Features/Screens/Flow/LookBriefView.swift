import SwiftUI
import UIKit

/// "Your expected result": between the desired-look photo and the tutorial. The photo cropped to the feature, the must-have
/// product and tool as cards, what to keep nearby for mistakes as rows, and "Start tutorial". An item that has a popup reads
/// as a link (underlined in pink) and opens `KitItemSheet` (its name, picture and what it is).
struct LookBriefView: View {
    let handoff: TutorialHandoff
    let photo: UIImage?
    let onBack: () -> Void
    let onStart: () -> Void
    @State private var shown: MakeupKitItem?

    // The design uses two text colours only: ink #0A0A0A and grey #757575.
    private static let ink = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)
    private static let muted = Color(red: 0x75 / 255, green: 0x75 / 255, blue: 0x75 / 255)
    private static let faint = muted

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("Your expected result")
                        .font(.system(size: 28, weight: .black)).fontWidth(.expanded)
                        .tracking(-0.6)
                        .foregroundStyle(Self.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 20)
                    picture
                        .aspectRatio(362 / 196, contentMode: .fit)
                        .padding(.top, 12)
                    Text("What to prepare")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Self.ink)
                        .padding(.top, 28)
                    Text("Tap an item to see what it looks like.")
                        .font(.system(size: 13))
                        .foregroundStyle(Self.muted)
                        .padding(.top, 4)
                    sectionLabel("Must have", color: Self.ink).padding(.top, 20)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(handoff.tool.mustHave) { card($0) }
                    }
                    .padding(.top, 8)
                    sectionLabel("Keep nearby · for mistakes", color: Self.muted).padding(.top, 20)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(handoff.tool.nearby) { row($0) }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, AppSpacing.large)
                .padding(.top, AppSpacing.small)
                .padding(.bottom, AppSpacing.large)
            }
            .scrollIndicators(.hidden)
            Button(action: onStart) {
                Label("Start tutorial", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    // Native Liquid Glass tinted the homepage button colour, at the earlier 52 pt height, with a drop shadow.
                    .glassEffect(.regular.tint(AppColors.buttonInk).interactive(), in: .capsule)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.large)
            .padding(.bottom, AppSpacing.medium)
        }
        .background { OnboardingGlow() }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .sheet(item: $shown) { KitItemSheet(item: $0) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Self.ink)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            StylePill(handoff: handoff)
        }
    }

    @ViewBuilder private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if let photo {
            Color.clear
                .overlay { Image(uiImage: Self.crop(photo, for: handoff.tool)).resizable().scaledToFill() }
                .clipShape(shape)
                .accessibilityLabel("Your desired look")
        } else {
            shape.fill(Color(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xE9 / 255))
                .overlay {
                    Label("No photo taken", systemImage: "camera")
                        .font(.footnote).foregroundStyle(Self.muted)
                }
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey, color: Color, size: CGFloat = 12) -> some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: size, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }

    /// A must-have: icon and kind on top, the name (a link when it opens a popup), then a short detail.
    private func card(_ item: MakeupKitItem) -> some View {
        Button { if item.info != nil { shown = item } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.dandanPink)
                        .frame(width: 36, height: 36)
                        .background(AppColors.dandanPink.opacity(0.1), in: Circle())
                    sectionLabel(item.kind.label, color: Self.muted, size: 11)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    name(item, size: 17, weight: .semibold)
                    Text(item.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Self.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.info != nil ? Text("Shows what it looks like") : Text(""))
    }

    /// Something to keep nearby: icon, name, and a faint note after it.
    private func row(_ item: MakeupKitItem) -> some View {
        Button { if item.info != nil { shown = item } } label: {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Self.muted)
                    .frame(width: 20)
                name(item, size: 15, weight: .regular)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Self.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.info != nil ? .isLink : [])
    }

    /// The item's name in ink; underlined in pink, like a link, when it opens a popup.
    private func name(_ item: MakeupKitItem, size: CGFloat, weight: Font.Weight) -> some View {
        Text(item.title)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(Self.ink)
            .underline(item.info != nil, color: AppColors.dandanPink)
    }

    /// The part of the full-page photo the brief shows: both brows and eyes, both eyes, or the face for blush, at the
    /// picture's 1.85 : 1. Placeholder positions (centre height, width as fractions of the photo), not checked on a device.
    static func crop(_ image: UIImage, for tool: TryOnTool) -> UIImage {
        let (centerY, widthFraction): (CGFloat, CGFloat) = switch tool {
        case .eyebrow: (0.37, 0.86)
        case .eyeliner: (0.39, 0.78)
        case .blush: (0.46, 1)
        }
        let size = image.size
        let width = size.width * widthFraction
        let height = min(width / 1.85, size.height)
        let rect = CGRect(x: (size.width - width) / 2, y: min(max(size.height * centerY - height / 2, 0), size.height - height),
                          width: width, height: height)
        return UIGraphicsImageRenderer(size: rect.size, format: .init(for: image.traitCollection)).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
    }
}

/// An item's popup: a native sheet (system material, navigation bar with the name and a close button), its picture on a
/// white card, what it is, and "Got it".
private struct KitItemSheet: View {
    let item: MakeupKitItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // The product photos are 1086 x 588: the card takes their shape at full width and the photo fills it.
                picture
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1086 / 588, contentMode: .fit)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                if let info = item.info {
                    Text(info.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .navigationTitle(Text(item.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Same dark button as "Start tutorial".
                Button { dismiss() } label: {
                    Text("Got it")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .glassEffect(.regular.tint(AppColors.buttonInk).interactive(), in: .capsule)
                        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        // Close in the design's ink, not the app's pink accent.
        .tint(AppColors.onboardingInk)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }

    /// The `kit-*` picture, or the item's symbol large until the image set is filled.
    @ViewBuilder private var picture: some View {
        if let name = item.info?.imageName, UIImage(named: name) != nil {
            Color.clear.overlay { Image(name).resizable().scaledToFill() }.clipped().accessibilityHidden(true)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppColors.dandanPink.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    LookBriefView(handoff: TutorialHandoff(tool: .blush, shades: [:], intensities: [:], blushStyle: .sunkissed),
                  photo: nil, onBack: {}, onStart: {})
}
