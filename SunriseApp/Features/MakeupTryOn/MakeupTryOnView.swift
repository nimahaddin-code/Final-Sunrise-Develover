import SwiftUI
import UIKit

// -Nimah: This live screen is eyeliner-only; eyebrow/blush use Nimah studio.
struct MakeupTryOnView: View {
    @StateObject private var model: MakeupTryOnViewModel
    @State private var category: MakeupCategory
    @State private var isComparing = false
    @State private var controlsHidden = false
    @State private var snapshotter = ARSnapshotter()
    @State private var photo: TryOnPhoto?
    @AppStorage(DeveloperTools.key) private var developerTools = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(plan: MakeupPlan, applied: [MakeupRecommendation]) {
        _model = StateObject(wrappedValue: MakeupTryOnViewModel(plan: plan, applied: applied))
        _category = State(initialValue: .eyeliner)
    }

    var body: some View {
        content
            .background(AppColors.background)
            .foregroundStyle(AppColors.ink)
            .navigationTitle("Live Try-On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if model.phase == .ready {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        #if DEBUG
                        // Developer mode: landmark dots, hand mask, lid tracking switch and the eye readout.
                        Button("Developer mode", systemImage: developerTools ? "ladybug.fill" : "ladybug") {
                            developerTools.toggle()
                        }
                        #endif
                        Button("Place again", systemImage: "arrow.triangle.2.circlepath", action: model.relocate)
                        Button("Take photo", systemImage: "camera") {
                            if let image = snapshotter.snapshot() {
                                photo = TryOnPhoto(image: model.linerOverlay.composed(image))
                            }
                        }
                    }
                }
            }
            .sheet(item: $photo) { photo in
                TryOnPhotoView(photo: photo)
                    .presentationDragIndicator(.visible)
            }
            .sensoryFeedback(.selection, trigger: model.selection)
            .sensoryFeedback(.selection, trigger: model.shadeChoices)
            .sensoryFeedback(.success, trigger: model.phase == .ready) { _, ready in ready }
            .task { await model.startIfNeeded() }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { _, newPhase in
                // -Nimah: Pause all camera/model work off-screen; resume through one guarded lifecycle.
                if newPhase == .active { Task { await model.startIfNeeded() } }
                else { model.stop() }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            ProgressView("Starting camera")
        case .locating, .ready, .interrupted:
            // One branch so the camera view keeps its identity while placement changes.
            tryOn
        case .unsupported:
            ContentUnavailableView("Live try-on unavailable", systemImage: "faceid",
                description: Text("Live try-on needs an iPhone with a TrueDepth front camera."))
        case .cameraDenied:
            ContentUnavailableView {
                Label("Camera access needed", systemImage: "camera")
            } description: {
                Text("Allow camera access in Settings to try on makeup. Nothing is saved or uploaded.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        case .failed:
            ContentUnavailableView {
                Label("Camera stopped", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Face tracking stopped unexpectedly.")
            } actions: {
                Button("Try again") { Task { await model.start() } }
            }
        }
    }

    private var tryOn: some View {
        ZStack {
            MakeupARView(session: model.session, layers: model.layers, showsMakeup: !isComparing,
                         snapshotter: snapshotter)
                .ignoresSafeArea()
            LinerOverlayView(model: model.linerOverlay, isVisible: !isComparing)
                .ignoresSafeArea()
            VStack {
                if let status {
                    Text(status).font(AppTypography.body).multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                        .background(AppColors.card, in: Capsule())
                        .padding(.top, AppSpacing.medium)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Spacer()
                if model.phase == .ready, model.hasMakeup {
                    compareButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, AppSpacing.medium)
                }
                panelToggle
                if !controlsHidden { controls }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .animation(.easeInOut(duration: 0.2), value: controlsHidden)
    }

    /// Folds the controls away to see the whole face.
    private var panelToggle: some View {
        Button { controlsHidden.toggle() } label: {
            Image(systemName: controlsHidden ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 28)
                .background(AppColors.card, in: Capsule())
                .foregroundStyle(AppColors.ink)
        }
        .buttonStyle(.plain)
        .padding(.bottom, controlsHidden ? AppSpacing.medium : 0)
        .accessibilityLabel(controlsHidden ? "Show controls" : "Hide controls")
    }

    private var status: LocalizedStringKey? {
        switch model.phase {
        case .locating(.findFace): "Position your face in the frame"
        case .locating(.lookStraight): "Look straight at the camera"
        case .locating(.holdStill): "Hold still, placing makeup…"
        case .interrupted: "Camera paused. Try-on resumes when the camera is available."
        default: nil
        }
    }

    /// Hold to see the bare face; VoiceOver users toggle it instead.
    private var compareButton: some View {
        VStack(spacing: 4) {
            Image(systemName: isComparing ? "eye.slash.fill" : "circle.lefthalf.filled")
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(isComparing ? AppColors.rose : AppColors.card, in: Circle())
                .foregroundStyle(isComparing ? Color.white : AppColors.ink)
            Text(isComparing ? "Without makeup" : "Hold to compare")
                .font(AppTypography.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.small).padding(.vertical, 2)
                .background(AppColors.card.opacity(0.9), in: Capsule())
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 60,
                            perform: {}, onPressingChanged: { isComparing = $0 })
        .sensoryFeedback(.impact(weight: .light), trigger: isComparing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compare without makeup")
        .accessibilityValue(isComparing ? Text("Makeup hidden") : Text("Makeup shown"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isComparing.toggle() }
    }

    private var controls: some View {
        let items = model.recommendations(in: category)
        let selected = model.selection[category]
        return VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Picker("Makeup", selection: $category) {
                ForEach([MakeupCategory.eyeliner]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    chip(isSelected: selected == nil) { model.select(nil, in: category) } label: {
                        Label("None", systemImage: "nosign")
                    }
                    ForEach(items) { item in
                        chip(isSelected: selected == item) { model.select(item, in: category) } label: {
                            HStack(spacing: AppSpacing.small) {
                                if MakeupPlan.isMadeForYou(item) {
                                    Image(systemName: "sparkles").font(.caption).accessibilityHidden(true)
                                }
                                Text(item.name)
                            }
                        }
                    }
                }
            }
            if selected != nil {
                shadePicker
                intensitySlider
            }
            Group {
                if let selected {
                    Text(selected.detail)
                } else {
                    Text(model.plan.reason(for: category))
                }
            }
            .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            .fixedSize(horizontal: false, vertical: true)
            // Long press: developer mode in builds without the toolbar button (Release, TestFlight).
            .onLongPressGesture(minimumDuration: 1.2) { developerTools.toggle() }
            .sensoryFeedback(.impact, trigger: developerTools)
            if category == .eyeliner, DeveloperTools.isOn(developerTools) {
                ScrollView { EyeDebugView(eyes: model.plan.eyes, overlay: model.linerOverlay) }
                    .frame(maxHeight: 150)
            }
            if let selected, let notes = notes(for: category, selected: selected), !notes.isEmpty {
                fitNotes(notes)
            }
        }
        .padding(AppSpacing.medium)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
        .padding(AppSpacing.medium)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    /// Why the selected style looks the way it does on this face. The eyeliner's reasons come from the face scan.
    private func notes(for category: MakeupCategory, selected: MakeupRecommendation) -> [LocalizedStringResource]? {
        if category == .eyeliner {
            return MakeupPlan.isMadeForYou(selected) ? model.plan.eyeliner.notes : nil
        }
        return model.fit?.notes(for: category)
    }

    /// How the selected style was fitted to this face.
    private func fitNotes(_ notes: [LocalizedStringResource]) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fitted to your features").font(AppTypography.caption.weight(.semibold))
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(AppTypography.caption)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles").foregroundStyle(AppColors.rose)
        }
        .padding(AppSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.rose.opacity(0.08), in: RoundedRectangle(cornerRadius: AppSpacing.small + 4))
        .accessibilityElement(children: .combine)
    }

    private var shadePicker: some View {
        let current = model.shade(for: category)
        return HStack(spacing: AppSpacing.medium) {
            Text("Shade").font(AppTypography.caption.weight(.semibold))
            ForEach(MakeupPalette.shades(for: category)) { shade in
                Button { model.select(shade, in: category) } label: {
                    ShadeDot(shade: shade)
                        .frame(width: 28, height: 28)
                        .padding(3)
                        .overlay(Circle().strokeBorder(shade == current ? AppColors.rose : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(shade.name))
                .accessibilityAddTraits(shade == current ? .isSelected : [])
            }
            Spacer(minLength: 0)
            if let current {
                Text(current.name).font(AppTypography.caption).foregroundStyle(AppColors.subtle).lineLimit(1)
            }
        }
    }

    private var intensitySlider: some View {
        let intensity = Binding(get: { model.intensity(for: category) },
                                set: { model.setIntensity($0, for: category) })
        return HStack(spacing: AppSpacing.small) {
            Image(systemName: "drop").font(.caption).accessibilityHidden(true)
            Slider(value: intensity, in: 0.1...1) { Text("Intensity") }
                .tint(AppColors.rose)
            Image(systemName: "drop.fill").accessibilityHidden(true)
        }
    }

    private func chip<Content: View>(isSelected: Bool, action: @escaping () -> Void,
                                     @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, AppSpacing.medium).padding(.vertical, AppSpacing.small)
                .background(isSelected ? AppColors.rose : AppColors.background, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : AppColors.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct TryOnPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Shows a captured try-on photo; sharing it also offers saving to Photos.
private struct TryOnPhotoView: View {
    let photo: TryOnPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: photo.image)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                .padding(AppSpacing.large)
                .accessibilityLabel("Try-on photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background)
                .navigationTitle("Your look")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        let image = Image(uiImage: photo.image)
                        ShareLink(item: image, preview: SharePreview("Try-on photo", image: image))
                    }
                }
        }
    }
}

#Preview {
    NavigationStack {
        let plan = MakeupPlan(shape: .round)
        MakeupTryOnView(plan: plan, applied: plan.madeForYou)
    }
}
