import SwiftUI

@main struct SunriseApp: App {
    @UIApplicationDelegateAdaptor(AppOrientationDelegate.self) private var orientationDelegate
    private let container = AppContainer.scaffold()
    var body: some Scene {
        WindowGroup { AppRootView(container: container).tint(AppColors.rose) }
    }
}
