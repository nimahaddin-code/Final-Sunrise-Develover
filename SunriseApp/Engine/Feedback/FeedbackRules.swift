// -Nimah: the rules of `makeup-feedback.database.json` (bands, messages, selection, score) and how a set of measured
// hits becomes the feedback the person reads. Deterministic: no model, no network.
import Foundation

struct FeedbackDatabase: Decodable, Sendable {
    struct Text: Decodable, Sendable { let title: String; let say: String; let steps: [String]? }
    struct Localized: Decodable, Sendable {
        let id: Text; let en: Text
        func text(_ language: FeedbackLanguage) -> Text { language == .id ? id : en }
    }
    struct Thresholds: Decodable, Sendable { let ok: Double; let slight: Double; let clear: Double }
    struct Rule: Decodable, Sendable {
        let id: String
        let kind: String
        let direction: String?
        let scale: String?
        let thresholds: Thresholds?
        let priority: Int
        let weight: Double
        let suppresses: [String]?
        let messages: [String: Localized]?
        let looks: [String]?
        let not_for_looks: [String]?
    }
    struct Praise: Decodable, Sendable { let id: String; let message: Localized }
    struct Capture: Decodable, Sendable { let id: String; let blocking: Bool; let message: Localized }
    struct Tool: Decodable, Sendable { let rules: [Rule]; let symmetry: [Rule]; let praise: [Praise] }
    struct Tools: Decodable, Sendable { let blush: Tool }
    struct Band: Decodable, Sendable { let score: Double }
    struct Bands: Decodable, Sendable { let ok: Band; let slight: Band; let clear: Band; let large: Band }
    struct ScoreLabel: Decodable, Sendable { let min: Double; let id: String; let en: String }
    struct Selection: Decodable, Sendable { let max_messages_per_tool: Int; let score_labels: [ScoreLabel] }
    struct Vocabulary: Decodable, Sendable {
        let side: [String: String]; let cheek: [String: String]; let blush_zone: [String: String]; let spill_zone: [String: String]
    }

    let bands: Bands
    let vocabulary: [String: Vocabulary]
    let selection: Selection
    let capture: [Capture]
    let tools: Tools

    static func load(bundle: Bundle = .main) -> FeedbackDatabase? {
        guard let url = bundle.url(forResource: "makeup-feedback.database", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeedbackDatabase.self, from: data)
    }

    func rule(_ id: String) -> Rule? { (tools.blush.rules + tools.blush.symmetry).first { $0.id == id } }
    func captureRule(_ id: String) -> Capture? { capture.first { $0.id == id } }
    func words(_ language: FeedbackLanguage) -> Vocabulary { vocabulary[language.rawValue] ?? vocabulary["en"]! }
}

enum FeedbackLanguage: String, Sendable {
    case id, en
    /// The app's own language: Indonesian when the app runs in Indonesian, otherwise English.
    static var current: FeedbackLanguage { Bundle.main.preferredLocalizations.first?.hasPrefix("id") == true ? .id : .en }
}

enum FeedbackBand: Int, Comparable, Sendable {
    case ok, slight, clear, large
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var key: String { ["ok", "slight", "clear", "large"][rawValue] }
    func score(_ bands: FeedbackDatabase.Bands) -> Double {
        switch self { case .ok: bands.ok.score; case .slight: bands.slight.score; case .clear: bands.clear.score; case .large: bands.large.score }
    }

    /// The database's four ways of reading thresholds (`bands.how_to_read_thresholds`). `value` is already the
    /// deviation for `abs` (|measured - target|) and the ratio for `ratio`.
    static func of(_ value: Double, kind: String, _ t: FeedbackDatabase.Thresholds, scale: Double = 1) -> FeedbackBand {
        switch kind {
        case "min":
            return value >= t.ok * scale ? .ok : value >= t.slight * scale ? .slight : value >= t.clear * scale ? .clear : .large
        case "ratio":
            let f = value > 0 ? max(value, 1 / value) : .infinity
            return f <= t.ok ? .ok : f <= t.slight ? .slight : f <= t.clear ? .clear : .large
        default: // abs, max
            let v = abs(value)
            return v <= t.ok * scale ? .ok : v <= t.slight * scale ? .slight : v <= t.clear * scale ? .clear : .large
        }
    }
}

