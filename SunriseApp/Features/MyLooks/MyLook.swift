// -Nimah: one finished look in "My Looks": what was tried on, how it went, the photos and the try-on's measured target
// (saved by `MyLookStore`). Saved on this phone only. The feedback is kept as rule ids, bands and the words that filled
// them, never as finished text, so it reads in the app's current language when it is shown again (`MyLookFeedback`).
import CoreGraphics
import Foundation
import UIKit

struct MyLook: Codable, Identifiable, Hashable, Sendable {
    /// 1: photos saved cropped as shown, no target. 2: full photos, the result lined up as a third photo, the target saved.
    static let currentSchema = 2
    /// Longest title the person can give a look.
    static let titleLimit = 30

    struct Shade: Codable, Hashable, Sendable {
        enum Source: String, Codable, Sendable { case palette, product }
        var id: String
        var name: String
        /// "#RRGGBB".
        var hex: String
        var source: Source
        /// The shade's opacity at the default strength (to try it on again).
        var opacity: Double?
    }

    /// 0...1 each; nil when that part was not measured (e.g. a tool without scoring yet).
    struct Score: Codable, Hashable, Sendable {
        var overall: Double?
        var placement: Double?
        var shade: Double?
        var date: Date
    }

    /// One feedback message by its database id, band ("ok", "slight", "clear", "large"), side and filling words.
    struct Rule: Codable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            /// Something to fix (a rule of the tool).
            case fix
            /// What went well.
            case praise
            /// A photo note (`capture.*`).
            case note
        }
        var id: String
        var band: String
        var side: String?
        var kind: Kind?
        /// The words in the message ({zone}, {other}, ...), in the language of `MyLook.language`.
        var values: [String: String]?
        /// The cards it is told on ("placement", "shade"; a rule ending in ".none" is on both).
        var cards: [String]?
        /// Among the top messages of the screen (`MakeupFeedback.items`): the first is "Fix this first".
        var top: Bool?
    }

    /// The dashed outlines of the first fix: 0...1 points on the result photo.
    struct Mark: Codable, Hashable, Sendable {
        var side: String
        var target: [CGPoint]
        var add: [CGPoint]
        var remove: [CGPoint]
    }

    var schemaVersion = MyLook.currentSchema
    var id = UUID()
    /// `TryOnTool.storageKey`.
    var tool: String
    /// The look picked on Try On (blush style, liner look, brow overlay or lip style id). With `tool`, the look's key:
    /// trying the same look again updates its entry.
    var lookId: String
    var title: String
    /// What the title goes back to when the person clears it, e.g. "Sunkissed blush".
    var defaultTitle: String
    var createdAt: Date
    var updatedAt: Date
    var attemptCount = 1
    /// Kept under "Favorites" on the My Looks page (the heart).
    var isFavorite = false
    var shades: [Shade] = []
    var intensity: Double?
    var faceShape: String?
    var eyeShape: String?
    var score: Score
    var rules: [Rule] = []
    var marks: [Mark] = []
    /// Earlier attempts' scores, oldest first.
    var previousScores: [Score] = []
    /// The feedback language the rule words were written in ("en", "id").
    var language: String?
    /// File names inside the look's folder; nil when there was none (e.g. the Simulator).
    var expectedPhoto: String?
    var resultPhoto: String?
    /// The result lined up with the expected photo, for the slider.
    var comparePhoto: String?
    /// The try-on's measured target (the desired photo's face numbers), so "Try again" can score without a new photo.
    var targetScan: String?

    var key: String { "\(tool)/\(lookId)" }
    /// Schema 1 saved its photos already cropped to the tool's area.
    var photosCropped: Bool { schemaVersion < 2 }

    /// The title as the person typed it: trimmed, at most `titleLimit` characters, empty -> the default title.
    static func cleanTitle(_ title: String, default fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(titleLimit))
    }
}

extension MyLook {
    init(id: UUID = UUID(), tool: String, lookId: String, title: String, createdAt: Date, score: Score) {
        self.id = id
        self.tool = tool
        self.lookId = lookId
        self.title = title
        defaultTitle = title
        self.createdAt = createdAt
        updatedAt = createdAt
        self.score = score
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, tool, lookId, title, defaultTitle, createdAt, updatedAt, attemptCount, isFavorite, shades, intensity,
             faceShape, eyeShape, score, rules, marks, previousScores, language, expectedPhoto, resultPhoto, comparePhoto,
             targetScan
    }

    /// Older files miss newer fields: those take their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        id = try c.decode(UUID.self, forKey: .id)
        tool = try c.decode(String.self, forKey: .tool)
        lookId = try c.decode(String.self, forKey: .lookId)
        title = try c.decode(String.self, forKey: .title)
        defaultTitle = try c.decodeIfPresent(String.self, forKey: .defaultTitle) ?? title
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        attemptCount = try c.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 1
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        shades = try c.decodeIfPresent([Shade].self, forKey: .shades) ?? []
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity)
        faceShape = try c.decodeIfPresent(String.self, forKey: .faceShape)
        eyeShape = try c.decodeIfPresent(String.self, forKey: .eyeShape)
        score = try c.decodeIfPresent(Score.self, forKey: .score) ?? Score(date: createdAt)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        marks = try c.decodeIfPresent([Mark].self, forKey: .marks) ?? []
        previousScores = try c.decodeIfPresent([Score].self, forKey: .previousScores) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language)
        expectedPhoto = try c.decodeIfPresent(String.self, forKey: .expectedPhoto)
        resultPhoto = try c.decodeIfPresent(String.self, forKey: .resultPhoto)
        comparePhoto = try c.decodeIfPresent(String.self, forKey: .comparePhoto)
        targetScan = try c.decodeIfPresent(String.self, forKey: .targetScan)
    }
}

