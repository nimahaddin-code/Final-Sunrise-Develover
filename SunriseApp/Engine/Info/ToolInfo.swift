import Foundation

/// What one makeup tool hands to the shared screens of the guided flow (comparison, preparation, feedback): the look that
/// was chosen on Try On, and what to have ready. Each tool fills its own in `Makeup/<Tool>/Info/`; the shared screens only
/// read it, so nobody has to edit another tool's file.
struct ToolInfo: Identifiable {
    /// Something to have ready: a tool (spoolie, brush) or a product (pencil, blush), and what to use without it.
    struct Item: Identifiable, Hashable {
        let name: String
        let detail: String
        /// What to use if she does not have it; nil when there is no easy stand-in.
        let alternative: String?
        /// SF Symbol shown next to it, until there is a picture.
        let symbol: String
        /// False: nice to have ("if you have one"); the preparation page can list these apart.
        var required = true
        /// A picture in Assets.xcassets (`tool-…`, `product-…`) shown instead of the symbol; nil until there is one.
        var imageName: String? = nil
        /// Products only: the card shows the shade chosen on Try On.
        var showsShade = false
        var id: String { name }
    }

    let tool: TryOnTool
    /// The look chosen on Try On, e.g. "Sunkissed".
    let lookName: String
    /// One or two sentences on what the look is, for the comparison page.
    let lookDescription: String
    let tools: [Item]
    let products: [Item]
    /// About how long the look takes, in minutes, for the comparison page.
    let minutes: Int
    var id: TryOnTool { tool }

    /// The tool's info for the look in this handoff.
    static func of(_ tool: TryOnTool, handoff: TutorialHandoff) -> ToolInfo {
        switch tool {
        case .blush: blush(handoff)
        case .eyebrow: brow(handoff)
        case .eyeliner: eyeliner(handoff)
        case .lips: lips(handoff)
        }
    }

    /// One per tool that had makeup on when Try On was left, in Try On's tool order.
    static func chosen(in handoff: TutorialHandoff) -> [ToolInfo] {
        TryOnTool.allCases.filter(handoff.enabled.contains).map { of($0, handoff: handoff) }
    }
}
