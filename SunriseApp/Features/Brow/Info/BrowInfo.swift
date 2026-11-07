import Foundation

extension ToolInfo {
    /// Brows: the look and kit for the guided flow. Sample wording (Phase 0), to be replaced by the brow owner.
    static func brow(_ handoff: TutorialHandoff) -> ToolInfo {
        ToolInfo(
            tool: .eyebrow,
            lookName: handoff.browOverlay?.title ?? "Brows",
            lookDescription: "Sample: your own brows, filled and shaped to the brow you picked.",
            tools: [
                Item(name: "Spoolie", detail: "A spiral brush that combs the hairs up.",
                     alternative: "A clean, old mascara wand", symbol: "comb"),
                Item(name: "Angled brush", detail: "Thin and slanted, for powder or pomade.",
                     alternative: nil, symbol: "paintbrush.pointed", required: false)
            ],
            products: [
                Item(name: "Brow pencil", detail: "A shade close to your hair, or one lighter.",
                     alternative: "Matte eyeshadow on the angled brush", symbol: "pencil", showsShade: true),
                Item(name: "Brow gel", detail: "Keeps the hairs in place at the end.",
                     alternative: "A little hair gel on the spoolie", symbol: "drop", required: false)
            ],
            minutes: 5)
    }
}
