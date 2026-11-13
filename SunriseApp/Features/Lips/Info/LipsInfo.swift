import Foundation

extension ToolInfo {
    /// Lips: the look and kit for the guided flow. Sample wording, like the eyeliner's, to be replaced by the lips owner.
    static func lips(_ handoff: TutorialHandoff) -> ToolInfo {
        ToolInfo(
            tool: .lips,
            lookName: handoff.lipStyle.title,
            lookDescription: "Sample: lipstick in the shape you picked, following your own lips.",
            tools: [
                Item(name: "Lip liner", detail: "Draws the edge before you fill in.",
                     alternative: "The edge of your lipstick", symbol: "pencil", required: false)
            ],
            products: [
                Item(name: "Lipstick", detail: "A bullet or a liquid one.",
                     alternative: "A lip tint", symbol: "mouth.fill", showsShade: true),
                Item(name: "Micellar water", detail: "A drop on a cotton bud tidies the edge.",
                     alternative: "Any makeup remover", symbol: "drop")
            ],
            minutes: 3)
    }
}
