import SwiftUI

@main struct SunriseApp: App {
    private let container = AppContainer.scaffold()
    var body: some Scene {
        WindowGroup { AppRootView(container: container).tint(AppColors.rose) }
    }
}
