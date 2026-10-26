import SwiftUI

/// A developer tab for correcting the face and eye outlines by hand. It runs the same scanners as onboarding (`FaceShapeView`,
/// `EyeScanView`); when a scan finishes, the points that scan drew become the raw points. You drag them where they belong, and
/// Confirm saves the raw and the corrected points as two separate files. Only coordinates are saved, never the picture.
/// The scans' own results are written to a throwaway store, so the real face and eye results are not changed.
struct ScanDebugView: View {
    @StateObject private var model: ScanDebugViewModel
    @StateObject private var scratchStore = FaceShapeStore()
    @State private var isScanning = false
    @State private var isZoomed = false
    @State private var pendingSnapshot: ScanSnapshot?

    init(store: ScanDebugStore = ScanDebugStore()) {
        _model = StateObject(wrappedValue: ScanDebugViewModel(store: store))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Picker("Outline", selection: $model.kind) {
                    ForEach(ScanDebugKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                scanButton
                if let message = model.message {
                    Text(message).font(AppTypography.caption).foregroundStyle(.red)
                }
                if model.session != nil {
                    preview
                    Toggle("Show landmark points and indices", isOn: $model.showIndices).tint(AppColors.rose)
                    stagePicker
                    measurementTable
                    exportRow
                    if model.stage == .corrected { correctionHint }
                    if model.stage == .final { saveSection }
                } else {
                    Text("Scan your \(model.kind.title.lowercased()) to get the raw points to correct.")
                        .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                }
                scansSection
                savedSection
                Text("Debug tool. Points come from the app's own face and eye scans. Only point coordinates are saved on this device; the scan picture is never stored or uploaded.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            }
            .padding(AppSpacing.medium)
        }
        .background(AppColors.background)
        .navigationTitle("Scan Debug")
        .fullScreenCover(isPresented: $isScanning) { scanner }
        .fullScreenCover(isPresented: $isZoomed) { ScanDebugZoomView(model: model) }
        .onChange(of: model.kind) { _, _ in model.stage = .raw }
    }

    private var scanButton: some View {
        Button { isScanning = true } label: {
            Label(model.session == nil ? "Scan \(model.kind.title.lowercased())" : "Scan \(model.kind.title.lowercased()) again",
                  systemImage: model.kind == .face ? "faceid" : "eye")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered).tint(AppColors.rose)
    }

    /// The same screens onboarding shows. "Use this scan" on the result keeps the scan's points.
    private var scanner: some View {
        NavigationStack {
            Group {
                if model.kind == .face {
                    FaceShapeView(store: scratchStore, onShowMakeup: useScan, continueTitle: "Use this scan", onResult: { pendingSnapshot = $0 })
                } else {
                    EyeScanView(store: scratchStore, continueTitle: "Use this scan", onFinish: useScan, onResult: { pendingSnapshot = $0 })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isScanning = false } }
            }
        }
    }

    private func useScan() {
        model.accept(pendingSnapshot, kind: model.kind)
        pendingSnapshot = nil
        isScanning = false
    }

    // MARK: Preview with draggable points

    private var preview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("\(model.kind.title) contour preview").font(.headline)
            ScanDebugCanvas(model: model)
                .overlay(alignment: .topTrailing) {
                    Button { model.stage = .corrected; model.beginEditing(); isZoomed = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .padding(10).background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white)
                    }
                    .padding(AppSpacing.small)
                    .accessibilityLabel("Open full screen to zoom and correct")
                }
        }
    }

    // MARK: Stage and measurements

    private var stagePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Measurement stage").font(.headline)
            Picker("Measurement stage", selection: $model.stage) {
                ForEach(ScanDebugStage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var measurementTable: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(row.value).monospacedDigit()
                        if let change = row.change {
                            Text("vs raw \(change)").font(AppTypography.caption).foregroundStyle(AppColors.subtle).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, AppSpacing.small)
                Divider()
            }
        }
    }

    /// Shares this scan with the Mac editor: the picture and the points, as one file, only when this is tapped.
    @ViewBuilder private var exportRow: some View {
        if let item = model.exportItem() {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ShareLink(item: item, preview: SharePreview(item.fileName)) {
                    Label("Export for Mac", systemImage: "square.and.arrow.up").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(AppColors.rose)
                Text("Sends the scan picture and its points, with your corrections so far, as one file (AirDrop works). The picture leaves the app only when you do this.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            }
        }
    }

    /// Every scan held this session. They live in memory only; this is where they can be exported together.
    @ViewBuilder private var scansSection: some View {
        if !model.allScans.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Scans this session").font(.headline)
                ShareLink(items: model.exportItems, preview: { SharePreview($0.fileName) }) {
                    Label("Export all \(model.allScans.count) for Mac", systemImage: "square.and.arrow.up.on.square")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(AppColors.rose)
                Text("Scans are kept in memory until you close the app. A new scan of the same outline does not replace the old one here.")
                    .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                ForEach(model.allScans) { scan in
                    let editing = model.sessions[scan.raw.kind]?.id == scan.id
                    HStack {
                        Image(systemName: scan.raw.kind == .face ? "faceid" : "eye")
                        VStack(alignment: .leading) {
                            Text("\(scan.raw.kind.rawValue)-\(scan.name)").font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                            Text(editing ? "Editing" : scan.takenAt.formatted(date: .omitted, time: .standard))
                                .font(AppTypography.caption).foregroundStyle(editing ? AppColors.rose : AppColors.subtle)
                        }
                        Spacer()
                        if !editing { Button("Edit") { model.activate(scan.id) } }
                        ShareLink(item: model.exportItem(for: scan), preview: SharePreview(model.exportItem(for: scan).fileName)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { model.remove(scan.id) } label: { Image(systemName: "trash") }
                    }
                    .buttonStyle(.borderless)
                    Divider()
                }
            }
        }
    }

    private var correctionHint: some View {
        HStack {
            Text("Drag the points to fix the outline.").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            Spacer()
            Button("Undo") { model.undo() }.disabled(!model.canUndo)
            Button("Reset to raw") { model.resetCorrection() }.disabled(!model.isCorrected)
                .padding(.leading, AppSpacing.small)
        }
    }

    // MARK: Save

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Save correction").font(.headline)
            TextField("Name (optional)", text: $model.saveName)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(model.isCorrected ? "Saves two files: the raw points and the corrected points."
                 : "Nothing was moved yet. Saving still stores both files, with identical points.")
                .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            PrimaryButton(title: "Confirm correction") { model.confirm() }
            if !model.savedFiles.isEmpty {
                ForEach(model.savedFiles, id: \.self) { name in
                    Label(name, systemImage: "checkmark.circle.fill").font(AppTypography.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private var savedSection: some View { SavedFilesView(store: model.store) }
}

/// Lists the saved files; watches the store itself because the model only holds a reference to it.
private struct SavedFilesView: View {
    @ObservedObject var store: ScanDebugStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Saved files").font(.headline)
            if store.items.count > 1 {
                ShareLink(items: store.items.map(\.url)) {
                    Label("Share all \(store.items.count) saved point files (no pictures)", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered).tint(AppColors.rose)
            }
            if store.items.isEmpty {
                Text("Nothing saved yet.").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            }
            ForEach(store.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.record.id).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(item.record.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                    }
                    Spacer()
                    ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { store.delete(item) } label: { Image(systemName: "trash") }
                        .padding(.leading, AppSpacing.small)
                }
                .buttonStyle(.borderless)
                Divider()
            }
        }
    }
}

/// The scan picture with its lines and the points on top. In the Corrected stage the points drag; otherwise they are shown
/// only when indices are on. Sizes itself to the width it is given, so a wider frame zooms it.
private struct ScanDebugCanvas: View {
    @ObservedObject var model: ScanDebugViewModel

    var body: some View {
        if let snapshot = model.snapshot {
            ScanOverlayView(snapshot: snapshot).overlay { pointLayer }
        }
    }

    private var pointLayer: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(model.shownSet?.points ?? []) { point in
                    handle(for: point, at: CGPoint(x: point.x * proxy.size.width, y: point.y * proxy.size.height), in: proxy.size)
                }
            }
            .coordinateSpace(name: "preview")
        }
    }

    @ViewBuilder
    private func handle(for point: ScanDebugPoint, at position: CGPoint, in size: CGSize) -> some View {
        let editable = model.stage == .corrected
        if editable || model.showIndices {
            ZStack {
                Circle().fill(editable ? AppColors.rose : Color.white).frame(width: editable ? 14 : 8, height: editable ? 14 : 8)
                    .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
                if model.showIndices {
                    Text("\(point.index)").font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(.black.opacity(0.6), in: Capsule()).offset(x: 12, y: -12)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(position)
            .allowsHitTesting(editable)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("preview")).onChanged { drag in
                model.move(point.id, toShown: CGPoint(x: drag.location.x / size.width, y: drag.location.y / size.height))
            }.onEnded { _ in model.endEdit() })
            .accessibilityLabel("Point \(point.index), \(point.id)")
        }
    }
}

