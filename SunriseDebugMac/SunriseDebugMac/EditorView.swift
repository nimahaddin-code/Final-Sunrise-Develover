import AppKit
import SwiftUI

/// Correct one scan: the picture and its points on the left (zoom, scroll, drag, nudge with the arrow keys), the measurements
/// and the save step on the right.
struct EditorView: View {
    let item: ScanLibrary.Item
    @ObservedObject var model: ScanDebugViewModel
    @ObservedObject var library: ScanLibrary
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    @State private var selected: String?
    @FocusState private var canvasFocused: Bool
    private let range: ClosedRange<CGFloat> = 1...12

    var body: some View {
        HSplitView {
            canvas.frame(minWidth: 420)
            inspector.frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .toolbar { toolbar }
        .navigationSubtitle(item.file.kind.title)
    }

    // MARK: Canvas

    private var aspect: CGFloat {
        guard let picture = model.session?.picture else { return 1 }
        return CGFloat(picture.width) / CGFloat(max(picture.height, 1))
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let fit = max(1, min(proxy.size.width - 16, (proxy.size.height - 16) * aspect))
            ScrollView([.horizontal, .vertical]) {
                EditorCanvas(model: model, selected: $selected, onTouch: { canvasFocused = true })
                    .frame(width: fit * zoom)
                    .padding(8)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                let start = pinchStart ?? zoom
                pinchStart = start
                zoom = min(max(start * value.magnification, range.lowerBound), range.upperBound)
            }.onEnded { _ in pinchStart = nil })
        }
        .background(Color.black.opacity(0.85))
        .focusable()
        .focused($canvasFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            nudge(press.key, big: press.modifiers.contains(.shift))
        }
    }

    /// Moves the selected point by one photo pixel (ten with Shift).
    private func nudge(_ key: KeyEquivalent, big: Bool) -> KeyPress.Result {
        guard model.stage == .corrected, let id = selected, let set = model.shownSet, let point = set.points.first(where: { $0.id == id })
        else { return .ignored }
        let step = big ? 10.0 : 1.0
        var x = point.x, y = point.y
        switch key {
        case .leftArrow: x -= step / Double(set.imageWidth)
        case .rightArrow: x += step / Double(set.imageWidth)
        case .upArrow: y -= step / Double(set.imageHeight)
        default: y += step / Double(set.imageHeight)
        }
        model.move(id, toShown: CGPoint(x: x, y: y))
        model.endEdit()
        return .handled
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z").disabled(!model.canUndo)
            Button { model.resetCorrection() } label: { Label("Reset to raw", systemImage: "arrow.counterclockwise") }
                .disabled(!model.isCorrected)
            Button { model.cancelEditing(); model.beginEditing() } label: { Label("Revert to opened", systemImage: "arrow.uturn.backward.circle") }
        }
        ToolbarItemGroup {
            Button { zoom = max(range.lowerBound, zoom / 1.5) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
                .keyboardShortcut("-")
            Text("\(zoom, format: .number.precision(.fractionLength(1)))×").monospacedDigit().frame(minWidth: 40)
            Button { zoom = min(range.upperBound, zoom * 1.5) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
                .keyboardShortcut("=")
            Button { zoom = 1 } label: { Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                .keyboardShortcut("0")
        }
    }

    // MARK: Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Measurement stage", selection: $model.stage) {
                    ForEach(ScanDebugStage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Toggle("Show landmark points and indices", isOn: $model.showIndices)
                if model.stage == .corrected {
                    Text("Drag a point, or click it and use the arrow keys (Shift = 10 px). ⌘Z undoes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                table
                if model.stage == .final { save }
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.red) }
                saved
            }
            .padding()
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(row.value).monospacedDigit()
                        if let change = row.change { Text("vs raw \(change)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private var save: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save correction").font(.headline)
            TextField("Name", text: $model.saveName).textFieldStyle(.roundedBorder)
            Text(model.isCorrected ? "Saves two files: the raw points and the corrected points."
                 : "Nothing was moved yet. Saving still stores both files, with identical points.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Confirm correction") { model.confirm() }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder private var saved: some View {
        if !model.savedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.savedFiles, id: \.self) { name in
                    Label(name, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                Button("Show in Finder") {
                    let urls = model.savedFiles.map { library.outputDirectory.appendingPathComponent($0) }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                .controlSize(.small)
            }
        }
    }
}

/// The picture with its lines and the points on top. In the Corrected stage the points drag; otherwise they show only with indices on.
private struct EditorCanvas: View {
    @ObservedObject var model: ScanDebugViewModel
    @Binding var selected: String?
    var onTouch: () -> Void

    var body: some View {
        if let snapshot = model.snapshot {
            ScanOverlayView(snapshot: snapshot).overlay { points }
        }
    }

    private var points: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(model.shownSet?.points ?? []) { point in
                    handle(point, size: proxy.size)
                }
            }
            .coordinateSpace(name: "editor")
        }
    }

    @ViewBuilder private func handle(_ point: ScanDebugPoint, size: CGSize) -> some View {
        let editable = model.stage == .corrected
        if editable || model.showIndices {
            let isSelected = selected == point.id
            ZStack {
                Circle().fill(editable ? AppColors.rose : Color.white).frame(width: editable ? 11 : 7, height: editable ? 11 : 7)
                    .overlay(Circle().stroke(isSelected ? Color.yellow : .black.opacity(0.5), lineWidth: isSelected ? 2 : 1))
                if model.showIndices {
                    Text("\(point.index)").font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 3).background(.black.opacity(0.6), in: Capsule()).offset(x: 10, y: -10)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .position(x: point.x * size.width, y: point.y * size.height)
            .allowsHitTesting(editable)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("editor")).onChanged { drag in
                selected = point.id
                onTouch()
                model.move(point.id, toShown: CGPoint(x: drag.location.x / size.width, y: drag.location.y / size.height))
            }.onEnded { _ in model.endEdit() })
        }
    }
}
