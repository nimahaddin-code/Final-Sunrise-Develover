import SwiftUI

/// First-run welcome: a light splash, then three swipeable pages (try on, learn step by step, compare).
struct OnboardingWelcomeScreen: View {
    let onStart: () -> Void
    @State private var page = 0
    @State private var showsSplash = true
    /// Page 1: the cards fan out from one stack, then the stickers fade in and float.
    @State private var deckOpen = false
    @State private var stickersIn = false
    /// Page 2: the step cards slide in from the right, top to bottom, then "3 easy steps" is stamped on.
    @State private var stepsIn = false
    @State private var stampIn = false
    /// Page 3: the outer line draws round once (its dots orbiting), the inner circle follows, then the icons pop in and float.
    @State private var ringIn = false
    @State private var innerIn = false
    @State private var iconsIn = false
    @State private var stepsIntroScheduled = false
    @State private var compareIntroScheduled = false
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
        if reduceMotion {
            showsSplash = false
            deckOpen = true
            stickersIn = true
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) { showsSplash = false }
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { deckOpen = true }
            try? await Task.sleep(for: .seconds(0.55))
            stickersIn = true
        }
    }

    private func advance() {
        let next = min(page + 1, 2)
        guard next != page else { return }
        withAnimation { page = next }
        playIntro(for: next)
    }

    /// Starts the current page's intro. Called both after a swipe and by Next, which changes the page before the art mounts.
    private func playIntro(for index: Int) {
        if index == 1 { playStepsIntro() } else if index == 2 { playCompareIntro() }
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

    /// Page 3's ring and the space it needs: the ring, its two labels, and the swipe page's padding.
    private func compareRing(height: CGFloat, width: CGFloat) -> CGFloat {
        min(width - 48, max(height * 0.41, 310))
    }

    private func content(height: CGFloat, width: CGFloat) -> some View {
        let buttonLabel: LocalizedStringKey = page == 2 ? "Get started" : "Next"
        let artHeight = max(height * 0.40, 300)
        let compareHeight = compareRing(height: height, width: width) + 82
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                DandanWordmark(size: 34).padding(.top, 12)
                Spacer(minLength: 8)
                // The swipe area runs edge to edge (the page's side padding is undone) so the tilted cards and shadows are
                // not cut off at the margins; each picture keeps the margin itself.
                TabView(selection: $page) {
                    artOne(height: height, width: width).artPage().tag(0)
                    artTwo(width: width).artPage().tag(1)
                    artThree(height: height, width: width).artPage().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: page) { _, newPage in playIntro(for: newPage) }
                .frame(height: max(artHeight + 82, compareHeight))
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
            let photoHeight = cardWidth * 600 / 515
            ZStack {
                // Closed deck: the back cards sit under the front card (its angle and place) until `deckOpen` fans them out.
                blankCard(width: cardWidth * 0.86, height: photoHeight * 0.92)
                    .rotationEffect(.degrees(deckOpen ? -10 : 4))
                    .offset(x: deckOpen ? -cardWidth * 0.08 : cardWidth * 0.30, y: deckOpen ? 4 : 0)
                blankCard(width: cardWidth * 0.93, height: photoHeight * 0.96)
                    .rotationEffect(.degrees(deckOpen ? -6 : 4))
                    .offset(x: deckOpen ? cardWidth * 0.08 : cardWidth * 0.30, y: deckOpen ? 2 : 0)
                // The photo PNG is already rotated 4 degrees (transparent corners); the white card behind it takes the same angle.
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
                        .frame(width: cardWidth * 0.925 + 16, height: photoHeight * 0.947 + 16)
                        .rotationEffect(.degrees(4))
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                    Image("onb-tryon-1").resizable().scaledToFit()
                        .frame(width: cardWidth, height: photoHeight)
                }
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 6) {
                        Circle().fill(AppColors.dandanPink).frame(width: 8, height: 8)
                        Text("Try on live").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(ink, in: Capsule())
                    .offset(x: 6, y: -18)
                }
                .offset(x: cardWidth * 0.30)
                // Stickers sit around the front card's centre, as fractions of its size.
                let sx = cardWidth * 0.30
                sticker("onb-sticker-brow-2", width: cardWidth * 0.40)
                    .stickerMotion(shown: stickersIn, order: 0, still: reduceMotion)
                    .offset(x: sx + cardWidth * 0.42, y: -photoHeight * 0.39)
                sticker("onb-sticker-brow-1", width: cardWidth * 0.32)
                    .stickerMotion(shown: stickersIn, order: 1, still: reduceMotion)
                    .offset(x: sx - cardWidth * 0.33, y: -photoHeight * 0.20)
                sticker("onb-sticker-blush", width: cardWidth * 0.27)
                    .stickerMotion(shown: stickersIn, order: 2, still: reduceMotion)
                    .offset(x: sx - cardWidth * 0.26, y: photoHeight * 0.07)
                sticker("onb-sticker-blush", width: cardWidth * 0.30)
                    .stickerMotion(shown: stickersIn, order: 3, still: reduceMotion)
                    .offset(x: sx + cardWidth * 0.42, y: photoHeight * 0.09)
                sticker("onb-sticker-lips", width: cardWidth * 0.29)
                    .stickerMotion(shown: stickersIn, order: 4, still: reduceMotion)
                    .offset(x: sx - cardWidth * 0.25, y: photoHeight * 0.29)
                HStack(spacing: 6) {
                    ForEach([0xE98BB5, 0xD07A70, 0xC9555E, 0xE79A70], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .rotationEffect(.degrees(-6))   // the middle card's angle
                .offset(x: -cardWidth * 0.50, y: -cardHeight * 0.36)
                // Fades in with the stickers, without floating.
                .opacity(stickersIn ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: stickersIn)
            }
            // Centres the opened deck (back card's left edge to the front card's right edge) on the screen.
            .offset(x: -cardWidth * 0.12)
            .frame(height: min(cardHeight + 24, artHeight + 40))
            .accessibilityHidden(true)
        }
    }

    private func blankCard(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }

    @ViewBuilder
    private func sticker(_ name: String, width: CGFloat) -> some View {
        if UIImage(named: name) != nil {
            Image(name).resizable().scaledToFit().frame(width: width)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        }
    }

    // MARK: Page 2: step by step

    /// Runs page 2's intro once, the first time the page is shown.
    private func playStepsIntro() {
        guard !stepsIntroScheduled else { return }
        stepsIntroScheduled = true
        if reduceMotion {
            stepsIn = true
            stampIn = true
            return
        }
        Task {
            // Next can select the page before its art is mounted; let it appear first so the cards start off-screen.
            try? await Task.sleep(for: .milliseconds(100))
            stepsIn = true
            try? await Task.sleep(for: .seconds(0.85))
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) { stampIn = true }
        }
    }

    private func artTwo(width: CGFloat) -> some View {
        Group {
            VStack(spacing: 12) {
                stepRow(image: "onb-step-1", title: "Find your apples", subtitle: "Step 1 · Smile wide", chip: .done)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topTrailing) {
                        // Stamp: drops from large and tilted onto the card, with a short bounce.
                        Text("3 easy steps")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.white, in: Capsule())
                            .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                            .scaleEffect(stampIn ? 1 : 2.4)
                            .rotationEffect(.degrees(stampIn ? 8 : -12))
                            .opacity(stampIn ? 1 : 0)
                            .offset(x: 4, y: -14)
                    }
                    .padding(.top, 10)
                    .slideIn(shown: stepsIn, order: 0, distance: width, still: reduceMotion)
                stepRow(image: "onb-step-2", title: "Dab on the colour", subtitle: "Step 2 · Two light taps", chip: .start, strongShadow: true)
                    .slideIn(shown: stepsIn, order: 1, distance: width, still: reduceMotion)
                stepRow(image: "onb-step-3", title: "Blend it up and out", subtitle: "Step 3 · Circles to the temple", chip: .next)
                    .padding(.horizontal, 12)
                    .slideIn(shown: stepsIn, order: 2, distance: width, still: reduceMotion)
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

    /// Runs page 3's intro once, the first time the page is shown.
    private func playCompareIntro() {
        guard !compareIntroScheduled else { return }
        compareIntroScheduled = true
        if reduceMotion {
            ringIn = true
            innerIn = true
            iconsIn = true
            return
        }
        Task {
            // As with page 2, wait for the page to mount when Next selects it.
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeInOut(duration: 0.9)) { ringIn = true }
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { innerIn = true }
            try? await Task.sleep(for: .seconds(0.4))
            iconsIn = true
        }
    }

    private func artThree(height: CGFloat, width: CGFloat) -> some View {
        Group {
            let ring = compareRing(height: height, width: width)
            let photo = ring * 0.66
            let pinkLine = Color(red: 0xF6 / 255, green: 0xC3 / 255, blue: 0xD6 / 255)
            VStack(spacing: 14) {
                ZStack {
                    // Outer line: drawn round once from the top, clockwise.
                    Circle().trim(from: 0, to: ringIn ? 1 : 0)
                        .stroke(pinkLine, lineWidth: 1.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: ring - 1.5, height: ring - 1.5)
                    // Its dots orbit slowly round the photo (one turn in 24 s) once the line is in.
                    TimelineView(.animation(paused: reduceMotion || !ringIn)) { context in
                        let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 24 * 360
                        ZStack {
                            ForEach([(-0.30, -0.92), (0.95, -0.18), (-0.88, 0.50), (0.45, 0.88)], id: \.0) { point in
                                Circle().strokeBorder(pinkLine, lineWidth: 2).background(Circle().fill(.white))
                                    .frame(width: 12, height: 12)
                                    .offset(x: ring / 2 * point.0, y: ring / 2 * point.1)
                            }
                        }
                        .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 360)))
                    }
                    .opacity(ringIn ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: ringIn)
                    Circle().fill(.white).frame(width: ring * 0.82, height: ring * 0.82)
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                        .scaleEffect(innerIn ? 1 : 0.7)
                        .opacity(innerIn ? 1 : 0)
                    splitPhoto(diameter: photo)
                    bubble("checkmark.circle", tint: AppColors.onboardingInk)
                        .stickerMotion(shown: iconsIn, order: 0, still: reduceMotion)
                        .offset(x: -ring * 0.36, y: -ring * 0.36)
                    bubble("sparkles", tint: AppColors.dandanPink)
                        .stickerMotion(shown: iconsIn, order: 1, still: reduceMotion)
                        .offset(x: ring * 0.46, y: -ring * 0.06)
                    bubble("paintbrush.pointed", tint: AppColors.onboardingInk)
                        .stickerMotion(shown: iconsIn, order: 2, still: reduceMotion)
                        .offset(x: -ring * 0.44, y: ring * 0.30)
                    bubble("face.smiling", tint: AppColors.onboardingInk)
                        .stickerMotion(shown: iconsIn, order: 3, still: reduceMotion)
                        .offset(x: ring * 0.34, y: ring * 0.38)
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

/// A page-1 sticker: fades and pops in when `shown` (staggered by `order`), then drifts and sways gently in a loop.
/// `still` (Reduce Motion) shows it at once, without drifting.
private struct StickerMotion: ViewModifier {
    let shown: Bool
    let order: Int
    let still: Bool

    func body(content: Content) -> some View {
        // Each sticker gets its own period and phase so they never move in step.
        let period = 2.6 + Double(order % 3) * 0.45
        let phase = Double(order) * 1.3
        TimelineView(.animation(paused: still || !shown)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 2 * .pi / period + phase
            content
                .offset(x: still ? 0 : cos(t * 0.7) * 3, y: still ? 0 : sin(t) * 6)
                .rotationEffect(.degrees(still ? 0 : sin(t * 0.8) * 3))
        }
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.6)
        .animation(still ? nil : .spring(response: 0.5, dampingFraction: 0.6).delay(Double(order) * 0.09), value: shown)
    }
}

private extension View {
    /// A page-2 step card: waits off the right edge until `shown`, then slides in, one after another by `order`.
    func slideIn(shown: Bool, order: Int, distance: CGFloat, still: Bool) -> some View {
        offset(x: shown ? 0 : distance)
            .opacity(shown ? 1 : 0)
            .animation(still ? nil : .spring(response: 0.5, dampingFraction: 0.82).delay(Double(order) * 0.15), value: shown)
    }

    func stickerMotion(shown: Bool, order: Int, still: Bool) -> some View {
        modifier(StickerMotion(shown: shown, order: order, still: still))
    }

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
