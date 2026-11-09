import SwiftUI

/// The tutorial's steps sheet ("Tutorial"): at its compact height only the current step with "Swipe for more"; dragged up,
/// every step with its picture and a Done / Now / Up next badge. Each step's picture is a placeholder until the design
/// team delivers the animations.
struct TutorialStepsSheet: View {
    struct Step {
        let title: Text
        let detail: Text?
    }

    /// The sheet's first height: the current step's card.
    static let compact = PresentationDetent.height(400)

    let steps: [Step]
    /// The step being done; `steps.count` when the side is finished (every step reads "Done").
    let current: Int
    let expanded: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(steps.indices, id: \.self) { index in
                                row(steps[index], index: index).id(index)
                            }
                        }
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.top, AppSpacing.small)
                        .padding(.bottom, AppSpacing.large * 2)
                    }
                    .scrollIndicators(.hidden)
                    // Scroll only as far as needed to show the current step: the first step opens at the top of the list.
                    .onAppear { if current > 0 { proxy.scrollTo(min(current, steps.count - 1)) } }
                    .onChange(of: current) { _, step in withAnimation { proxy.scrollTo(min(step, steps.count - 1)) } }
                }
            } else {
                row(steps[min(current, steps.count - 1)], index: min(current, steps.count - 1))
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.top, AppSpacing.small)
                Spacer(minLength: 0)
                if steps.count > 1 {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.compact.up").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.dandanPink)
                        Text("Swipe for more").font(.system(size: 13))
                            .foregroundStyle(AppColors.onboardingInk)
                    }
                    .padding(.bottom, AppSpacing.medium)
                    .accessibilityHidden(true)
                }
            }
        }
        .presentationBackground(.white)
        .presentationCornerRadius(28)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        ZStack {
            Text("Tutorial")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.onboardingInk)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.onboardingInk)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.top, 22)
        .padding(.bottom, AppSpacing.small)
    }

    private func row(_ step: Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Step \(index + 1): \(step.title)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                badge(index)
            }
            if let detail = step.detail {
                detail.font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xF0 / 255))
                .frame(height: 170)
                .overlay {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.black.opacity(0.2))
                }
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(index == current ? .isSelected : [])
    }

    @ViewBuilder private func badge(_ index: Int) -> some View {
        let label: LocalizedStringKey = index < current ? "Done" : index == current ? "Now" : "Up next"
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(index == current ? .white : AppColors.onboardingBody)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(index == current ? AppColors.dandanPink : Color.black.opacity(0.05)))
    }
}
