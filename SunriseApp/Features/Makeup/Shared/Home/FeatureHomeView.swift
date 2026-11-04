import SwiftUI

/// The first page after the welcome: one card per tool (Blush, Eyeliner, Eyebrow). Tapping a card opens Try On for that tool.
/// Plain SwiftUI, no camera.
struct FeatureHomeView: View {
    let onSelect: (TryOnTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .frame(maxWidth: 160, maxHeight: 44)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, AppSpacing.extraLarge)
            Text("What do you want to try?")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppColors.snow)
                .padding(.horizontal, AppSpacing.small)
                .padding(.bottom, AppSpacing.medium)
            VStack(spacing: 12) {
                ForEach(TryOnTool.allCases) { tool in card(tool) }
            }
            Spacer(minLength: AppSpacing.large)
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func detail(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .blush: "Find where blush sits best on your cheeks."
        case .eyeliner: "Try a liner shaped for your eyes."
        case .eyebrow: "Try brow shapes on your own brows."
        }
    }

    private func card(_ tool: TryOnTool) -> some View {
        Button { onSelect(tool) } label: {
            HStack(spacing: 16) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.flamingo)
                    .frame(width: 58, height: 58)
                    .background(AppColors.flamingo.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title).font(.system(size: 17, weight: .semibold))
                    Text(detail(tool)).font(.system(size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AppColors.wine)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.wine)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(AppColors.snow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}
