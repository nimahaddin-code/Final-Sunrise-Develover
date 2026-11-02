import SwiftUI

struct FeaturePlaceholderView<Actions: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let explanation: LocalizedStringKey
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(AppColors.rose).accessibilityHidden(true)
                Text(title).font(AppTypography.title)
                Text("SCAFFOLD · NOT IMPLEMENTED")
                    .font(AppTypography.caption).bold().foregroundStyle(AppColors.rose)
                Text(explanation).font(AppTypography.body)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.large)
            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .padding(AppSpacing.large)
        }
        .foregroundStyle(AppColors.ink)
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}
