import SwiftUI

/// Eyeliner on the shared Try On screen: the six liner looks as pictures, scrolling sideways; the first tile switches
/// the liner off. No debug menu.
struct EyelinerTryOnFeature: TryOnFeature {
    func lookPicker(home: TryOnHomeModel) -> AnyView {
        AnyView(
            LinerLookPicker(selected: home.isOff ? nil : home.linerLook) { look in
                if let look { home.setLinerLook(look) } else { home.turnOff() }
            }
            .disabled(!home.canTry(.eyeliner))
        )
    }

    func styleName(home: TryOnHomeModel) -> Text {
        home.isOff ? Text("None") : Text(home.linerLook.title)
    }

    func debugMenu() -> AnyView? { nil }
}
