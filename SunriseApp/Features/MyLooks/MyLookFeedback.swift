// -Nimah: a saved look's feedback told again from its rule ids, bands and words (`MyLook.rules`), in the app's current
// language: the same cards, fixes, notes and praise the feedback screen showed, without measuring anything.
import UIKit

enum MyLookFeedback {
    static func feedback(for look: MyLook, database: FeedbackDatabase?, language: FeedbackLanguage = .current) -> MakeupFeedback {
        let marks = look.marks.compactMap { mark -> MakeupFeedback.Mark? in
            guard let side = FeedbackSide(rawValue: mark.side) else { return nil }
            return MakeupFeedback.Mark(side: side, target: mark.target, add: mark.add, remove: mark.remove)
        }
        guard let database else {
            var plain = MakeupFeedback(score: look.score.overall, headline: "", comments: [])
            plain.marks = marks
            return plain
        }
        var composer = FeedbackComposer(database: database, language: language)
        switch TryOnTool(storageKey: look.tool) {
        case .eyebrow: composer.part = \.brow
        case .eyeliner, .lips: composer.part = \.eye
        default: break
        }
        let saidIn = look.language.flatMap(FeedbackLanguage.init(rawValue:)) ?? language

        func values(_ rule: MyLook.Rule) -> [String: String] {
            (rule.values ?? [:]).mapValues { translate($0, from: saidIn, to: language, database: database) }
        }
        func band(_ rule: MyLook.Rule) -> FeedbackBand {
            [FeedbackBand.ok, .slight, .clear, .large].first { $0.key == rule.band } ?? .slight
        }
        func message(_ rule: MyLook.Rule) -> MakeupFeedback.Item? {
            switch rule.kind ?? .fix {
            case .fix:
                let hit = FeedbackHit(rule: rule.id, band: band(rule), side: rule.side.flatMap(FeedbackSide.init(rawValue:)) ?? .both,
                                      priority: database.rule(rule.id)?.priority ?? 50, values: values(rule), size: 0, suppresses: [])
                return composer.message(for: hit)
            case .note:
                guard let capture = database.captureRule(rule.id) else { return nil }
                let text = capture.message.text(language)
                return MakeupFeedback.Item(title: text.title, say: composer.fill(text.say, values(rule)), steps: text.steps ?? [],
                                           band: band(rule), rule: rule.id, values: values(rule))
            case .praise:
                guard let tool = TryOnTool(storageKey: look.tool), let rules = database.tool(tool) else { return nil }
                return composer.praise(rule.id, tool: rules, values: values(rule))
            }
        }

        let fixes = look.rules.filter { ($0.kind ?? .fix) == .fix }
        let notes = look.rules.filter { $0.kind == .note }.compactMap(message)
        let praise = look.rules.filter { $0.kind == .praise }.compactMap(message)
        let top = fixes.filter { $0.top == true }.compactMap(message)

        let cards: [MakeupFeedback.Category] = FeedbackCategory.allCases.compactMap { card in
            let percent = card == .placement ? look.score.placement : look.score.shade
            guard let percent else { return nil }
            let own = fixes.filter { ($0.cards ?? []).contains(card.rawValue) }
            let items = own.compactMap(message)
            let label = own.first.flatMap { FeedbackNote.text(rule: $0.id, band: band($0), language: language) }
                ?? (items.first?.title ?? FeedbackNote.spotOn(language))
            return MakeupFeedback.Category(id: card.rawValue, title: card.title, symbol: card.symbol, percent: percent,
                                           label: label, items: items)
        }
        var feedback = MakeupFeedback(score: look.score.overall,
                                      headline: look.score.overall.map { composer.label(score: $0 * 100) } ?? "",
                                      comments: [], items: (top.isEmpty ? praise : top) + notes, categories: cards,
                                      summary: cards.isEmpty ? "" : FeedbackNote.summary(cards, language: language), notes: notes,
                                      placement: cards.first { $0.id == "placement" }.map { .init(value: $0.percent, note: $0.label) },
                                      shade: cards.first { $0.id == "shade" }.map { .init(value: $0.percent, note: $0.label) })
        feedback.praise = praise
        feedback.marks = marks
        return feedback
    }

    /// A word of the database's vocabulary said in another language (e.g. "outer" -> "luar"); anything else unchanged.
    static func translate(_ word: String, from: FeedbackLanguage, to: FeedbackLanguage, database: FeedbackDatabase) -> String {
        guard from != to else { return word }
        let tables: [KeyPath<FeedbackDatabase.Vocabulary, [String: String]>] =
            [\.side, \.cheek, \.brow, \.eye, \.blush_zone, \.spill_zone, \.brow_zone, \.liner_zone]
        let old = database.words(from), new = database.words(to)
        for table in tables {
            if let key = old[keyPath: table].first(where: { $0.value == word })?.key, let said = new[keyPath: table][key] { return said }
        }
        return word
    }

    /// Try On's choices again: the tool, its look, shade and strength, for the tutorial of "Try again".
    static func handoff(for look: MyLook) -> TutorialHandoff? {
        guard let tool = TryOnTool(storageKey: look.tool) else { return nil }
        var handoff = TutorialHandoff(tool: tool, shades: [:], intensities: [:], enabled: [tool])
        if let shade = look.shades.first { handoff.shades[tool] = shade.makeupShade(for: tool) }
        if let intensity = look.intensity { handoff.intensities[tool] = intensity }
        switch tool {
        case .blush: handoff.blushStyle = BlushPlacementStyle(rawValue: look.lookId)
        case .eyeliner: if let liner = LinerLook(rawValue: look.lookId) { handoff.linerLook = liner }
        case .eyebrow: handoff.browOverlay = BrowOverlay.all.first { $0.id == look.lookId }
        case .lips: if let lips = LipStyle(rawValue: look.lookId) { handoff.lipStyle = lips }
        }
        return handoff
    }

    /// The tool's area of a photo, as the feedback screen shows it: the eyes for brows and eyeliner, the lips for lips,
    /// the whole face for blush (`LookBriefView.crop`).
    static func focused(_ image: UIImage?, tool: TryOnTool) -> UIImage? {
        guard let image, tool != .blush else { return image }
        return LookBriefView.crop(image, for: tool)
    }
}