/// Which cheek (or brow, or eye) a hit is about. `both` once left and right hits are merged.
enum FeedbackSide: String, Sendable { case left, right, both }

/// One measured result that crossed a rule's threshold.
struct FeedbackHit: Sendable {
    var rule: String
    var band: FeedbackBand
    var side: FeedbackSide
    var priority: Int
    /// Fills the message's placeholders ({delta}, {value}, {zone}, {other}). {part} comes from `side`.
    var values: [String: String]
    /// For sorting hits of the same band and priority: larger first.
    var size: Double
    var suppresses: [String]
}

/// One evaluated metric, for the score (also the ones that were ok).
struct FeedbackScoreEntry: Sendable { var band: FeedbackBand; var weight: Double }

struct FeedbackComposer {
    let database: FeedbackDatabase
    let language: FeedbackLanguage

    /// Steps 3-6 of `selection.order`: merge left and right, drop suppressed hits, sort, keep the first few.
    func select(_ hits: [FeedbackHit]) -> [FeedbackHit] {
        var merged: [FeedbackHit] = []
        for hit in hits where hit.band != .ok {
            if let i = merged.firstIndex(where: { $0.rule == hit.rule && $0.band == hit.band && $0.side != hit.side && $0.side != .both }) {
                merged[i].side = .both
                if hit.size > merged[i].size { merged[i].values = hit.values; merged[i].size = hit.size }
            } else {
                merged.append(hit)
            }
        }
        let kept = merged.filter { hit in
            !merged.contains { other in
                other.rule != hit.rule && other.band >= hit.band
                    && (other.side == hit.side || other.side == .both || hit.side == .both)
                    && other.suppresses.contains { Self.matches(hit.rule, pattern: $0) }
            }
        }
        let sorted = kept.sorted {
            ($0.band, -$0.priority, $0.size) > ($1.band, -$1.priority, $1.size)
        }
        return Array(sorted.prefix(database.selection.max_messages_per_tool))
    }

    static func matches(_ id: String, pattern: String) -> Bool {
        pattern.hasSuffix("*") ? id.hasPrefix(pattern.dropLast()) : id == pattern
    }

    func message(for hit: FeedbackHit) -> MakeupFeedback.Item? {
        guard let rule = database.rule(hit.rule), let text = rule.messages?[hit.band.key]?.text(language) else { return nil }
        var values = hit.values
        values["part"] = database.words(language).cheek[hit.side.rawValue]
        return MakeupFeedback.Item(title: text.title, say: fill(text.say, values), steps: text.steps ?? [], band: hit.band)
    }

    func fill(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for (key, value) in values { out = out.replacingOccurrences(of: "{\(key)}", with: value) }
        return out
    }

    func score(_ entries: [FeedbackScoreEntry]) -> Double? {
        let weight = entries.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        return entries.reduce(0) { $0 + $1.band.score(database.bands) * $1.weight } / weight
    }

    func label(score: Double) -> String {
        let labels = database.selection.score_labels.sorted { $0.min > $1.min }
        let label = labels.first { score >= $0.min } ?? labels.last
        return (language == .id ? label?.id : label?.en) ?? ""
    }

    /// Rounding of `placeholders.{delta}`: mm to 0.5, percent to 5, degrees to 1.
    static func mm(_ v: Double) -> String { String(format: "%g", (abs(v) * 2).rounded() / 2) }
    static func percent(_ v: Double) -> String { String(Int((v / 5).rounded() * 5)) }
    static func degrees(_ v: Double) -> String { String(Int(abs(v).rounded())) }
    static func times(_ v: Double) -> String { String(format: "%.1f", v) }
}
