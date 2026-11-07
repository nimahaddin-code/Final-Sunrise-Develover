import SwiftUI

/// Brows on the shared Try On screen: the brow picture row and the brow debug menu.
struct BrowTryOnFeature: TryOnFeature {
    func lookPicker(home: TryOnHomeModel) -> AnyView {
        AnyView(BrowOverlayPicker(overlays: BrowOverlay.all, selected: home.browOverlay, onSelect: home.choose(browOverlay:)))
    }

    func debugMenu() -> AnyView? { AnyView(BrowDebugMenu()) }
}
