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
    struct Capture: Decodable, Sendable { let id: String; let blocking: Bool; let tools: [String]?; let message: Localized }
    struct Tool: Decodable, Sendable { let rules: [Rule]; let symmetry: [Rule]; let praise: [Praise] }
    struct Tools: Decodable, Sendable { let blush: Tool; let brow: Tool; let eyeliner: Tool }
    struct Band: Decodable, Sendable { let score: Double }
    struct Bands: Decodable, Sendable { let ok: Band; let slight: Band; let clear: Band; let large: Band }
    struct ScoreLabel: Decodable, Sendable { let min: Double; let id: String; let en: String }
    struct Selection: Decodable, Sendable { let max_messages_per_tool: Int; let score_labels: [ScoreLabel] }
    struct Vocabulary: Decodable, Sendable {
        let side: [String: String]; let cheek: [String: String]; let brow: [String: String]; let eye: [String: String]
        let blush_zone: [String: String]; let spill_zone: [String: String]; let brow_zone: [String: String]
        let liner_zone: [String: String]
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

    func tool(_ tool: TryOnTool) -> Tool {
        switch tool { case .blush: tools.blush; case .eyebrow: tools.brow; case .eyeliner: tools.eyeliner }
    }
    func rule(_ id: String) -> Rule? {
        [tools.blush, tools.brow, tools.eyeliner].lazy.flatMap { $0.rules + $0.symmetry }.first { $0.id == id }
    }
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
struct FeedbackScoreEntry: Sendable { var band: FeedbackBand; var weight: Double; var priority: Int }

/// The feedback screen's cards: the database's `selection.priority_groups`, by the rule's priority.
enum FeedbackCategory: String, CaseIterable, Sendable {
    case placement, shape, amount, edges, finish, balance

    init(priority: Int) {
        switch priority {
        case ..<20: self = .amount   // nothing applied
        case 20..<30: self = .placement
        case 30..<40: self = .shape
        case 40..<50: self = .amount
        case 50..<60: self = .edges
        case 60..<70: self = .finish
        default: self = .balance
        }
    }

    var title: String {
        switch self {
        case .placement: String(localized: "Placement")
        case .shape: String(localized: "Shape")
        case .amount: String(localized: "Amount")
        case .edges: String(localized: "Clean edges")
        case .finish: String(localized: "Finish")
        case .balance: String(localized: "Balance")
        }
    }

    var symbol: String {
        switch self {
        case .placement: "viewfinder"
        case .shape: "scribble.variable"
        case .amount: "drop.fill"
        case .edges: "sparkles"
        case .finish: "paintpalette.fill"
        case .balance: "arrow.left.and.right"
        }
    }
}

struct FeedbackComposer {
    let database: FeedbackDatabase
    let language: FeedbackLanguage
    /// The vocabulary for {part}: cheek, brow or eye.
    var part: KeyPath<FeedbackDatabase.Vocabulary, [String: String]> = \.cheek

    func partName(_ side: FeedbackSide) -> String { database.words(language)[keyPath: part][side.rawValue] ?? "" }

    /// Steps 3-6 of `selection.order`: merge left and right, drop suppressed hits, sort, keep the first few.
    func select(_ hits: [FeedbackHit], limit: Int? = nil) -> [FeedbackHit] {
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
        return Array(sorted.prefix(limit ?? database.selection.max_messages_per_tool))
    }

    /// The whole feedback: the top messages (or praise), the score and its label, and one card per measured category with
    /// its own percentage, short label and every message of that category.
    func assemble(hits: [FeedbackHit], entries: [FeedbackScoreEntry], praise: [MakeupFeedback.Item],
                  notes: [MakeupFeedback.Item]) -> MakeupFeedback {
        let chosen = select(hits).compactMap { message(for: $0) }
        let score = score(entries)
        let all = select(hits, limit: .max)
        let categories = FeedbackCategory.allCases.compactMap { category -> MakeupFeedback.Category? in
            let own = entries.filter { FeedbackCategory(priority: $0.priority) == category }
            guard let percent = self.score(own) else { return nil }
            let messages = all.filter { FeedbackCategory(priority: $0.priority) == category }.compactMap { message(for: $0) }
            return MakeupFeedback.Category(id: category.rawValue, title: category.title, symbol: category.symbol,
                                           percent: percent / 100, label: messages.first?.title ?? String(localized: "Spot on"),
                                           items: messages)
        }
        // The score card's line, short as in the design: the two weakest categories' labels, or the first praise.
        let weakest = categories.filter { !$0.items.isEmpty }.sorted { $0.percent < $1.percent }.prefix(2).map(\.label)
        let summary = weakest.isEmpty ? (praise.first?.title ?? "") : weakest.joined(separator: ". ") + "."
        func part(_ id: FeedbackCategory) -> MakeupFeedback.Part? {
            categories.first { $0.id == id.rawValue }.map { .init(value: $0.percent, note: $0.label) }
        }
        return MakeupFeedback(score: score.map { $0 / 100 }, headline: score.map { label(score: $0) } ?? "", comments: [],
                              items: (chosen.isEmpty ? praise : chosen) + notes, categories: categories,
                              summary: summary, notes: notes, placement: part(.placement), shade: part(.finish))
    }

    static func matches(_ id: String, pattern: String) -> Bool {
        pattern.hasSuffix("*") ? id.hasPrefix(pattern.dropLast()) : id == pattern
    }

    func message(for hit: FeedbackHit) -> MakeupFeedback.Item? {
        guard let rule = database.rule(hit.rule), let text = rule.messages?[hit.band.key]?.text(language) else { return nil }
        var values = hit.values
        values["part"] = partName(hit.side)
        return MakeupFeedback.Item(title: text.title, say: fill(text.say, values), steps: text.steps ?? [], band: hit.band, rule: hit.rule)
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

    /// A praise message of `tool` by id, with {part} = both sides.
    func praise(_ id: String, tool: FeedbackDatabase.Tool, values: [String: String] = [:]) -> MakeupFeedback.Item? {
        guard let p = tool.praise.first(where: { $0.id == id }) else { return nil }
        let text = p.message.text(language)
        var all = values; all["part"] = all["part"] ?? partName(.both)
        return MakeupFeedback.Item(title: text.title, say: fill(text.say, all), steps: [], band: .ok, rule: id)
    }
}

/// The photo checks of `capture` shared by every tool (step 1 of `selection.order`).
struct FeedbackPhotoCheck {
    var blocking: [MakeupFeedback.Item] = []
    var notes: [MakeupFeedback.Item] = []

    init() {}

    init(before: FaceScan?, after: FaceScan?, tool: String, composer: FeedbackComposer) {
        let language = composer.language
        let names = language == .id ? ["Try On", "hasil"] : ["Try On", "result"]
        for (index, scan) in [before, after].enumerated() {
            let photo = ["photo": names[index]]
            guard let scan else { report("capture.no_face", photo, tool: tool, composer); continue }
            // Calibration (device test 2026-11-09): a phone held a little below the eyes reads 8° down, and the database's 8°
            // blocked every result. Up to `poseBlockingDegrees` it is a note; beyond, a retake.
            if abs(scan.yaw) > 8 {
                report("capture.turned", photo.merging(["value": FeedbackComposer.degrees(Double(scan.yaw))]) { $1 }, tool: tool, composer,
                       blocks: abs(scan.yaw) > Self.poseBlockingDegrees)
            }
            if abs(scan.pitch) > 8 {
                let down = scan.pitch > 0
                let direction = language == .id ? (down ? "menunduk" : "mendongak") : (down ? "tilted down" : "tilted up")
                report("capture.tilted_up_down", photo.merging(["direction": direction, "value": FeedbackComposer.degrees(Double(scan.pitch))]) { $1 },
                       tool: tool, composer, blocks: abs(scan.pitch) > Self.poseBlockingDegrees)
            }
            if abs(scan.roll) > 5 { report("capture.rolled", photo.merging(["value": FeedbackComposer.degrees(Double(scan.roll))]) { $1 }, tool: tool, composer) }
            if scan.smile > 0.3 { report("capture.smiling", photo, tool: tool, composer) }
            if scan.jawOpen > 0.25 { report("capture.mouth_open", photo, tool: tool, composer) }
            if scan.blink > 0.5 { report("capture.eyes_closed", photo, tool: tool, composer) }
            if scan.browRaise > 0.3 { report("capture.brows_raised", photo, tool: tool, composer) }
            if let skin = FeedbackSkin.lightness(scan, rendered: false), skin < 35 { report("capture.too_dark", photo, tool: tool, composer) }
        }
        if let before, let after, abs(before.yaw - after.yaw) > 6 || abs(before.pitch - after.pitch) > 6 {
            report("capture.pose_mismatch", [:], tool: tool, composer)
        }
    }

    static let poseBlockingDegrees: Float = 15

    mutating func report(_ id: String, _ values: [String: String] = [:], tool: String, _ composer: FeedbackComposer, blocks override: Bool? = nil) {
        guard let rule = composer.database.captureRule(id), rule.tools?.contains(tool) ?? true else { return }
        let text = rule.message.text(composer.language)
        let blocks = override ?? rule.blocking
        let item = MakeupFeedback.Item(title: text.title, say: composer.fill(text.say, values), steps: text.steps ?? [],
                                       band: blocks ? .large : .slight, rule: id)
        if blocks { if !blocking.contains(item) { blocking.append(item) } } else if !notes.contains(item) { notes.append(item) }
    }
}

/// Skin away from makeup (forehead centre and chin, `coordinates.skin_reference`), for light matching.
enum FeedbackSkin {
    static func isReference(_ s: FaceScan.Sample, eyeY: Float) -> Bool {
        (s.position.y > eyeY + 25 && abs(s.position.x) < 25) || (s.position.y < eyeY - 100 && abs(s.position.x) < 18)
    }

    static func lightness(_ scan: FaceScan, rendered: Bool) -> Float? {
        let values = scan.samples.compactMap { s -> Float? in
            guard s.visible, isReference(s, eyeY: scan.eyeY) else { return nil }
            return rendered ? s.rendered?.x : s.lab.x
        }
        guard values.count >= 10 else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    /// What to add to the result's colours so its skin reference matches the desired-look photo's, and whether the
    /// light changed more than `detection.normalise.max_correction` allows.
    static func shift(before: FaceScan, after: FaceScan, both: [Int]) -> (shift: Lab, mismatch: Bool) {
        let reference = both.filter { isReference(before.samples[$0], eyeY: before.eyeY) }
        guard reference.count >= 10 else { return (.zero, false) }
        let b = reference.reduce(Lab.zero) { $0 + before.samples[$1].lab } / Float(reference.count)
        let a = reference.reduce(Lab.zero) { $0 + after.samples[$1].lab } / Float(reference.count)
        let s = b - a
        return (s, abs(s.x) > 12 || abs(s.y) > 6 || abs(s.z) > 6)
    }
}
