import SwiftUI

/// The tutorial's step-by-step sheet: every step with its animation and words, the current one marked. It opens half
/// height at the start; drag up for the full list or down to close. Each step's GIF is a placeholder box until the
/// design team delivers the animations.
struct TutorialStepsSheet: View {
    struct Step {
        let title: Text
        let detail: Text?
    }

    let steps: [Step]
    let current: Int
    /// "Right side" / "Left side" in the one-side-at-a-time tutorial.
    let sideTitle: LocalizedStringKey?
    /// A line of encouragement under the title, e.g. when the second side starts.
    var note: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title stays put; only the steps scroll under it.
            HStack(alignment: .firstTextBaseline) {
                Text("Steps").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if let sideTitle { Text(sideTitle).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.flamingo) }
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.top, AppSpacing.large)
            .padding(.bottom, AppSpacing.small)
            if let note {
                Text(note)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.snow.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.bottom, AppSpacing.small)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        ForEach(steps.indices, id: \.self) { index in
                            row(steps[index], index: index).id(index)
                        }
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.top, AppSpacing.small)
                    // Room under the last step so the sheet's rounded bottom never cuts it.
                    .padding(.bottom, AppSpacing.large * 2)
                }
                // Scroll only as far as needed to show the current step: the first step opens at the top of the list.
                .onAppear { if current > 0 { proxy.scrollTo(current) } }
                .onChange(of: current) { _, step in withAnimation { proxy.scrollTo(step) } }
            }
        }
        .foregroundStyle(AppColors.snow)
        .presentationBackground(AppColors.sheet)
    }

    private func row(_ step: Step, index: Int) -> some View {
        let isCurrent = index == current
        return HStack(alignment: .top, spacing: AppSpacing.medium) {
            FlowPlaceholderBox(label: "GIF", symbol: "play.rectangle")
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(AppColors.snow.opacity(0.7))
                step.title.font(.headline).fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail {
                    detail.font(.subheadline).foregroundStyle(AppColors.snow.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.snow.opacity(isCurrent ? 0.16 : 0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppColors.flamingo, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
