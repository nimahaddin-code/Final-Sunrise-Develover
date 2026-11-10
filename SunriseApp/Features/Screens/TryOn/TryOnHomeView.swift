import SwiftUI

/// Try On for the one tool picked on the home screen. The camera fills the whole page; back and the screen light sit in
/// the top safe area, and the palette button, the tool's look row (or the shades and intensity bar) and Continue (to the
/// desired-look photo) sit at the bottom over a dark gradient. The tool only supplies its look row and debug menu
/// (`TryOnTool.tryOnFeature`). There is no face or eye scan.
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
    /// The shade row and intensity bar, opened by the palette button over the look row.
    @State private var showsShades = false
    /// The camera card shows a message on the light glow (`TryOnCameraOffKey`): controls go dark-on-light, no gradient.
    @State private var cameraOff = false
    /// Dark labels on the white screen of the light.
    private var ink: Color { light.isOn ? .black : AppColors.plumInk }

    /// One screen per tool: `tool` is the only makeup it shows, with its shape, colour and intensity.
    init(plan: MakeupPlan, assessment: FaceShapeAssessment, checker: any FaceTrackingAvailabilityChecking,
         tool: TryOnTool, onBack: @escaping () -> Void, onContinue: @escaping (TutorialHandoff) -> Void) {
        _home = StateObject(wrappedValue: TryOnHomeModel(tool: tool, plan: plan, assessment: assessment, checker: checker))
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        // Read the top safe area here: the camera ignores it, but its messages must sit under the top buttons.
        GeometryReader { proxy in content(safeTop: proxy.safeAreaInsets.top) }
        .background {
            if light.isOn { AppColors.ringLight.ignoresSafeArea() }
            // Black behind the full-page camera so its rounded corners blend into the screen's.
            else { Color.black.ignoresSafeArea() }
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

    /// The camera fills the whole page; back and light sit in the top safe area; the controls sit over the bottom of it.
    private func content(safeTop: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // -Nimah: Dismantle the face camera while the palette picker owns the rear camera.
            if showColours {
                RoundedRectangle(cornerRadius:AppSpacing.cornerRadius).fill(AppColors.cocoa)
                    .overlay(Text("Choosing makeup colour")).ignoresSafeArea()
            } else {
                TryOnLiveCard(home: home, light: light, showsLightButton: false,
                              captionTopInset: safeTop + Self.topButtonsHeight + AppSpacing.small)
                    .ignoresSafeArea()
                    .onPreferenceChange(TryOnCameraOffKey.self) { value in
                        MainActor.assumeIsolated { cameraOff = value }
                    }
            }
            controlsCard
        }
        .overlay(alignment: .top) { if !showColours { topButtons } }
        .overlay(alignment: .topTrailing) {
            if developerTools && !showColours, let menu = home.tool.tryOnFeature.debugMenu() {
                menu.padding(AppSpacing.small).padding(.top, 56)
            }
        }
    }

    /// Controls pinned to the bottom. The palette button sits on the bare camera; the dark gradient starts just below it
    /// and runs under the home indicator.
    private var controlsCard: some View {
        VStack(spacing: AppSpacing.small) {
            // -Nimah: Old installs may have analysis but no persisted fit; never silently show an empty tool.
            if home.canTry(home.tool) { paletteToggle }
            VStack(spacing: AppSpacing.small) {
                if home.canTry(home.tool) {
                    if showsShades {
                        shadeControls.padding(.horizontal, AppSpacing.medium)
                    } else {
                        home.tool.tryOnFeature.lookPicker(home: home)
                    }
                } else {
                    Text(home.recommendationTitle).font(AppTypography.caption).multilineTextAlignment(.center)
                }
                continueButton
            }
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.small)
            .frame(maxWidth: .infinity)
            .background {
                // One gradient, from clear right under the palette button to dark at the bottom edge. None over the
                // light camera-off page.
                if !cameraOff {
                    LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(cameraOff ? AppColors.plumInk : AppColors.snow)
        .environment(\.colorScheme, cameraOff ? .light : .dark)
    }

    // MARK: Top buttons

    /// Back and light (48 pt) with `AppSpacing.small` around them, from the top of the safe area.
    private static let topButtonsHeight: CGFloat = 48 + AppSpacing.small * 2

    /// Back (left) and the screen light (right) over the top corners of the camera; with developer tools on, the
    /// "New flow" switch sits just below. A long press on back toggles developer mode (landmark dots, hand mask).
    private var topButtons: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack {
                // Not a Button with a simultaneous long press: on iOS 26 that gesture can swallow the tap, so back did
                // nothing. One gesture decides: a 1.2 s hold toggles developer tools, anything shorter goes back.
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(Circle())
                    .gesture(LongPressGesture(minimumDuration: 1.2)
                        .onEnded { _ in developerTools.toggle() }
                        .exclusively(before: TapGesture().onEnded { onBack() }))
                    .accessibilityElement()
                    .accessibilityLabel("Back to features")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onBack() }
                    .sensoryFeedback(.impact, trigger: developerTools)
                Spacer()
                if home.canTry(home.tool) { styleNamePill }
                Spacer()
                ScreenLightButton(light: light, pulse: 0, plainGlass: true)
            }
            if developerTools {
                // Developer switch for the entry screens being built (`NewFlow`).
                Button { newFlow.toggle() } label: {
                    Text(verbatim: newFlow ? "New flow: on" : "New flow: off")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .glassCapsule(tint: newFlow ? AppColors.glassSelected : AppColors.glassLight)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(AppSpacing.small)
    }

    /// The chosen look's name between back and the light: the same Liquid Glass as they have, as a capsule.
    private var styleNamePill: some View {
        home.tool.tryOnFeature.styleName(home: home)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, AppSpacing.medium)
            .frame(height: 48)
            .glassEffect(.regular, in: .capsule)
            .accessibilityAddTraits(.isHeader)
    }

    /// Full-width button at the bottom, on to the photo of the desired look. A style must be on first.
    private var continueButton: some View {
        Button {
            let handoff = home.tutorialHandoff
            home.deactivate()
            onContinue(handoff)
        } label: {
            // Disabled looked exactly like enabled, so a tap with no look chosen seemed to do nothing: it now says why.
            Text(canContinue ? "Continue" : "Pick a look to continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(canContinue ? 1 : 0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                // System glass tinted with the homepage's dark button colour, so it follows the Liquid Glass setting.
                .glassEffect(.regular.tint(AppColors.buttonInk.opacity(canContinue ? 1 : 0.5)).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        // The page has no side padding, so the button keeps its own inset.
        .padding(.horizontal, AppSpacing.medium)
        .padding(.top, AppSpacing.small)
        .disabled(!canContinue)
    }

    private var canContinue: Bool { home.canTry(home.tool) && !home.isOff }

    /// Opens the shade row and intensity bar; shows an X while they are open.
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

    // MARK: Shades

    /// The shade row and intensity bar, in place of the look row while the palette button is open.
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

    private let trackHeight: CGFloat = 20 // a full-width fade from the shade, faint, to the shade at full strength
    private let thumbSize: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbSize, 1)
            let thumbX = thumbSize / 2 + travel * CGFloat(value)
            ZStack(alignment: .leading) {
                // One glass capsule over the fade: no outline, no inner stroke.
                Capsule()
                    // Faint to full shade: the right end is the picked colour at full strength (was near-black for every shade).
                    .fill(LinearGradient(colors: [tint.opacity(0.15), tint],
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
