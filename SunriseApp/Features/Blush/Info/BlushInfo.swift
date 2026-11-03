import Foundation

extension ToolInfo {
    /// Blush: the look and kit for the guided flow. Sample wording (Phase 0), to be replaced by the blush owner.
    static func blush(_ handoff: TutorialHandoff) -> ToolInfo {
        ToolInfo(
            tool: .blush,
            lookName: handoff.blushStyle?.title ?? "Blush",
            lookDescription: "Sample: a soft wash of colour on the cheeks, blended out so no edge shows.",
            tools: [
                Item(name: "Fingertips or a fluffy blush brush", detail: "Fingers for cream blush, a brush for powder.",
                     alternative: "A damp makeup sponge", symbol: "hand.point.up.left")
            ],
            products: [
                Item(name: "Blush", detail: "Cream or powder, close to the shade you chose.",
                     alternative: "A lip tint dabbed on lightly", symbol: "circle.lefthalf.filled", showsShade: true)
            ],
            minutes: 3)
    }
}