/// Full-screen correction: the same canvas, zoomable with pinch or the buttons and scrollable when zoomed in. Points are
/// the same size at every zoom, so zooming in makes small moves easier.
private struct ScanDebugZoomView: View {
    @ObservedObject var model: ScanDebugViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    private let range: ClosedRange<CGFloat> = 1...8

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ScanDebugCanvas(model: model).frame(width: proxy.size.width * zoom)
                }
                .scrollIndicators(.visible)
                .simultaneousGesture(MagnifyGesture().onChanged { value in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    zoom = min(max(start * value.magnification, range.lowerBound), range.upperBound)
                }.onEnded { _ in pinchStart = nil })
            }
            .background(Color.black)
            .navigationTitle("\(model.kind.title) correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.cancelEditing(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { zoom = max(range.lowerBound, zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Zoom out")
                    Text("\(zoom, format: .number.precision(.fractionLength(1)))×").monospacedDigit()
                    Button { zoom = min(range.upperBound, zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoom in")
                    Spacer()
                    Picker("Stage", selection: $model.stage) {
                        Text("Raw").tag(ScanDebugStage.raw)
                        Text("Corrected").tag(ScanDebugStage.corrected)
                    }
                    .pickerStyle(.segmented).frame(width: 190)
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!model.canUndo).accessibilityLabel("Undo")
                    Button("Reset") { model.resetCorrection() }.disabled(!model.isCorrected)
                }
            }
        }
        .preferredColorScheme(.dark)
        // Eyes are a wide, thin strip, so they get the long side of the screen.
        .onAppear { if model.kind == .eyes { ScreenOrientation.lock(to: .landscape) } }
        .onDisappear { ScreenOrientation.lock(to: .portrait) }
    }
}
