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

    init(plan: MakeupPlan, assessment: FaceShapeAssessment, checker: any FaceTrackingAvailabilityChecking,
         onTutorial: @escaping (TutorialHandoff) -> Void) {
        _home = StateObject(wrappedValue: TryOnHomeModel(plan: plan, assessment: assessment, checker: checker))
        self.onTutorial = onTutorial
    }

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            header
            // -Nimah: Dismantle the face camera while the palette picker owns the rear camera.
            if showColours {
                RoundedRectangle(cornerRadius:AppSpacing.cornerRadius).fill(AppColors.cocoa)
                    .overlay(Text("Choosing makeup colour")).frame(maxHeight:.infinity)
            } else {
                TryOnLiveCard(home: home).frame(maxHeight:.infinity)
                    .overlay(alignment: .topLeading) {
                        if developerTools && home.tool == .eyebrow { BrowDebugMenu().padding(AppSpacing.small) }
                        if developerTools && home.tool == .blush { BlushDebugMenu().padding(AppSpacing.small) }
                    }
            }
            toolStrip
            if home.tool == .eyebrow && home.canTry(.eyebrow) {
                BrowOverlayPicker(overlays: BrowOverlay.all, selected: home.browOverlay, onSelect: home.choose(browOverlay:))
            }
            if home.tool == .eyebrow && home.canTry(.eyebrow) && EyebrowConfiguration.showsBrowTracking {
                browTrackingToggles
            }
            if home.tool == .eyebrow && home.canTry(.eyebrow) && !EyebrowConfiguration.showsBrowTracking {
                BrowStylePicker(styles: home.brow.browStyleChoices, selected: home.brow.configuration.style,
                                onSelect: home.brow.chooseBrowStyle)
            }
            // -Nimah: Never silently show an empty tool.
            if home.tool == .blush {blushPlacementRow}
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
        .background(AppColors.wine.ignoresSafeArea())
        .foregroundStyle(AppColors.snow)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: home.tool)
        .sensoryFeedback(.selection, trigger: home.currentShade?.id)
        .sheet(isPresented:$showColours,onDismiss:{ if isVisible { home.activate() } }) {
            PaletteColorPicker(initial:home.currentShade ?? home.swatches[0]) { home.choose(shade:$0) }
        }
        .onAppear {
            isVisible=true
            if !showColours { home.activate() }
        }
        .onDisappear { isVisible=false; home.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            // Pause the camera off-screen; resume through the same guarded path.
            if phase == .active && isVisible && !showColours { home.activate() } else { home.deactivate() }
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
                Button { home.deactivate(); onTutorial(TutorialHandoff(tool: home.tool,shades: home.shades,intensities: home.intensities,blushStyle:home.blushLook,browOverlay:home.browOverlay,hideNaturalBrow:!home.naturalBrowVisible)) } label: {
                    Image(systemName: "arrow.right")
                        .font(.title2.weight(.medium))
                        .frame(width: 60, height: 60)
                        .background(AppColors.flamingo, in: Circle())
                        .foregroundStyle(AppColors.snow)
                }
                .accessibilityLabel("Open tutorial")
                .disabled(!home.canTry(home.tool))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Tools

    private var toolStrip: some View {
        HStack(spacing: AppSpacing.medium) {
            ForEach(TryOnTool.allCases) { tool in
                let selected = tool == home.tool
                Button { home.choose(tool) } label: {
                    Image(systemName: tool.symbol)
                        .font(.title)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(AppColors.flamingo.opacity(selected ? 0.32 : 0.16),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(AppColors.snow, lineWidth: selected ? 2 : 0)
                        }
                        .foregroundStyle(AppColors.snow)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
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
                .background(AppColors.flamingo.opacity(isOn.wrappedValue ? 0.32 : 0.12), in: Capsule())
                .overlay { Capsule().strokeBorder(AppColors.snow, lineWidth: isOn.wrappedValue ? 1.5 : 0) }
                .foregroundStyle(AppColors.snow.opacity(isOn.wrappedValue ? 1 : 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    // -Nimah: Placement and shade are independent. User requested these three creative alternatives.
    private var blushPlacementRow:some View {
        HStack(spacing:8) {
            ForEach(BlushPlacementStyle.referenceLooks) {look in
                Button {home.choose(blush:look)} label: {
                    Text(look.title).font(.subheadline.weight(.semibold))
                        .frame(maxWidth:.infinity).padding(.vertical,10)
                        .background(home.blushLook==look ? AppColors.flamingo:AppColors.snow.opacity(0.12),in:Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(home.blushLook==look ? .isSelected:[])
            }
        }.disabled(!home.canTry(.blush))
    }

    // MARK: Shades

    private var shadeRow: some View {
        HStack(spacing: AppSpacing.small) {
            circleButton(selected: home.isOff, label: "No makeup", action: home.turnOff) {
                Image(systemName: "nosign").font(.title3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(home.swatches) { shade in
                        let selected = shade == home.currentShade
                        Button { home.choose(shade: shade) } label: {
                            Circle().fill(shade.color)
                                .frame(width: 36, height: 36)
                                .padding(3)
                                .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: selected ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(shade.name))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            // The "+" opens the snap-a-product colour sheet.
            circleButton(selected: false, label: "Add a colour from a product", action: {
                home.deactivate(); showColours = true
            }) {
                Image(systemName: "plus").font(.title2)
            }
        }
        .frame(height: 56)
    }

    private func circleButton<Content: View>(selected: Bool, label: LocalizedStringKey, action: @escaping () -> Void,
                                             @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .frame(width: 52, height: 52)
                .background(AppColors.cocoa, in: Circle())
                .overlay(Circle().strokeBorder(AppColors.snow, lineWidth: selected ? 2 : 0))
                .foregroundStyle(AppColors.snow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A capsule track with a draggable thumb, filled with the current shade up to the thumb. Drag or tap anywhere on the
/// track to set how strong the makeup shows (0.1...1); the value follows the finger while dragging.
private struct IntensityBar: View {
    @Binding var value: Double
    let tint: Color
    @State private var isDragging = false

    private let trackHeight: CGFloat = 14
    private let thumbSize: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbSize, 1)
            let thumbX = thumbSize / 2 + travel * CGFloat(value)
            ZStack(alignment: .leading) {
                Capsule().strokeBorder(AppColors.snow.opacity(0.9), lineWidth: 1)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(LinearGradient(colors: [tint, AppColors.wine], startPoint: .leading, endPoint: .trailing))
                    .frame(width: thumbX, height: trackHeight - 4)
                    .padding(.leading, 2)
                Circle()
                    .fill(AppColors.snow)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().fill(tint).frame(width: thumbSize - 14, height: thumbSize - 14))
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 6 : 3, y: 1)
                    .scaleEffect(isDragging ? 1.15 : 1)
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
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(height: 44)
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