extension MyLook.Score {
    init(date: Date) { self.init(overall: nil, placement: nil, shade: nil, date: date) }
}

/// One finished run, ready for `MyLookStore.save`: the look's data, its photos as JPEG and the try-on's target.
struct MyLookDraft: @unchecked Sendable {
    var tool: String
    var lookId: String
    var title: String
    var shades: [MyLook.Shade]
    var intensity: Double?
    var faceShape: String? = nil
    var eyeShape: String? = nil
    var score: MyLook.Score
    var rules: [MyLook.Rule]
    var marks: [MyLook.Mark]
    var language: String? = nil
    var expectedJPEG: Data?
    var resultJPEG: Data?
    var compareJPEG: Data? = nil
    var targetScan: FaceScan? = nil
}

extension MyLookDraft {
    /// From the feedback screen: the tool's look, shade and strength from Try On, the scores and every message by id.
    init(feedback: MakeupFeedback, handoff: TutorialHandoff, date: Date, language: FeedbackLanguage = .current,
         expectedJPEG: Data?, resultJPEG: Data?, compareJPEG: Data? = nil, targetScan: FaceScan? = nil) {
        let tool = handoff.tool
        let shades = handoff.shades[tool].map { [MyLook.Shade($0)] } ?? []
        func percent(_ id: String) -> Double? { feedback.categories.first { $0.id == id }?.percent }
        self.init(tool: tool.storageKey, lookId: handoff.lookId, title: handoff.styleTitle, shades: shades,
                  intensity: handoff.intensities[tool],
                  score: MyLook.Score(overall: feedback.score, placement: percent("placement"), shade: percent("shade"), date: date),
                  rules: Self.rules(feedback),
                  marks: feedback.marks.map { MyLook.Mark(side: $0.side.rawValue, target: $0.target, add: $0.add, remove: $0.remove) },
                  language: language.rawValue, expectedJPEG: expectedJPEG, resultJPEG: resultJPEG, compareJPEG: compareJPEG,
                  targetScan: targetScan)
    }

    /// The top messages in order, then every other card message, the notes and the praise; one entry per rule and side,
    /// with the cards it is told on.
    static func rules(_ feedback: MakeupFeedback) -> [MyLook.Rule] {
        var rules: [MyLook.Rule] = []
        func key(_ item: MakeupFeedback.Item) -> String { "\(item.rule)|\(item.side?.rawValue ?? "")" }
        func add(_ item: MakeupFeedback.Item, kind: MyLook.Rule.Kind, card: String? = nil, top: Bool = false) {
            guard !item.rule.isEmpty else { return }
            if let i = rules.firstIndex(where: { "\($0.id)|\($0.side ?? "")" == key(item) }) {
                if let card, !(rules[i].cards ?? []).contains(card) { rules[i].cards = (rules[i].cards ?? []) + [card] }
                if top { rules[i].top = true }
                return
            }
            rules.append(MyLook.Rule(id: item.rule, band: item.band.key, side: item.side?.rawValue, kind: kind,
                                     values: item.values.isEmpty ? nil : item.values, cards: card.map { [$0] }, top: top ? true : nil))
        }
        let notes = Set(feedback.notes.map(key))
        for item in feedback.items where !notes.contains(key(item)) { add(item, kind: .fix, top: true) }
        for category in feedback.categories { for item in category.items { add(item, kind: .fix, card: category.id) } }
        for item in feedback.notes { add(item, kind: .note) }
        for item in feedback.praise { add(item, kind: .praise) }
        return rules
    }

    /// A photo for the store: at most 1280 px on its long side, JPEG quality 0.8 (a few hundred kB).
    static func jpeg(_ image: UIImage?, longSide: CGFloat = 1280) -> Data? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let factor = min(1, longSide / max(pixels.width, pixels.height))
        let size = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: 0.8)
    }
}

extension MyLook.Shade {
    /// A colour made on the colour sheet (from a photo of the product) has a "custom." id.
    init(_ shade: MakeupShade) {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        self.init(id: shade.id, name: String(localized: shade.name),
                  hex: String(format: "#%02X%02X%02X", byte(shade.red), byte(shade.green), byte(shade.blue)),
                  source: shade.id.hasPrefix("custom.") ? .product : .palette, opacity: shade.opacity)
    }

    /// Back to a shade to try on: the palette's own when it still exists, else this colour.
    func makeupShade(for tool: TryOnTool) -> MakeupShade {
        let palette = tool == .lips ? MakeupPalette.lipShades : MakeupPalette.shades(for: tool.category)
        if let known = palette.first(where: { $0.id == id }) { return known }
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return MakeupShade(id: id, name: LocalizedStringResource(stringLiteral: name),
                           red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                           blue: Double(value & 0xFF) / 255, opacity: opacity ?? 0.7)
    }
}

extension TutorialHandoff {
    /// The id of the look picked on Try On, for My Looks.
    var lookId: String {
        switch tool {
        case .blush: blushStyle?.rawValue ?? "none"
        case .eyeliner: linerLook.rawValue
        case .eyebrow: browOverlay?.id ?? "none"
        case .lips: lipStyle.rawValue
        }
    }
}

extension TryOnTool {
    /// The tool's name in saved files: never changes, whatever the title says.
    var storageKey: String {
        switch self {
        case .blush: "blush"
        case .eyeliner: "eyeliner"
        case .eyebrow: "eyebrow"
        case .lips: "lips"
        }
    }

    init?(storageKey: String) {
        guard let tool = Self.allCases.first(where: { $0.storageKey == storageKey }) else { return nil }
        self = tool
    }
}
