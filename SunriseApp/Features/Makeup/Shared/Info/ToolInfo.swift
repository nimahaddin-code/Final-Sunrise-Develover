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
        /// SF Symbol shown next to it.
        let symbol: String
        var id: String { name }
    }

    let tool: TryOnTool
    /// The look chosen on Try On, e.g. "Sunkissed".
    let lookName: String
    /// One or two sentences on what the look is, for the comparison page.
    let lookDescription: String
    let tools: [Item]
    let products: [Item]
    var id: TryOnTool { tool }

    /// The tool's info for the look in this handoff.
    static func of(_ tool: TryOnTool, handoff: TutorialHandoff) -> ToolInfo {
        switch tool {
        case .blush: blush(handoff)
        case .eyebrow: brow(handoff)
        case .eyeliner: eyeliner(handoff)
        }
    }

    /// One per tool that had makeup on when Try On was left, in Try On's tool order.
    static func chosen(in handoff: TutorialHandoff) -> [ToolInfo] {
        TryOnTool.allCases.filter(handoff.enabled.contains).map { of($0, handoff: handoff) }
    }
}
