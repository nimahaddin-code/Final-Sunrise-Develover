import SwiftUI

/// What one makeup tool adds to the shared Try On screen. The screen owns the layout (camera, top buttons, palette,
/// shades, intensity, Continue); a tool only supplies its look row and, with developer tools on, its debug menu.
@MainActor protocol TryOnFeature {
    func lookPicker(home: TryOnHomeModel) -> AnyView
    /// The chosen look's name for the top row ("None" when the tool is off).
    func styleName(home: TryOnHomeModel) -> Text
    /// What the colour sheet calls the feature: "Add your blush colour".
    var colourName: String { get }
    /// nil: the tool has no debug menu.
    func debugMenu() -> AnyView?
}

extension TryOnTool {
    /// The one place a tool is mapped to its Try On content. A new tool adds a case here and a feature in its folder.
    @MainActor var tryOnFeature: any TryOnFeature {
        switch self {
        case .blush: BlushTryOnFeature()
        case .eyeliner: EyelinerTryOnFeature()
        case .eyebrow: BrowTryOnFeature()
        case .lips: LipsTryOnFeature()
        }
    }
}
