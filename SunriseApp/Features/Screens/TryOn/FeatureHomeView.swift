import SwiftUI

/// The first page after the welcome: a light page with a swipeable slider of tool cards (Eyeliner, Blush, Brows; Blush
/// first in view), the selected tool's name, steps, minutes and a line about it, and "Start Lesson" for the selected tool.
/// Plain SwiftUI, no camera.
struct FeatureHomeView: View {
    let onSelect: (TryOnTool) -> Void

    private static let order: [TryOnTool] = [.eyeliner, .blush, .eyebrow]
    private static let cardWidthFraction: CGFloat = 0.68

    @State private var selected: TryOnTool? = .blush
    @State private var sliderWidth: CGFloat = 0

    private var current: TryOnTool { selected ?? .blush }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hi fellas!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.wine)
                Text("What do you want to learn today?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.plumInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.small)

            slider
                .frame(maxHeight: .infinity)
                .layoutPriority(-1)
                .padding(.top, AppSpacing.medium)

            dots
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.small)

            VStack(alignment: .leading, spacing: 10) {
                Text(name(current))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppColors.plumInk)
                HStack(spacing: 8) {
                    chip(Text("\(steps(current)) steps"), fill: chipFill(current))
                    chip(Text("\(minutes(current)) min"), fill: chipFill(current))
                }
                Text(blurb(current))
                    .font(.system(size: 15))
                    .foregroundStyle(Self.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.medium)

            Spacer(minLength: AppSpacing.medium)

            Button { onSelect(current) } label: {
                HStack(spacing: 8) {
                    Text("Start Lesson")
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.flamingo, in: Capsule())
                .shadow(color: AppColors.flamingo.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.large)
            .padding(.bottom, AppSpacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { AppColors.homeCanvas.ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Slider

    private var slider: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.order) { tool in
                    Button { withAnimation(.snappy) { selected = tool } } label: {
                        Image(Self.imageName(tool))
                            .resizable().scaledToFit()
                    }
                    .buttonStyle(.plain)
                    // The container already excludes the content margins below, so this is cardWidthFraction of the slider.
                    .containerRelativeFrame(.horizontal)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .opacity(phase.isIdentity ? 1 : 0.6)
                    }
                    .accessibilityLabel(name(tool))
                    .accessibilityAddTraits(selected == tool ? .isSelected : [])
                    .id(tool)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, sliderWidth * (1 - Self.cardWidthFraction) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selected)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sliderWidth = $0 }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Self.order) { tool in
                Capsule()
                    .fill(selected == tool ? AppColors.plumInk : Self.dotGrey)
                    .frame(width: selected == tool ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: selected)
        .accessibilityHidden(true)
    }

    private func chip(_ text: Text, fill: Color) -> some View {
        text
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.plumInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
    }

    // MARK: Per-tool content

    private static let bodyText = Color(red: 0x6B / 255, green: 0x5F / 255, blue: 0x63 / 255)
    private static let dotGrey = Color(red: 0xD9 / 255, green: 0xD2 / 255, blue: 0xCE / 255)

    private static func imageName(_ tool: TryOnTool) -> String {
        switch tool {
        case .eyeliner: "home-card-eyeliner"
        case .blush: "home-card-blush"
        case .eyebrow: "home-card-brows"
        }
    }

    /// Chip fill tinted to the tool's card: eyeliner #EAE3F2, blush #F9E5EF, brows #FAF2EA.
    private func chipFill(_ tool: TryOnTool) -> Color {
        switch tool {
        case .eyeliner: Color(red: 0xEA / 255, green: 0xE3 / 255, blue: 0xF2 / 255)
        case .blush: Color(red: 0xF9 / 255, green: 0xE5 / 255, blue: 0xEF / 255)
        case .eyebrow: Color(red: 0xFA / 255, green: 0xF2 / 255, blue: 0xEA / 255)
        }
    }

    private func name(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .eyeliner: "Eyeliner"
        case .blush: "Blush"
        case .eyebrow: "Brows"
        }
    }

    private func blurb(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .eyeliner: "A liner shape that suits your eyes."
        case .blush: "A soft flush placed right for your cheeks."
        case .eyebrow: "Fuller, tidy brows that frame your face."
        }
    }

    private func steps(_ tool: TryOnTool) -> Int {
        switch tool {
        case .eyeliner: GuidedTutorialModel.linerLessons.count
        case .blush: GuidedTutorialModel.blushLessons.count
        case .eyebrow: GuidedTutorialModel.browLessons.count
        }
    }

    private func minutes(_ tool: TryOnTool) -> Int {
        ToolInfo.of(tool, handoff: TutorialHandoff(tool: tool, shades: [:], intensities: [:])).minutes
    }
}
