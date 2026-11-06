import SwiftUI

/// The home screen: pick one makeup feature, then Continue opens its Try On. Layout follows the lo-fi "Pick a Feature";
/// tile artwork is SF Symbols until the design team's icons arrive.
struct FeaturePickerView: View {
    let onContinue: (TryOnTool) -> Void
    @State private var selected: TryOnTool?

    /// In the lo-fi's order.
    private let tools: [TryOnTool] = [.eyebrow, .blush, .eyeliner]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .frame(maxWidth: 160, maxHeight: 44)
                .accessibilityLabel("dandan")
                .padding(.top, AppSpacing.small)
            Spacer()
            Text("Pick a Feature")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColors.snow)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, AppSpacing.large)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(tools) { tool in tile(tool) }
            }
            .padding(.horizontal, AppSpacing.small)
            .padding(.bottom, AppSpacing.extraLarge)
            FlowPrimaryButton(title: "Continue") {
                if let selected { onContinue(selected) }
            }
            .disabled(selected == nil)
            .padding(.horizontal, AppSpacing.large)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func tile(_ tool: TryOnTool) -> some View {
        let isSelected = tool == selected
        return Button { selected = tool } label: {
            VStack(spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(isSelected ? AppColors.snow : AppColors.flamingo)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(isSelected ? AppColors.glassSelected : AppColors.raisedWine,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(AppColors.snow.opacity(isSelected ? 0.6 : 0.08), lineWidth: isSelected ? 2 : 1)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                Text(tool.shortTitle)
                    .font(.headline)
                    .foregroundStyle(AppColors.snow.opacity(isSelected ? 1 : 0.75))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tool.shortTitle))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension TryOnTool {
    /// The home tile's label.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .blush: "Blush"
        case .eyeliner: "Liner"
        case .eyebrow: "Brows"
        }
    }
}

#Preview { FeaturePickerView { _ in } }
