import SwiftUI

/// Blush on the shared Try On screen: the blush look row and the blush debug menu.
struct BlushTryOnFeature: TryOnFeature {
    func lookPicker(home: TryOnHomeModel) -> AnyView {
        AnyView(
            BlushLookPicker(selected: home.isOff ? nil : home.blushLook) { look in
                if let look { home.choose(blush: look) } else { home.turnOff() }
            }
            .disabled(!home.canTry(.blush))
        )
    }

    func debugMenu() -> AnyView? { AnyView(BlushDebugMenu()) }
}
