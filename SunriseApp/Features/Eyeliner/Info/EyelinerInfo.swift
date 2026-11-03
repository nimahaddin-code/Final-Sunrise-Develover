import Foundation

extension ToolInfo {
    /// Eyeliner: the look and kit for the guided flow. Sample wording (Phase 0), to be replaced by the eyeliner owner.
    static func eyeliner(_ handoff: TutorialHandoff) -> ToolInfo {
        ToolInfo(
            tool: .eyeliner,
            lookName: String(localized: handoff.linerLook.title),
            lookDescription: "Sample: a line along the lashes that follows the shape you picked.",
            tools: [
                Item(name: "Cotton bud", detail: "To tidy a line that slipped.",
                     alternative: "A folded tissue", symbol: "circle.dotted")
            ],
            products: [
                Item(name: "Eyeliner pen", detail: "A felt tip is the easiest to start with.",
                     alternative: "A soft eyeliner pencil", symbol: "pencil.tip", showsShade: true),
                Item(name: "Micellar water", detail: "A drop on the cotton bud wipes mistakes away.",
                     alternative: "Any makeup remover", symbol: "drop")
            ],
            minutes: 5)
    }
}
