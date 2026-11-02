import SwiftUI

/// The page between Try On and the tutorial: four things to have ready, then "Go to Tutorial". Plain SwiftUI, no camera.
struct TutorialPrepView: View {
    let onBack: () -> Void
    let onStart: () -> Void

    private struct Tip: Identifiable {
        let id: String
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let tips = [
        Tip(id: "face", symbol: "drop", title: "Clean, bare face", detail: "Wash up and moisturise so makeup sits nicely."),
        Tip(id: "light", symbol: "sun.max", title: "Bright, soft light", detail: "Face a window, or switch on the flash later."),
        Tip(id: "kit", symbol: "paintbrush.pointed", title: "Your makeup kit", detail: "Spoolie, brow pencil, blush or eyeliner depends on which."),
        Tip(id: "phone", symbol: "iphone", title: "Phone at eye level", detail: "Lean it on something so both hands stay free.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassCircleButton(symbol: "chevron.left", size: 48, tint: AppColors.glassLight, label: "Back", action: onBack)
                .padding(.bottom, AppSpacing.extraLarge)
            Text("Before we start the tutorial,")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppColors.snow.opacity(0.9))
                .padding(.horizontal, AppSpacing.small)
            Text("Let's get you ready")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppColors.snow)
                .padding(.horizontal, AppSpacing.small)
                .padding(.bottom, AppSpacing.medium)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 12) {
                ForEach(tips) { tip in card(tip) }
            }
            Spacer(minLength: AppSpacing.large)
            Button(action: onStart) {
                Label("Go to Tutorial", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppColors.snow)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    // Native glass over a solid pink, so the wine background cannot show through and dull it:
                    // the glass still draws its own sheen and rim, like the design.
                    .background(Capsule().fill(AppColors.prepPink))
                    .glassCapsule(tint: AppColors.prepPink.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(_ tip: Tip) -> some View {
        HStack(spacing: 16) {
            Image(systemName: tip.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppColors.flamingo)
                .frame(width: 58, height: 58)
                .background(AppColors.flamingo.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.system(size: 17, weight: .semibold))
                Text(tip.detail).font(.system(size: 15))
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

/// Title first, icon after it ("Go to Tutorial →").
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}
