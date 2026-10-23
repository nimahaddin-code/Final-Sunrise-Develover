import Combine
import CoreGraphics
import Foundation

/// State of the debug tab: one picked photo, the raw and corrected points of each outline, and the save step.
/// It never touches `FaceShapeStore`, the scan view models or the onboarding flag.
@MainActor final class ScanDebugViewModel: ObservableObject {
    /// One outline on the photo: what the detector found, what the person moved it to, and the picture to draw on.
    struct Session: Identifiable {
        var id = UUID()
        /// Used in the exported file name.
        var name = ScanDebugStore.timestamp(Date())
        var takenAt = Date()
        let raw: ScanDebugPointSet
        var corrected: ScanDebugPointSet
        /// The scan picture the points are normalized to; it only lives in memory.
        let picture: CGImage
    }

    struct Row: Equatable, Identifiable {
        var id: String { label }
        let label: String
        let value: String
        /// Final stage only: how much the correction changed the value.
        let change: String?
    }

    @Published var kind: ScanDebugKind = .face
    @Published var stage: ScanDebugStage = .raw
    @Published var showIndices = true
    @Published var saveName = ""
    @Published private(set) var sessions: [ScanDebugKind: Session] = [:]
    /// Earlier scans that a newer scan of the same kind replaced. Kept in memory only, so they can still be exported in bulk.
    @Published private(set) var archive: [Session] = []
    @Published private(set) var message: String?
    @Published private(set) var savedFiles: [String] = []
    let store: ScanDebugStore
    /// Earlier states of each outline's corrected points, newest last. One entry per drag.
    private var undoStacks: [ScanDebugKind: [ScanDebugPointSet]] = [:]
    private var isEditing = false
    private var checkpoint: (set: ScanDebugPointSet, undo: [ScanDebugPointSet])?

    init(store: ScanDebugStore = ScanDebugStore()) {
        self.store = store
    }

    var session: Session? { sessions[kind] }
    /// Every scan held this session, oldest first: the replaced ones and the two being edited.
    var allScans: [Session] { (archive + sessions.values).sorted { $0.takenAt < $1.takenAt } }
    var canUndo: Bool { !(undoStacks[kind] ?? []).isEmpty }
    var isCorrected: Bool { session.map { $0.corrected != $0.raw } ?? false }

    /// Points to draw for the current stage: the detector's in Raw, the person's otherwise.
    var shownSet: ScanDebugPointSet? {
        session.map { stage == .raw ? $0.raw : $0.corrected }
    }

    /// The scan picture with the lines of the current stage.
    var snapshot: ScanSnapshot? {
        guard let session, let set = shownSet else { return nil }
        return ScanSnapshot(croppedImage: session.picture, overlay: set.overlay)
    }

    var rows: [Row] {
        guard let session else { return [] }
        let raw = ScanDebugMeasure.report(for: session.raw)
        let corrected = ScanDebugMeasure.report(for: session.corrected)
        let report = stage == .raw ? raw : corrected
        var rows = report.metrics.map { metric in
            Row(label: metric.label, value: Self.format(metric.value, unit: metric.unit),
                change: stage == .final ? raw.value(metric.key).map { Self.format(metric.value - $0, unit: metric.unit, signed: true) } : nil)
        }
        if stage != .raw {
            rows.append(Row(label: "Mean point shift", value: Self.format(session.corrected.meanShift(from: session.raw), unit: "px"), change: nil))
        }
        rows.append(Row(label: "Classification", value: report.classification ?? "Not enough points", change: nil))
        return rows
    }

    private static func format(_ value: Double, unit: String, signed: Bool = false) -> String {
        let number = value.formatted(.number.precision(.fractionLength(unit == "px" ? 0 : 2)).sign(strategy: signed ? .always() : .automatic))
        return "\(number) \(unit)"
    }

    // MARK: Scan

