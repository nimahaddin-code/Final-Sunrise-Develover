import SwiftUI

struct PrimaryButton: View {
    let title: LocalizedStringKey
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(AppSpacing.small)
                .background(enabled ? AppColors.rose : AppColors.subtle, in: Capsule())
                .foregroundStyle(.white)
        }.buttonStyle(.plain)
    }
}
