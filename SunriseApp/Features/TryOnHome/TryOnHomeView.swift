import SwiftUI
import Combine
// -Nimah: Saved scan outputs select the single assigned style on the shared camera.

/// The app's first screen once onboarding is done: header, live camera card, the three tools, a shade row and an
/// intensity bar. The arrow opens the tutorial, the profile button the profile page.
struct TryOnHomeView: View {
    @StateObject private var home: TryOnHomeModel
    var onProfile: () -> Void
    var onTutorial: (TryOnTool,MakeupShade?,Double) -> Void
    @ObservedObject private var store: FaceShapeStore
    @AppStorage(DeveloperTools.key) private var developerTools = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible=false
    @State private var showColours=false

    init(store: FaceShapeStore, assessment: FaceShapeAssessment?, checker: any FaceTrackingAvailabilityChecking,
         onProfile: @escaping () -> Void, onTutorial: @escaping (TryOnTool,MakeupShade?,Double) -> Void) {
        let plan = store.latest.map { MakeupPlan(scan: $0, eyeScan: store.eyes) } ?? MakeupPlan(shape: .oval, eyeScan: store.eyes)
        _home = StateObject(wrappedValue: TryOnHomeModel(plan: plan, assessment: assessment ?? FaceShapeAssessment(shape: .unknown),
                                                         checker: checker))
        self.store = store
        self.onProfile = onProfile
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
            }
            toolStrip
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
        .onReceive(store.$latest.combineLatest(store.$eyes)) { face,eyes in
            home.updateRecommendations(face:face,eyes:eyes)
        }
        .sheet(isPresented:$showColours,onDismiss:{ if isVisible { home.activate() } }) {
            PaletteColorPicker(initial:home.currentShade ?? home.swatches[0]) { home.choose(shade:$0) }
        }
        .onAppear { isVisible=true; if !showColours { home.activate() } }
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
                Button(action: onProfile) {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .background(AppColors.snow.opacity(0.35), in: Circle())
                        .foregroundStyle(AppColors.wine)
                }
                .accessibilityLabel("Profile")
                Spacer()
                Button { onTutorial(home.tool,home.shades[home.tool],home.intensity) } label: {
                    Image(systemName: "arrow.right")
                        .font(.title2.weight(.medium))
                        .frame(width: 60, height: 60)
                        .background(AppColors.flamingo, in: Circle())
                        .foregroundStyle(AppColors.snow)
                }
                .accessibilityLabel("Open tutorial")
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
            let thumbX = thumbSize / 2 + travel * CGFloat((value - 0.1) / 0.9)
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
                    value = 0.1 + 0.9 * min(max(Double(fraction), 0), 1)
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
            case .decrement: value = max(value - 0.1, 0.1)
            @unknown default: break
            }
        }
    }
}
