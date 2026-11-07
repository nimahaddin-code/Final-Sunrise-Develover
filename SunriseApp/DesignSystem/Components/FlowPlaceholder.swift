import SwiftUI

/// Stand-in for a screen of the new flow until its owner designs it: what the screen is, who builds it, and the button to
/// the next screen. Developer text, English only and not localised. Replace the whole view when the real screen is built.
struct FlowPlaceholder<Content: View>: View {
    let title: String
    let owner: String
    let note: String
    var buttonTitle: String?
    var action: (() -> Void)?
    var onBack: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            if let onBack {
                GlassCircleButton(symbol: "chevron.left", size: 48, tint: AppColors.glassLight, label: "Back", action: onBack)
            }
            Text(verbatim: "PLACEHOLDER · \(owner.uppercased())")
                .font(AppTypography.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.snow.opacity(0.7))
            Text(verbatim: title).font(.system(size: 30, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(verbatim: note).font(AppTypography.body).foregroundStyle(AppColors.snow.opacity(0.85))
            content
            Spacer(minLength: AppSpacing.medium)
            if let buttonTitle, let action {
                Button(action: action) {
                    Text(verbatim: buttonTitle)
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Capsule().fill(AppColors.prepPink))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(AppColors.snow)
        .padding(AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { MainBackground() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension FlowPlaceholder where Content == EmptyView {
    init(title: String, owner: String, note: String, buttonTitle: String? = nil, action: (() -> Void)? = nil,
         onBack: (() -> Void)? = nil) {
        self.init(title: title, owner: owner, note: note, buttonTitle: buttonTitle, action: action, onBack: onBack) { EmptyView() }
    }
}