    /// Takes the picture a finished face or eye scan produced as the raw points to correct.
    func accept(_ snapshot: ScanSnapshot?, kind: ScanDebugKind) {
        guard let snapshot, let set = ScanDebugSnapshotReader.pointSet(from: snapshot, kind: kind) else {
            message = "The scan finished without a usable picture, so there is nothing to correct. Scan again."
            return
        }
        if let previous = sessions[kind] { archive.append(previous) }
        sessions[kind] = Session(raw: set, corrected: set, picture: snapshot.image)
        undoStacks[kind] = []
        self.kind = kind
        stage = .raw
        saveName = ""
        savedFiles = []
        message = nil
    }

    /// Opens points that came from somewhere else, such as an exported scan file in the Mac editor.
    func load(raw: ScanDebugPointSet, corrected: ScanDebugPointSet, picture: CGImage) {
        sessions[raw.kind] = Session(raw: raw, corrected: corrected, picture: picture)
        undoStacks[raw.kind] = []
        kind = raw.kind
        stage = .raw
        savedFiles = []
        message = nil
    }

    /// What "Export for Mac" shares for one scan. The picture is only encoded when the person shares it.
    func exportItem(for session: Session) -> ScanDebugExportItem {
        ScanDebugExportItem(name: session.name, raw: session.raw, corrected: session.corrected, picture: session.picture)
    }

    /// The scan being edited, or `nil` before a scan was used.
    func exportItem() -> ScanDebugExportItem? { session.map(exportItem(for:)) }

    /// Every scan held this session, for the bulk export.
    var exportItems: [ScanDebugExportItem] { allScans.map(exportItem(for:)) }

    /// Makes a scan from the list the one being edited; the one it replaces goes to the list. Undo history is not kept across this.
    func activate(_ id: UUID) {
        if let index = archive.firstIndex(where: { $0.id == id }) {
            let chosen = archive.remove(at: index)
            if let current = sessions[chosen.raw.kind] { archive.append(current) }
            sessions[chosen.raw.kind] = chosen
            undoStacks[chosen.raw.kind] = []
            kind = chosen.raw.kind
        } else if let current = sessions.values.first(where: { $0.id == id }) {
            kind = current.raw.kind
        }
        stage = .raw
        isEditing = false
    }

    func remove(_ id: UUID) {
        archive.removeAll { $0.id == id }
        if let key = sessions.first(where: { $0.value.id == id })?.key {
            sessions[key] = nil
            undoStacks[key] = nil
        }
    }

    // MARK: Correction

    /// Moves a point of the corrected set. `position` is normalized to the scan picture.
    func move(_ id: String, toShown position: CGPoint) {
        guard stage == .corrected, var session = sessions[kind] else { return }
        if !isEditing {
            isEditing = true
            undoStacks[kind, default: []].append(session.corrected)
        }
        session.corrected.move(id, to: position)
        sessions[kind] = session
    }

    /// Call when a drag ends, so the next drag is one undo step of its own.
    func endEdit() { isEditing = false }

    /// Puts the corrected points back to how they were before the last drag or reset.
    func undo() {
        guard var session = sessions[kind], let previous = undoStacks[kind]?.popLast() else { return }
        session.corrected = previous
        sessions[kind] = session
    }

    /// Remembers the corrected points now, so `cancelEditing` can come back to them.
    func beginEditing() {
        guard let session else { return }
        checkpoint = (session.corrected, undoStacks[kind] ?? [])
    }

    /// Throws away everything moved since `beginEditing`.
    func cancelEditing() {
        guard var session = sessions[kind], let checkpoint else { return }
        session.corrected = checkpoint.set
        sessions[kind] = session
        undoStacks[kind] = checkpoint.undo
        self.checkpoint = nil
    }

    func resetCorrection() {
        guard var session = sessions[kind], session.corrected != session.raw else { return }
        undoStacks[kind, default: []].append(session.corrected)
        session.corrected = session.raw
        sessions[kind] = session
    }

    /// Saves the raw points and the corrected points as two separate files.
    func confirm() {
        guard let session else { return }
        do {
            savedFiles = try store.save(name: saveName, raw: session.raw, corrected: session.corrected)
            message = nil
            saveName = ""
        } catch {
            savedFiles = []
            message = "Could not save: \(error.localizedDescription)"
        }
    }
}
