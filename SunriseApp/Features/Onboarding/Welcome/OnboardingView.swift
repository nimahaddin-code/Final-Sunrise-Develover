import SwiftUI

/// First-run welcome: a light splash, then three swipeable pages (try on, learn step by step, compare).
struct OnboardingWelcomeScreen: View {
    let onStart: () -> Void
    @State private var page = 0
    @State private var showsSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17
    @ScaledMetric(relativeTo: .title2) private var buttonSize: CGFloat = 20

    private let ink = AppColors.buttonInk

    var body: some View {
        ZStack {
            OnboardingGlow()
            GeometryReader { proxy in
                content(height: proxy.size.height, width: proxy.size.width)
            }
            if showsSplash {
                splash.transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            dismissSplash()
        }
    }

    private func dismissSplash() {
        guard showsSplash else { return }
        if reduceMotion { showsSplash = false } else { withAnimation(.easeInOut(duration: 0.45)) { showsSplash = false } }
    }

    private func advance() {
        withAnimation { page = min(page + 1, 2) }
    }

    // MARK: Splash

    private var splash: some View {
        ZStack {
            OnboardingGlow()
            VStack(spacing: 14) {
                DandanWordmark(size: 90)
                Text("makeup made for your face")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissSplash)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Fixed frame (only the art swipes)

    private var copy: [(heading: LocalizedStringKey, text: LocalizedStringKey)] {
        [("Try it on before you put it on", "Swap blush, brows and liner live on your own face before you touch a brush."),
         ("Step by step, at your own pace", "Bite-size steps and a live face map show where to go and how much."),
         ("See how you did, side by side", "Put your try-on next to your real result and get gentle tips for next time.")]
    }

    private func copyBlock(_ index: Int) -> some View {
        VStack(spacing: 12) {
            Text(copy[index].heading)
                .font(.system(size: headingSize, weight: .black)).fontWidth(.expanded)
                .foregroundStyle(AppColors.onboardingInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(copy[index].text)
                .font(.system(size: bodySize))
                .foregroundStyle(AppColors.onboardingBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func content(height: CGFloat, width: CGFloat) -> some View {
        let buttonLabel: LocalizedStringKey = page == 2 ? "Get started" : "Next"
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                DandanWordmark(size: 34).padding(.top, 12)
                Spacer(minLength: 8)
                // The swipe area runs edge to edge (the page's side padding is undone) so the tilted cards and shadows are
                // not cut off at the margins; each picture keeps the margin itself.
                TabView(selection: $page) {
                    artOne(height: height, width: width).artPage().tag(0)
                    artTwo.artPage().tag(1)
                    artThree(height: height, width: width).artPage().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: max(height * 0.40, 300) + 50 + 32)
                .padding(.horizontal, -24)
                Spacer(minLength: 16)
                // All three texts reserve the height; only the current one shows, crossfading.
                ZStack(alignment: .top) {
                    ForEach(0..<3) { copyBlock($0).hidden() }
                    copyBlock(page).id(page).transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: page)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(pageSwipe)
                Spacer(minLength: 16)
                indicator
                Button(action: { if page == 2 { onStart() } else { advance() } }) {
                    Text(buttonLabel)
                        .font(.system(size: buttonSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(ink, in: Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.25), value: page)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .frame(minHeight: height)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    /// Swipe left for the next page, right for the previous one; used on the text and the dots (the picture is a TabView).
    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 20).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            withAnimation { page = value.translation.width < 0 ? min(page + 1, 2) : max(page - 1, 0) }
        }
    }

    private var indicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == page ? AppColors.dandanPink : Color(red: 0xD6 / 255, green: 0xD3 / 255, blue: 0xD4 / 255))
                    .frame(width: index == page ? 48 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
        // Swipe on the dots too: left for next, right for back, on a full-width strip so it is easy to hit.
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .gesture(pageSwipe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of 3")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: withAnimation { page = min(page + 1, 2) }
            case .decrement: withAnimation { page = max(page - 1, 0) }
            @unknown default: break
            }
        }
    }

    // MARK: Page 1: try it on

    private func artOne(height: CGFloat, width: CGFloat) -> some View {
        Group {
            let artHeight = max(height * 0.40, 300)
            let cardWidth = min(width * 0.50, artHeight * 0.64)
            let cardHeight = cardWidth * 1.55
            ZStack {
                photoCard(name: "onb-tryon-3", width: cardWidth * 0.86, height: cardHeight * 0.86)
                    .rotationEffect(.degrees(-12)).offset(x: -cardWidth * 0.46, y: 4)
                photoCard(name: "onb-tryon-2", width: cardWidth * 0.93, height: cardHeight * 0.93)
                    .rotationEffect(.degrees(-8)).offset(x: -cardWidth * 0.14, y: 2)
                photoCard(name: "onb-tryon-1", width: cardWidth, height: cardHeight)
                    .overlay(alignment: .bottomTrailing) {
                        HStack(spacing: 6) {
                            Circle().fill(AppColors.dandanPink).frame(width: 8, height: 8)
                            Text("Try on live").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(ink, in: Capsule())
                        .offset(x: 6, y: -18)
                    }
                    .rotationEffect(.degrees(-4)).offset(x: cardWidth * 0.36)
                HStack(spacing: 6) {
                    ForEach([0xE98BB5, 0xD07A70, 0xC9555E, 0xE79A70], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .offset(x: -cardWidth * 0.62, y: -cardHeight * 0.36)
            }
            .frame(height: min(cardHeight + 24, artHeight + 40))
            .accessibilityHidden(true)
        }
    }

    private func photoCard(name: String, width: CGFloat, height: CGFloat) -> some View {
        OnboardingPhoto(name: name)
            .frame(width: width - 16, height: height - 16)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }

    // MARK: Page 2: step by step

    private var artTwo: some View {
        Group {
            VStack(spacing: 12) {
                stepRow(image: "onb-step-1", title: "Find your apples", subtitle: "Step 1 · Smile wide", chip: .done)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topTrailing) {
                        Text("3 easy steps")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                            .rotationEffect(.degrees(8))
                            .offset(x: 4, y: -14)
                    }
                    .padding(.top, 10)
                stepRow(image: "onb-step-2", title: "Dab on the colour", subtitle: "Step 2 · Two light taps", chip: .start, strongShadow: true)
                stepRow(image: "onb-step-3", title: "Blend it up and out", subtitle: "Step 3 · Circles to the temple", chip: .next)
                    .padding(.horizontal, 12)
            }
        }
    }

    private enum Chip { case done, start, next }

    private func stepRow(image: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, chip: Chip,
                         strongShadow: Bool = false) -> some View {
        HStack(spacing: 12) {
            OnboardingPhoto(name: image)
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(AppColors.onboardingInk)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(AppColors.onboardingBody)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2).minimumScaleFactor(0.8)
            chipView(chip)
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(strongShadow ? 0.20 : 0.08), radius: strongShadow ? 18 : 10, y: strongShadow ? 10 : 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        let light = Color(red: 0xEE / 255, green: 0xEC / 255, blue: 0xED / 255)
        switch chip {
        case .done:
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text("Done")
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.onboardingInk)
            .padding(.horizontal, 12).padding(.vertical, 8).background(light, in: Capsule())
        case .start:
            Text("Start").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8).background(ink, in: Capsule())
        case .next:
            Text("Next").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.onboardingInk)
                .padding(.horizontal, 14).padding(.vertical, 8).background(light, in: Capsule())
        }
    }

    // MARK: Page 3: compare

    private func artThree(height: CGFloat, width: CGFloat) -> some View {
        Group {
            let ring = min(width - 40, max(height * 0.34, 270))
            let photo = ring * 0.66
            let pinkLine = Color(red: 0xF6 / 255, green: 0xC3 / 255, blue: 0xD6 / 255)
            VStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(pinkLine, lineWidth: 1.5).frame(width: ring, height: ring)
                    ForEach([(-0.30, -0.92), (0.95, -0.18), (-0.88, 0.50), (0.45, 0.88)], id: \.0) { point in
                        Circle().strokeBorder(pinkLine, lineWidth: 2).background(Circle().fill(.white))
                            .frame(width: 12, height: 12)
                            .offset(x: ring / 2 * point.0, y: ring / 2 * point.1)
                    }
                    Circle().fill(.white).frame(width: ring * 0.82, height: ring * 0.82)
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                    splitPhoto(diameter: photo)
                    bubble("checkmark.circle", tint: AppColors.onboardingInk).offset(x: -ring * 0.36, y: -ring * 0.36)
                    bubble("sparkles", tint: AppColors.dandanPink).offset(x: ring * 0.46, y: -ring * 0.06)
                    bubble("paintbrush.pointed", tint: AppColors.onboardingInk).offset(x: -ring * 0.44, y: ring * 0.30)
                    bubble("face.smiling", tint: AppColors.onboardingInk).offset(x: ring * 0.34, y: ring * 0.38)
                }
                .frame(width: ring, height: ring)
                .overlay(alignment: .topTrailing) {
                    Text("92% match")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                        .rotationEffect(.degrees(8))
                        .offset(x: 8, y: 6)
                }
                HStack(spacing: 10) {
                    Text("Try-on").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
                    Text("Your result").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(ink, in: Capsule())
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func splitPhoto(diameter: CGFloat) -> some View {
        ZStack {
            OnboardingPhoto(name: "onb-compare-before").frame(width: diameter, height: diameter)
            OnboardingPhoto(name: "onb-compare-after").frame(width: diameter, height: diameter)
                .mask(alignment: .trailing) { Rectangle().frame(width: diameter / 2) }
            Rectangle().fill(.white).frame(width: 3, height: diameter)
            HStack(spacing: 3) { Image(systemName: "chevron.left"); Image(systemName: "chevron.right") }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(AppColors.onboardingInk)
                .frame(width: 36, height: 36)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private func bubble(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
    }
}

/// "dandan" in expanded black pink followed by a black dot, baseline aligned.
private struct DandanWordmark: View {
    let size: CGFloat
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.04 * scale) {
            Text(verbatim: "dandan")
                .font(.system(size: size * scale, weight: .black)).fontWidth(.expanded)
                .foregroundStyle(AppColors.dandanPink)
                .lineLimit(1).minimumScaleFactor(0.5)
            Circle().fill(.black)
                .frame(width: size * 0.15 * scale, height: size * 0.15 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "dandan"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Soft pink and grey glow on white, behind every onboarding screen.
struct OnboardingGlow: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                Circle().fill(Color(red: 0xF9 / 255, green: 0xC6 / 255, blue: 0xDA / 255).opacity(0.75))
                    .frame(width: proxy.size.width * 1.1).blur(radius: 70)
                    .position(x: proxy.size.width * 0.2, y: proxy.size.height * 0.12)
                Circle().fill(Color.gray.opacity(0.14))
                    .frame(width: proxy.size.width * 1.2).blur(radius: 80)
                    .position(x: proxy.size.width * 0.8, y: proxy.size.height * 0.88)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// An onboarding picture from the asset catalog, or a light placeholder until the image set is filled.
private struct OnboardingPhoto: View {
    let name: String

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else {
            ZStack {
                Color(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xE9 / 255)
                Image(systemName: "person.crop.square")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(.black.opacity(0.12))
            }
        }
    }
}

private extension View {
    /// One onboarding picture inside the edge-to-edge swipe area: centred, with the page's 24 pt side margin.
    func artPage() -> some View {
        frame(maxWidth: 560).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
