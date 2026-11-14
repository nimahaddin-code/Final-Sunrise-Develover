import SwiftUI

/// The first page after the welcome: the onboarding glow with "Hi, pretty!", a swipeable slider of tool cards (Eyeliner,
/// Blush, Brows, Lips; Blush first in view; steps and minutes as chips inside each card) and the selected tool's name and a line
/// about it. Tap the centred card to open Try On for it; tap a side card to bring it to the centre. Plain SwiftUI, no camera.
struct FeatureHomeView: View {
    let onSelect: (TryOnTool) -> Void
    /// -Nimah: the saved looks shown under the tool cards (nil: no My Looks row).
    var looks: MyLookStore? = nil
    var onOpenLook: (UUID) -> Void = { _ in }
    var onOpenMyLooks: () -> Void = {}

    private static let order: [TryOnTool] = [.eyeliner, .blush, .eyebrow, .lips]
    private static let cardWidthFraction: CGFloat = 0.68

    @State private var selected: TryOnTool? = .blush
    @State private var sliderWidth: CGFloat = 0
    @State private var isScrolling = false
    @State private var opening = false
    /// Steps and minutes per tool, computed once (and again when the language changes) instead of on every body pass.
    @State private var meta: [TryOnTool: (steps: Int, minutes: Int)] = FeatureHomeView.makeMeta()
    @AppStorage(AppLanguage.key) private var language = AppLanguage.current

    private var current: TryOnTool { selected ?? .blush }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hi, pretty!")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppColors.onboardingInk)
                    Spacer()
                    languageMenu
                }
                Text("What do you want to learn today?")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.onboardingInk)
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
                Text(blurb(current))
                    .font(.system(size: 15))
                    .foregroundStyle(Self.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.medium)

            if let looks {
                MyLooksSection(store: looks, onOpen: onOpenLook, onSeeAll: onOpenMyLooks)
                    .padding(.top, AppSpacing.medium)
            }

            Spacer(minLength: AppSpacing.medium)
        }
        .padding(.bottom, AppSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { OnboardingGlow() }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { opening = false }
        .onChange(of: language) { meta = Self.makeMeta() }
    }

    private func tap(_ tool: TryOnTool) {
        guard !isScrolling, !opening else { return }
        if tool == current {
            opening = true
            onSelect(tool)
        } else {
            withAnimation(.snappy) { selected = tool }
        }
    }

    // MARK: Slider

    private var slider: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(Self.order) { tool in
                    Button { tap(tool) } label: {
                        Image(Self.imageName(tool))
                        .resizable().scaledToFit()
                        .overlay(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(name(tool))
                                    .textCase(.uppercase)
                                    .font(.system(size: 30, weight: .black).width(.expanded))
                                    .foregroundStyle(Self.titleColor(tool))
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                Text(tagline(tool))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Self.titleColor(tool).opacity(0.8))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        }
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 6) {
                                chip(Text("^[\(meta[tool]?.steps ?? 0) step](inflect: true)"))
                                chip(Text("\(meta[tool]?.minutes ?? 0) min"))
                            }
                            .padding(16)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle())
                    // The container already excludes the content margins below, so this is cardWidthFraction of the slider.
                    .containerRelativeFrame(.horizontal)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.9)
                            .opacity(phase.isIdentity ? 1 : 0.6)
                    }
                    .accessibilityLabel(name(tool))
                    .accessibilityHint("Opens Try On")
                    .accessibilityAddTraits(selected == tool ? .isSelected : [])
                    .id(tool)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, sliderWidth * (1 - Self.cardWidthFraction) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selected)
        .onScrollPhaseChange { _, phase in isScrolling = phase != .idle }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sliderWidth = $0 }
    }

    /// Top right: the app's language. A choice shows at once and is kept for the next launch.
    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: Binding(get: { language }, set: { $0.select() })) {
                ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.onboardingInk)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Language")
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(Self.order) { tool in
                Capsule()
                    .fill(selected == tool ? AppColors.dandanPink : Self.dotGrey)
                    .frame(width: selected == tool ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: selected)
        .accessibilityHidden(true)
    }

    private func chip(_ text: Text) -> some View {
        text
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.plumInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.7), in: Capsule())
    }

    // MARK: Per-tool content

    private static let bodyText = Color(red: 0x6B / 255, green: 0x5F / 255, blue: 0x63 / 255)
    private static let dotGrey = Color(red: 0xD9 / 255, green: 0xD2 / 255, blue: 0xCE / 255)

    private static func imageName(_ tool: TryOnTool) -> String {
        switch tool {
        case .eyeliner: "home-card-eyeliner"
        case .blush: "home-card-blush"
        case .eyebrow: "home-card-brows"
        case .lips: "home-card-lips"
        }
    }

    private func name(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .eyeliner: "Eyeliner"
        case .blush: "Blush"
        case .eyebrow: "Brows"
        case .lips: "Lips"
        }
    }

    private func tagline(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .eyeliner: "Wings & lines"
        case .blush: "Soft flush, fresh glow"
        case .eyebrow: "Shape & fill"
        case .lips: "Colour & shape"
        }
    }

    private static func titleColor(_ tool: TryOnTool) -> Color {
        switch tool {
        case .eyeliner: Color(red: 0xF2 / 255, green: 0xA6 / 255, blue: 0xC8 / 255)
        case .blush: Color(red: 0xFC / 255, green: 0xE4 / 255, blue: 0xF4 / 255)
        case .eyebrow: Color(red: 0x5A / 255, green: 0x2E / 255, blue: 0x12 / 255)
        case .lips: Color(red: 0xFF / 255, green: 0xE3 / 255, blue: 0xE0 / 255)
        }
    }

    private func blurb(_ tool: TryOnTool) -> LocalizedStringKey {
        switch tool {
        case .eyeliner: "A liner shape that suits your eyes."
        case .blush: "A soft flush placed right for your cheeks."
        case .eyebrow: "Fuller, tidy brows that frame your face."
        case .lips: "A lip colour and shape that suits you."
        }
    }

    private static func makeMeta() -> [TryOnTool: (steps: Int, minutes: Int)] {
        Dictionary(uniqueKeysWithValues: order.map { ($0, (steps(for: $0), minutes(for: $0))) })
    }

    private static func steps(for tool: TryOnTool) -> Int {
        switch tool {
        case .eyeliner: GuidedTutorialModel.linerLessons.count
        case .blush: GuidedTutorialModel.blushLessons.count
        case .eyebrow: GuidedTutorialModel.browLessons.count
        case .lips: GuidedTutorialModel.lipLessons.count
        }
    }

    private static func minutes(for tool: TryOnTool) -> Int {
        ToolInfo.of(tool, handoff: TutorialHandoff(tool: tool, shades: [:], intensities: [:])).minutes
    }
}

/// Pressed feedback for a tool card: a slight shrink while the finger is down.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
