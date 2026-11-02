import SwiftUI

/// The app's first screen: header, live camera card, the three tools, a shade row and an intensity bar.
/// The arrow opens the tutorial. Every tool uses the standard look; there is no face or eye scan.
struct TryOnHomeView: View {
    @StateObject private var home: TryOnHomeModel
    var onTutorial: (TutorialHandoff) -> Void
    @AppStorage(DeveloperTools.key) private var developerTools = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible=false
    @State private var showColours=false
    @State private var paletteSource = PaletteSource.camera
    @StateObject private var light = ScreenLight()
    @Namespace private var toolGlass

    init(plan: MakeupPlan, assessment: FaceShapeAssessment, checker: any FaceTrackingAvailabilityChecking,
         onTutorial: @escaping (TutorialHandoff) -> Void) {
        _home = StateObject(wrappedValue: TryOnHomeModel(plan: plan, assessment: assessment, checker: checker))
        self.onTutorial = onTutorial
    }

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            header
            // -Nimah: Dismantle the face camera while the palette picker owns the rear camera.
            if showColours {
                RoundedRectangle(cornerRadius:AppSpacing.cornerRadius).fill(AppColors.cocoa)
                    .overlay(Text("Choosing makeup colour")).frame(maxHeight:.infinity)
            } else {
                TryOnLiveCard(home: home).frame(maxHeight:.infinity)
                    .overlay { ScreenLightGlow(light: light) }
                    .overlay(alignment: .topLeading) {
                        Button { light.toggle() } label: {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(light.isOn ? ScreenLight.glow : AppColors.snow)
                                .frame(width: 44, height: 44)
                                .glassCircle(tint: light.isOn ? ScreenLight.glow.opacity(0.3) : AppColors.snow.opacity(0.18))
                        }
                        .buttonStyle(.plain)
                        .padding(AppSpacing.small)
                        .accessibilityLabel("Light")
                        .accessibilityValue(light.isOn ? Text("On") : Text("Off"))
                    }
                    .overlay(alignment: .topTrailing) {
                        if developerTools && home.tool == .eyebrow { BrowDebugMenu().padding(AppSpacing.small) }
                        if developerTools && home.tool == .blush { BlushDebugMenu().padding(AppSpacing.small) }
                    }
                    .overlay(alignment: .bottom) { stylePicker.padding(.bottom, AppSpacing.small) }
            }
            toolStrip
            if home.tool == .eyebrow && home.canTry(.eyebrow) && EyebrowConfiguration.showsBrowTracking {
                browTrackingToggles
            }
            if home.tool == .eyebrow && home.canTry(.eyebrow) && !EyebrowConfiguration.showsBrowTracking {
                BrowStylePicker(styles: home.brow.browStyleChoices, selected: home.brow.configuration.style,
                                onSelect: home.brow.chooseBrowStyle)
            }
            // -Nimah: Old installs may have analysis but no persisted fit; never silently show an empty tool.
            if !home.canTry(home.tool) {
                Text(home.recommendationTitle).font(AppTypography.caption).multilineTextAlignment(.center)
            }
            shadeRow.disabled(!home.canTry(home.tool))
            IntensityBar(value: Binding(get: { home.intensity }, set: home.setIntensity),
                         tint: home.currentShade?.color ?? AppColors.flamingo)
                .disabled(!home.canTry(home.tool))
        }
        .padding(.horizontal, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .background { MainBackground() }
        .foregroundStyle(AppColors.snow)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: home.tool)
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
            Image("logo-burgundy")
                .resizable().scaledToFit()
                .frame(maxWidth: 160, maxHeight: 44)
                .accessibilityLabel("dandan")
                .accessibilityAddTraits(.isHeader)
                // Long press: developer mode (landmark dots, hand mask) in builds without a toolbar button.
                .onLongPressGesture(minimumDuration: 1.2) { developerTools.toggle() }
                .sensoryFeedback(.impact, trigger: developerTools)
            HStack {
                Spacer()
                GlassCircleButton(symbol: "arrow.right", size: 48, tint: AppColors.flamingo.opacity(0.9), label: "Open tutorial") {
                    home.deactivate()
                    onTutorial(TutorialHandoff(tool: home.tool,shades: home.shades,intensities: home.intensities,linerLook: home.linerLook,blushStyle:home.blushLook,browOverlay:home.browOverlay,hideNaturalBrow:!home.naturalBrowVisible))
                }
                .disabled(!home.canTry(home.tool))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Tools

    /// The three tools as text; the chosen one sits on a glass capsule that slides to the next one.
    private var toolStrip: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(TryOnTool.allCases) { tool in
                    let selected = tool == home.tool
                    Button { withAnimation(.smooth(duration: 0.3)) { home.choose(tool) } } label: {
                        Text(tool.title)
                            .font(.system(size: 18, weight: selected ? .semibold : .regular))
                            .foregroundStyle(AppColors.snow.opacity(selected ? 1 : 0.6))
                            .padding(.horizontal, 18)
                            .frame(minHeight: 42)
                            .modifier(SelectedToolGlass(selected: selected, namespace: toolGlass))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Test toggles under the eyebrow tool for the MediaPipe tracking view.
    private var browTrackingToggles: some View {
        HStack(spacing: AppSpacing.small) {
            Spacer()
            trackingToggle("Landmarks", symbol: "circle.grid.3x3", isOn: $home.browLandmarksVisible)
            trackingToggle("Natural brow", symbol: "eyebrow", isOn: $home.naturalBrowVisible)
        }
    }

    private func trackingToggle(_ title: LocalizedStringKey, symbol: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: symbol)
                .font(AppTypography.caption.weight(.semibold))
                .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                .glassCapsule(tint: isOn.wrappedValue ? AppColors.glassSelected : nil)
                .foregroundStyle(AppColors.snow.opacity(isOn.wrappedValue ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
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
            BrowOverlayPicker(overlays: BrowOverlay.all, selected: home.browOverlay, onSelect: home.choose(browOverlay:))
        case .blush:
            blushPlacementRow
        default:
            EmptyView()
        }
    }

    // -Nimah: Placement and shade are independent. User requested these three creative alternatives.
    private var blushPlacementRow: some View {
        GlassPickerRow(title: home.isOff ? Text("None") : Text(home.blushLook.title),
                       selectedID: home.isOff ? "none" : "\(home.blushLook.id)", onCenter: { id in
            if let look = BlushPlacementStyle.referenceLooks.first(where: { $0.id == id }) { home.choose(blush: look) } else { home.turnOff() }
        }) {
            Button { home.turnOff() } label: {
                StyleCircle(selected: home.isOff, isNone: true) { EmptyView() }
            }
            .buttonStyle(.plain).id("none").accessibilityLabel("No makeup")
            ForEach(BlushPlacementStyle.referenceLooks) { look in
                let selected = !home.isOff && home.blushLook == look
                Button { home.choose(blush: look) } label: {
                    StyleCircle(selected: selected) { BlushStyleIcon(look: look) }
                }
                .buttonStyle(.plain)
                .id("\(look.id)")
                .accessibilityLabel(look.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .disabled(!home.canTry(.blush))
    }

    // MARK: Shades

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
                .overlay { if selected { Circle().strokeBorder(AppColors.snow, lineWidth: 2.5) } }
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

/// The chosen tool's glass capsule. Every tool gets the same id, so changing the choice slides one capsule across.
private struct SelectedToolGlass: ViewModifier {
    let selected: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if selected {
            content
                .glassCapsule(tint: AppColors.glassSelected)
                .glassEffectID("selected-tool", in: namespace)
        } else {
            content
        }
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
