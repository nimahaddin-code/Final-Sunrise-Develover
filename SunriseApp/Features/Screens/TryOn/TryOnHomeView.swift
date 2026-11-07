import SwiftUI

/// Try On for the one tool picked on the home screen: header, live camera card with its shape row, a shade row, an
/// intensity bar and Continue (to the desired-look photo). Every tool uses the standard look; there is no face or eye scan.
struct TryOnHomeView: View {
    @StateObject private var home: TryOnHomeModel
    var onBack: () -> Void
    var onContinue: (TutorialHandoff) -> Void
    @AppStorage(DeveloperTools.key) private var developerTools = false
    @AppStorage(NewFlow.key) private var newFlow = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible=false
    @State private var showColours=false
    @State private var paletteSource = PaletteSource.camera
    @StateObject private var light = ScreenLight()
    /// Brow only: the shade row and intensity bar, opened by the palette button over the brow pictures.
    @State private var showsShades = false
    /// Brow Try On has its own layout: light page, flash top right, palette button, Continue at the bottom.
    private var isBrow: Bool { home.tool == .eyebrow }
    /// Dark labels on the white screen of the light and on the light brow page.
    private var ink: Color { light.isOn ? .black : isBrow ? AppColors.plumInk : AppColors.snow }

    /// One screen per tool: `tool` is the only makeup it shows, with its shape, colour and intensity.
    init(plan: MakeupPlan, assessment: FaceShapeAssessment, checker: any FaceTrackingAvailabilityChecking,
         tool: TryOnTool, onBack: @escaping () -> Void, onContinue: @escaping (TutorialHandoff) -> Void) {
        _home = StateObject(wrappedValue: TryOnHomeModel(tool: tool, plan: plan, assessment: assessment, checker: checker))
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            // Brow: no logo row; back and light sit over the camera's top corners so the camera fills the space.
            if !isBrow { header }
            // -Nimah: Dismantle the face camera while the palette picker owns the rear camera.
            if showColours {
                RoundedRectangle(cornerRadius:AppSpacing.cornerRadius).fill(AppColors.cocoa)
                    .overlay(Text("Choosing makeup colour")).frame(maxHeight:.infinity)
            } else {
                TryOnLiveCard(home: home, light: light, showsLightButton: !isBrow, captionAtTop: isBrow).frame(maxHeight:.infinity)
                    .overlay(alignment: .top) { if isBrow { browTopButtons } }
                    .overlay(alignment: .topTrailing) {
                        if developerTools && home.tool == .eyebrow { BrowDebugMenu().padding(AppSpacing.small).padding(.top, 56) }
                        if developerTools && home.tool == .blush { BlushDebugMenu().padding(AppSpacing.small) }
                    }
                    .overlay(alignment: .bottom) { stylePicker.padding(.bottom, AppSpacing.small) }
            }
            if home.tool == .eyebrow && home.canTry(.eyebrow) && !EyebrowConfiguration.showsBrowTracking {
                BrowStylePicker(styles: home.brow.browStyleChoices, selected: home.brow.configuration.style,
                                onSelect: home.brow.chooseBrowStyle)
            }
            // -Nimah: Old installs may have analysis but no persisted fit; never silently show an empty tool.
            if !home.canTry(home.tool) {
                Text(home.recommendationTitle).font(AppTypography.caption).multilineTextAlignment(.center)
            }
            // Brow: shades and intensity replace the brow pictures inside the camera card (see `stylePicker`).
            if !isBrow { shadeControls }
            continueButton
        }
        // Brow: the camera runs edge to edge; Continue keeps its own side inset.
        .padding(.horizontal, isBrow ? 0 : AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .background {
            if light.isOn { AppColors.ringLight.ignoresSafeArea() }
            else if isBrow { AppColors.browCanvas.ignoresSafeArea() }
            else { MainBackground() }
        }
        .animation(.easeInOut(duration: 0.25), value: showsShades)
        .animation(.easeInOut(duration: 0.25), value: light.isOn)
        .preferredColorScheme(light.isOn ? .light : nil)
        .foregroundStyle(ink)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: light.isOn)
        .sensoryFeedback(.selection, trigger: home.currentShade?.id)
        .sheet(isPresented:$showColours,onDismiss:{ if isVisible { home.activate() } }) {
            PaletteColorPicker(initial:home.currentShade ?? home.swatches[0], source: paletteSource) { home.choose(shade:$0) }
        }
        .onAppear {
            isVisible=true
            light.resume()
            if !showColours { home.activate() }
        }
        .onDisappear { isVisible=false; home.deactivate(); light.turnOff() }
        .onChange(of: scenePhase) { _, phase in
            // Pause the camera off-screen; resume through the same guarded path.
            if phase == .active && isVisible && !showColours { home.activate(); light.resume() } else { home.deactivate(); light.suspend() }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            if developerTools {
                // Developer switch for the entry screens being built (`NewFlow`).
                Button { newFlow.toggle() } label: {
                    Text(verbatim: newFlow ? "New flow: on" : "New flow: off")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .glassCapsule(tint: newFlow ? AppColors.glassSelected : AppColors.glassLight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .frame(maxWidth: 160, maxHeight: 44)
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
                // Long press: developer mode (landmark dots, hand mask) in builds without a toolbar button.
                .onLongPressGesture(minimumDuration: 1.2) { developerTools.toggle() }
                .sensoryFeedback(.impact, trigger: developerTools)
            HStack {
                GlassCircleButton(symbol: "chevron.left", size: 48, tint: AppColors.glassLight, label: "Back to features", action: onBack)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    /// Brow: back (left) and the screen light (right) over the top corners of the camera card.
    private var browTopButtons: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("Back to features")
            Spacer()
            ScreenLightButton(light: light, pulse: 0, plainGlass: true)
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.small)
    }

    /// Full-width pink button under everything, on to the photo of the desired look. A style must be on first.
    private var continueButton: some View {
        Button {
            let handoff = home.tutorialHandoff
            home.deactivate()
            onContinue(handoff)
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.flamingo, in: Capsule())
        }
        .buttonStyle(.plain)
        // Brow: the page has no side padding, so the button keeps its own inset.
        .padding(.horizontal, isBrow ? AppSpacing.medium * 2 : 0)
        .padding(.top, AppSpacing.small)
        .disabled(!home.canTry(home.tool) || home.isOff)
    }

    /// Brow only: opens the shade row and intensity bar; shows an X while they are open.
    private var paletteToggle: some View {
        Button { showsShades.toggle() } label: {
            Image(systemName: showsShades ? "xmark" : "paintpalette")
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsShades ? "Close colours" : "Colours")
    }

    // MARK: Liner look

    /// The six liner looks as pictures, scrolling sideways; the first tile switches the liner off.
    private var linerLookPicker: some View {
        LinerLookPicker(selected: home.isOff ? nil : home.linerLook) { look in
            if let look { home.setLinerLook(look) } else { home.turnOff() }
        }
        .disabled(!home.canTry(.eyeliner))
    }

    /// The look choices of the selected tool, as glass circles over the bottom of the camera card.
    @ViewBuilder private var stylePicker: some View {
        switch home.tool {
        case .eyeliner:
            linerLookPicker
        case .eyebrow where home.canTry(.eyebrow):
            VStack(spacing: AppSpacing.small) {
                paletteToggle
                if showsShades {
                    shadeControls.padding(.horizontal, AppSpacing.small)
                } else {
                    BrowOverlayPicker(overlays: BrowOverlay.all, selected: home.browOverlay, onSelect: home.choose(browOverlay:))
                }
            }
        case .blush:
            BlushLookPicker(selected: home.isOff ? nil : home.blushLook) { look in
                if let look { home.choose(blush: look) } else { home.turnOff() }
            }
            .disabled(!home.canTry(.blush))
        default:
            EmptyView()
        }
    }

    // MARK: Shades

    /// The shade row and intensity bar: under the card for blush and eyeliner, in place of the brow pictures for brows.
    @ViewBuilder private var shadeControls: some View {
        shadeRow.disabled(!home.canTry(home.tool))
        IntensityBar(value: Binding(get: { home.intensity }, set: home.setIntensity),
                     tint: home.currentShade?.color ?? AppColors.flamingo)
            .disabled(!home.canTry(home.tool))
    }

    private func openPalette(_ source: PaletteSource) {
        home.deactivate()
        paletteSource = source
        showColours = true
    }

    private var shadeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { shadeCells(equalWidth: true) }.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) { shadeCells(equalWidth: true) }
            }
        }
        .frame(height: 48)
    }

    @ViewBuilder private func shadeCells(equalWidth: Bool) -> some View {
        ForEach(home.swatches) { shade in
            let selected = shade == home.currentShade
            Button { home.choose(shade: shade) } label: {
                Circle().fill(shade.color)
                    .frame(width: 48, height: 48)
                    .glassCircle(tint: shade.color.opacity(0.55))
                .overlay {
                    if selected {
                        Circle().strokeBorder(AppColors.snow, lineWidth: 2.5)
                        Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(AppColors.snow)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                    }
                }
                .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(shade.name))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        // The plus opens a menu: photograph a product, or pick a photo, then choose its colour in the sheet.
        Menu {
            Button { openPalette(.camera) } label: { Label("Take a Photo", systemImage: "camera") }
            Button { openPalette(.library) } label: { Label("Choose From Photo", systemImage: "photo") }
        } label: {
            Image(systemName: "plus").font(.title2.weight(.medium))
                .foregroundStyle(AppColors.snow)
                .frame(width: 48, height: 48)
                .glassCircle(tint: AppColors.glassLight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a colour from a product")
    }
}

/// A capsule track with a draggable thumb, filled with the current shade up to the thumb. Drag or tap anywhere on the
/// track to set how strong the makeup shows (0.1...1); the value follows the finger while dragging.
private struct IntensityBar: View {
    @Binding var value: Double
    let tint: Color
    @State private var isDragging = false

    private let trackHeight: CGFloat = 20 // design: a full-width fade from soft mauve through the shade to near-black
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbSize, 1)
            let thumbX = thumbSize / 2 + travel * CGFloat(value)
            ZStack(alignment: .leading) {
                // One glass capsule over the fade: no outline, no inner stroke.
                Capsule()
                    .fill(LinearGradient(colors: [AppColors.glassLight.opacity(0.5), tint, Color.black.opacity(0.9)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: trackHeight)
                    .glassCapsule(tint: tint.opacity(0.12), interactive: false)
                // The thumb is glass too and lifts off the track while held.
                Color.clear
                    .frame(width: thumbSize, height: thumbSize)
                    .glassCircle(tint: AppColors.snow.opacity(0.9), interactive: false)
                    .scaleEffect(isDragging ? 1.35 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: isDragging ? 8 : 0, y: isDragging ? 5 : 0)
                    .offset(y: isDragging ? -3 : 0)
                    .position(x: thumbX, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    isDragging = true
                    let fraction = (drag.location.x - thumbSize / 2) / travel
                    value = min(max(Double(fraction), 0), 1)
                }
                .onEnded { _ in isDragging = false })
            .animation(.spring(duration: 0.3, bounce: 0.35), value: isDragging)
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel("Intensity")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
        }
    }
}
