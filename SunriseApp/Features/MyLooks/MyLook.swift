// -Nimah: one finished look in "My Looks": what was tried on, how it went, and the two photos (saved by `MyLookStore`).
// Saved on this phone only. The feedback is kept as rule ids and bands, never as text, so it reads in the app's current
// language when it is shown again.
import CoreGraphics
import Foundation
import UIKit

struct MyLook: Codable, Identifiable, Hashable, Sendable {
    /// Bump when a field changes meaning; new optional fields only need a default in `init(from:)`.
    static let currentSchema = 1
    /// Longest title the person can give a look.
    static let titleLimit = 30

    struct Shade: Codable, Hashable, Sendable {
        enum Source: String, Codable, Sendable { case palette, product }
        var id: String
        var name: String
        /// "#RRGGBB".
        var hex: String
        var source: Source
    }

    /// 0...1 each; nil when that part was not measured (e.g. a tool without scoring yet).
    struct Score: Codable, Hashable, Sendable {
        var overall: Double?
        var placement: Double?
        var shade: Double?
        var date: Date
    }

    /// A feedback message by its database id, band ("ok", "slight", "clear", "large") and side.
    struct Rule: Codable, Hashable, Sendable {
        var id: String
        var band: String
        var side: String?
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
    var shades: [Shade] = []
    var intensity: Double?
    var faceShape: String?
    var eyeShape: String?
    var score: Score
    var rules: [Rule] = []
    var marks: [Mark] = []
    /// Earlier attempts' scores, oldest first.
    var previousScores: [Score] = []
    /// File names inside the look's folder; nil when there was no photo (e.g. the Simulator).
    var expectedPhoto: String?
    var resultPhoto: String?

    var key: String { "\(tool)/\(lookId)" }

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
        case schemaVersion, id, tool, lookId, title, defaultTitle, createdAt, updatedAt, attemptCount, shades, intensity,
             faceShape, eyeShape, score, rules, marks, previousScores, expectedPhoto, resultPhoto
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
        shades = try c.decodeIfPresent([Shade].self, forKey: .shades) ?? []
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity)
        faceShape = try c.decodeIfPresent(String.self, forKey: .faceShape)
        eyeShape = try c.decodeIfPresent(String.self, forKey: .eyeShape)
        score = try c.decodeIfPresent(Score.self, forKey: .score) ?? Score(date: createdAt)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        marks = try c.decodeIfPresent([Mark].self, forKey: .marks) ?? []
        previousScores = try c.decodeIfPresent([Score].self, forKey: .previousScores) ?? []
        expectedPhoto = try c.decodeIfPresent(String.self, forKey: .expectedPhoto)
        resultPhoto = try c.decodeIfPresent(String.self, forKey: .resultPhoto)
    }
}

extension MyLook.Score {
    init(date: Date) { self.init(overall: nil, placement: nil, shade: nil, date: date) }
}

/// One finished run, ready for `MyLookStore.save`: the look's data and its two photos as JPEG.
struct MyLookDraft: Sendable {
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
    var expectedJPEG: Data?
    var resultJPEG: Data?
}

extension MyLookDraft {
    /// From the feedback screen: the tool's look, shade and strength from Try On, the scores and messages by id.
    init(feedback: MakeupFeedback, handoff: TutorialHandoff, date: Date, expectedJPEG: Data?, resultJPEG: Data?) {
        let tool = handoff.tool
        let lookId: String = switch tool {
        case .blush: handoff.blushStyle?.rawValue ?? "none"
        case .eyeliner: handoff.linerLook.rawValue
        case .eyebrow: handoff.browOverlay?.id ?? "none"
        case .lips: handoff.lipStyle.rawValue
        }
        let shades = handoff.shades[tool].map { [MyLook.Shade($0)] } ?? []
        func percent(_ id: String) -> Double? { feedback.categories.first { $0.id == id }?.percent }
        var seen = Set<String>()
        let rules = (feedback.items + feedback.praise).compactMap { item -> MyLook.Rule? in
            guard !item.rule.isEmpty, seen.insert("\(item.rule)|\(item.side?.rawValue ?? "")").inserted else { return nil }
            return MyLook.Rule(id: item.rule, band: item.band.key, side: item.side?.rawValue)
        }
        self.init(tool: tool.storageKey, lookId: lookId, title: handoff.styleTitle, shades: shades,
                  intensity: handoff.intensities[tool],
                  score: MyLook.Score(overall: feedback.score, placement: percent("placement"), shade: percent("shade"), date: date),
                  rules: rules,
                  marks: feedback.marks.map { MyLook.Mark(side: $0.side.rawValue, target: $0.target, add: $0.add, remove: $0.remove) },
                  expectedJPEG: expectedJPEG, resultJPEG: resultJPEG)
    }
}

extension MyLook.Shade {
    /// A colour made on the colour sheet (from the palette's picker or the product camera) has a "custom." id.
    init(_ shade: MakeupShade) {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        self.init(id: shade.id, name: String(localized: shade.name),
                  hex: String(format: "#%02X%02X%02X", byte(shade.red), byte(shade.green), byte(shade.blue)),
                  source: shade.id.hasPrefix("custom.") ? .product : .palette)
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

extension MyLookDraft {
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
