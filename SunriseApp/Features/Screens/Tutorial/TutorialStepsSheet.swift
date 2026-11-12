import SwiftUI

/// The tutorial's steps sheet ("Tutorial"): one step per page with its picture and a Done / Now / Up next badge; swipe
/// sideways for the other steps (was a vertical list behind "Swipe for more"). It opens on the step being done and follows
/// it. Pictures are the design team's stills (`TutorialStepsSheet.imageName(tab:step:)`).
struct TutorialStepsSheet: View {
    struct Step {
        let title: Text
        let detail: Text?
        /// The step's picture (`tutorial-<tool>-<n>` image sets); a grey placeholder when nil.
        var imageName: String? = nil
    }

    /// The sheet's height: one step's card with its picture.
    static let compact = PresentationDetent.height(430)

    let steps: [Step]
    /// The step being done; `steps.count` when the side is finished (every step reads "Done").
    let current: Int
    let onClose: () -> Void
    @State private var page = 0

    private var shownStep: Int { min(current, steps.count - 1) }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    row(steps[index], index: index)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.top, AppSpacing.small)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            if steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? AppColors.dandanPink : Color.black.opacity(0.15))
                            .frame(width: index == page ? 18 : 6, height: 6)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: page)
                .padding(.bottom, AppSpacing.medium)
                .accessibilityHidden(true)
            }
        }
        .onAppear { page = shownStep }
        .onChange(of: current) { _, _ in withAnimation { page = shownStep } }
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
            picture(step)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(index == current ? .isSelected : [])
    }

    /// The step's still at its own 3 : 2 shape, full width; the grey box when there is none.
    @ViewBuilder private func picture(_ step: Step) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if let name = step.imageName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(339 / 226, contentMode: .fit)
                .clipShape(shape)
        } else {
            shape
                .fill(Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xF0 / 255))
                .frame(height: 170)
                .overlay {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.black.opacity(0.2))
                }
        }
    }

    /// The picture of step `step` (0-based) of a tool's tutorial, in `GuidedTutorialModel`'s lesson order.
    static func imageName(tab: TutorialTab, step: Int) -> String? {
        let (prefix, count) = switch tab {
        case .brows: ("tutorial-brow", 4)
        case .eyeliner: ("tutorial-liner", 3)
        case .blush: ("tutorial-blush", 1)
        }
        return (0..<count).contains(step) ? "\(prefix)-\(step + 1)" : nil
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
