import Combine
import Foundation

/// One saved file: a set of points (never the photo) with what it measured.
struct ScanDebugRecord: Codable, Equatable, Identifiable, Sendable {
    enum Stage: String, Codable, Sendable { case raw, corrected }

    var name: String
    var kind: ScanDebugKind
    var stage: Stage
    var savedAt: Date
    var imageWidth: Int
    var imageHeight: Int
    var points: [ScanDebugPoint]
    var measurements: [String: Double]
    var classification: String?
    /// File name, set when loaded from disk.
    var id: String { "\(kind.rawValue)-\(name).\(stage.rawValue).json" }
}

/// Keeps the confirmed corrections as JSON files in Application Support, one file for the raw points and one for the
/// corrected points, named after the kind and the name the person gave. Nothing here touches the main scan flow or leaves the
/// device.
@MainActor final class ScanDebugStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let record: ScanDebugRecord
        let url: URL
        var id: URL { url }
    }

    @Published private(set) var items: [Item] = []
    private(set) var directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                                     appropriateFor: nil, create: true))?
            .appendingPathComponent("ScanDebug", isDirectory: true) ?? FileManager.default.temporaryDirectory.appendingPathComponent("ScanDebug")
        reload()
    }

    /// A file-safe name; falls back to `fallback` when nothing usable is left.
    nonisolated static func sanitized(_ name: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(cleaned).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(60))
    }

    /// Writes `raw` and `corrected` as two separate files and returns their names. A name already in use gets `-2`, `-3`…
    /// so an earlier correction is never overwritten.
    @discardableResult
    func save(name: String, raw: ScanDebugPointSet, corrected: ScanDebugPointSet, now: Date = Date()) throws -> [String] {
        let kind = raw.kind
        let stamp = Self.timestamp(now)
        let base = Self.sanitized(name, fallback: stamp)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var unique = base, counter = 2
        func clash(_ candidate: String) -> Bool {
            [ScanDebugRecord.Stage.raw, .corrected].contains {
                fileManager.fileExists(atPath: directory.appendingPathComponent("\(kind.rawValue)-\(candidate).\($0.rawValue).json").path)
            }
        }
        while clash(unique) { unique = "\(base)-\(counter)"; counter += 1 }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var written: [URL] = []
        do {
            for (stage, set) in [(ScanDebugRecord.Stage.raw, raw), (.corrected, corrected)] {
                let report = ScanDebugMeasure.report(for: set)
                let record = ScanDebugRecord(name: unique, kind: kind, stage: stage, savedAt: now, imageWidth: set.imageWidth,
                                             imageHeight: set.imageHeight, points: set.points,
                                             measurements: Dictionary(uniqueKeysWithValues: report.metrics.map { ($0.key, $0.value) }),
                                             classification: report.classification)
                let url = directory.appendingPathComponent(record.id)
                try encoder.encode(record).write(to: url, options: .atomic)
                written.append(url)
            }
        } catch {
            written.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
        reload()
        return written.map(\.lastPathComponent)
    }

    /// Saves into another folder from now on (the Mac editor's output folder).
    func use(directory newDirectory: URL) {
        directory = newDirectory
        reload()
    }

    func delete(_ item: Item) {
        try? fileManager.removeItem(at: item.url)
        reload()
    }

    func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        items = urls.filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ScanDebugRecord.self, from: $0) }.map { Item(record: $0, url: url) } }
            .sorted { ($0.record.savedAt, $0.record.id) > ($1.record.savedAt, $1.record.id) }
    }

    nonisolated static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
