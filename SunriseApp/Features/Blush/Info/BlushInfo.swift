import Foundation

extension ToolInfo {
    /// Blush: the look and kit for the guided flow. One kit for every look; the description follows the look.
    static func blush(_ handoff: TutorialHandoff) -> ToolInfo {
        ToolInfo(
            tool: .blush,
            lookName: handoff.blushStyle?.title ?? String(localized: "Blush"),
            lookDescription: blushDescription(handoff.blushStyle),
            tools: [
                Item(name: String(localized: "Fingertips"),
                     detail: String(localized: "Your ring finger dabs cream blush on gently."),
                     alternative: String(localized: "A soft blush brush"), symbol: "hand.point.up.left"),
                Item(name: String(localized: "Makeup sponge"),
                     detail: String(localized: "Dampen it, then press over the edges to blend them out."),
                     alternative: String(localized: "A clean brush"), symbol: "oval.portrait",
                     required: false, imageName: "kit-blush-sponge")
            ],
            products: [
                Item(name: String(localized: "Cream or liquid blush"),
                     detail: String(localized: "Close to the shade you chose. Cream melts into skin when you dab it."),
                     alternative: String(localized: "Powder blush, or a lip tint dabbed on lightly"),
                     symbol: "circle.lefthalf.filled", imageName: "kit-blush-blush", showsShade: true),
                Item(name: String(localized: "Loose powder"),
                     detail: String(localized: "A light layer on top helps the blush last longer."),
                     alternative: nil, symbol: "circle.dotted", required: false, imageName: "kit-blush-powder")
            ],
            minutes: 1)
    }

    /// What the look gives and where it sits, for a beginner.
    private static func blushDescription(_ style: BlushPlacementStyle?) -> String {
        switch style {
        case .youthful:
            String(localized: "A fresh, rosy flush on the apples of your cheeks that makes your face look softer and younger.")
        case .sunkissed:
            String(localized: "A warm wash across both cheeks and the top of your nose, like you just came back from the sun.")
        case .lifted:
            String(localized: "Colour swept from the outer cheek up toward your temples, so your face looks lifted and more defined.")
        case .cheekboneLook:
            String(localized: "A soft band along your cheekbones, angled toward the temples, so your cheekbones stand out.")
        case .appleLook:
            String(localized: "A round, rosy patch on the apples of your cheeks, the spot that lifts when you smile.")
        case .softSweep:
            String(localized: "A soft oval of colour across the middle of your cheeks, blended outward for an easy, natural flush.")
        default:
            String(localized: "A soft wash of colour on your cheeks, blended out so no edge shows.")
        }
    }
}
