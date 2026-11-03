import SwiftUI
import UIKit

/// The app is portrait only, except for screens that ask otherwise (the eye correction view turns landscape). The mask lives
/// here because iOS asks the app delegate which orientations are allowed.
@MainActor final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }
}

@MainActor enum ScreenOrientation {
    /// Allows only `mask` and turns the screen to it now.
    static func lock(to mask: UIInterfaceOrientationMask) {
        AppOrientationDelegate.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}
