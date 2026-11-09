import SwiftUI

/// Between the desired-look photo and the tutorial: the photo, the style's name and what to have ready, then
/// "Go to Tutorial". Placeholder layout (lo-fi "This is your final looks") until the design is final; the cards keep the
/// old get-ready page's style.
struct LookBriefView: View {
    let handoff: TutorialHandoff
    let photo: UIImage?
    let onBack: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    GlassCircleButton(symbol: "chevron.left", size: 48, tint: AppColors.glassLight, label: "Back", action: onBack)
                    Text("This is your final look")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppColors.snow)
                        .accessibilityAddTraits(.isHeader)
                    Group {
                        if let photo {
                            Color.clear.overlay { Image(uiImage: photo).resizable().scaledToFill() }.clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .accessibilityLabel("Your desired look")
                        } else {
                            FlowPlaceholderBox(label: "No photo taken", symbol: "camera")
                        }
                    }
                    .frame(height: 260)
                    Text(handoff.styleTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppColors.snow)
                        .frame(maxWidth: .infinity)
                    Text("What to prepare")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppColors.snow.opacity(0.9))
                        .padding(.top, AppSpacing.small)
                    VStack(spacing: 12) {
                        ForEach(handoff.tool.kit) { item in card(item) }
                    }
                }
                .padding(.horizontal, AppSpacing.medium)
                .padding(.top, AppSpacing.small)
            }
            FlowPrimaryButton(title: "Go to Tutorial", symbol: "arrow.right", action: onStart)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.medium)
        }
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }

    private func card(_ item: MakeupKitItem) -> some View {
        HStack(spacing: 16) {
            Group {
                if let name = item.imageName {
                    Image(name).resizable().scaledToFit().padding(4)
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(AppColors.flamingo)
                }
            }
            .frame(width: 58, height: 58)
            .background(AppColors.flamingo.opacity(0.18), in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 17, weight: .semibold))
                Text(item.detail).font(.system(size: 15))
            }
            .foregroundStyle(AppColors.wine)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AppColors.snow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LookBriefView(handoff: TutorialHandoff(tool: .blush, shades: [:], intensities: [:], blushStyle: .sunkissed),
                  photo: nil, onBack: {}, onStart: {})
}
