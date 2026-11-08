import SwiftUI
import UIKit

/// "Your final look": between the desired-look photo and the tutorial. The photo cropped to the feature, the must-have
/// product and tool as cards, what to keep nearby for mistakes as rows, and "Start tutorial". An item with an ⓘ opens
/// `KitItemSheet` (its picture, what it is, a tip).
struct LookBriefView: View {
    let handoff: TutorialHandoff
    let photo: UIImage?
    let onBack: () -> Void
    let onStart: () -> Void
    @State private var shown: MakeupKitItem?

    private static let ink = AppColors.onboardingInk
    private static let muted = AppColors.onboardingBody
    private static let faint = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9A / 255)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("Your final look")
                        .font(.system(size: 30, weight: .black)).fontWidth(.expanded)
                        .tracking(-0.6)
                        .foregroundStyle(Self.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, AppSpacing.medium)
                    picture
                        .frame(height: 196)
                        .padding(.top, AppSpacing.medium)
                    Text("What to prepare")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Self.ink)
                        .padding(.top, 28)
                    Text("Tap an item to see what it looks like.")
                        .font(.system(size: 14))
                        .foregroundStyle(Self.muted)
                        .padding(.top, 4)
                    sectionLabel("Must have", color: Self.ink).padding(.top, 20)
                    HStack(spacing: 12) {
                        ForEach(handoff.tool.mustHave) { card($0) }
                    }
                    .padding(.top, 10)
                    sectionLabel("Keep nearby · for mistakes", color: Self.muted).padding(.top, 24)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(handoff.tool.nearby) { row($0) }
                    }
                    .padding(.top, 12)
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
                    .frame(height: 56)
                    .background(AppColors.buttonInk, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
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
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private func sectionLabel(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }

    /// A must-have: icon and kind on top, the name (dotted underline and ⓘ when it opens a popup), then a short detail.
    private func card(_ item: MakeupKitItem) -> some View {
        Button { if item.info != nil { shown = item } } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.dandanPink)
                        .frame(width: 34, height: 34)
                        .background(AppColors.dandanPink.opacity(0.1), in: Circle())
                    sectionLabel(item.kind.label, color: Self.faint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    name(item, size: 17)
                    Text(item.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Self.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.info != nil ? Text("Shows what it looks like") : Text(""))
    }

    /// Something to keep nearby: icon, name, and a faint note after it.
    private func row(_ item: MakeupKitItem) -> some View {
        Button { if item.info != nil { shown = item } } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Self.muted)
                    .frame(width: 20)
                name(item, size: 15)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Self.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.info == nil)
        .accessibilityElement(children: .combine)
    }

    private func name(_ item: MakeupKitItem, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text(item.title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Self.ink)
                .underline(item.info != nil, pattern: .dot, color: AppColors.dandanPink)
            if item.info != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
                    .accessibilityHidden(true)
            }
        }
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

/// An item's popup: its kind and name, its picture, what it is, a tip, and "Got it".
private struct KitItemSheet: View {
    let item: MakeupKitItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind.label)
                        .textCase(.uppercase)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(AppColors.onboardingBody)
                    Text(item.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.onboardingInk)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.onboardingBody)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            picture
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .padding(.top, AppSpacing.medium)
            if let info = item.info {
                Text(info.text)
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.onboardingInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.medium)
                Label {
                    Text(info.tip)
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(AppColors.dandanPink)
                }
                .font(.system(size: 13))
                .foregroundStyle(AppColors.onboardingBody)
                .padding(.top, 10)
            }
            Spacer(minLength: AppSpacing.medium)
            Button { dismiss() } label: {
                Text("Got it")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColors.dandanPink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, 28)
        .padding(.bottom, AppSpacing.small)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.white)
        .preferredColorScheme(.light)
    }

    /// The `kit-*` picture, or the item's symbol large until the image set is filled.
    @ViewBuilder private var picture: some View {
        if let name = item.info?.imageName, UIImage(named: name) != nil {
            Image(name).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(AppColors.dandanPink.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.dandanPink.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    LookBriefView(handoff: TutorialHandoff(tool: .blush, shades: [:], intensities: [:], blushStyle: .sunkissed),
                  photo: nil, onBack: {}, onStart: {})
}
