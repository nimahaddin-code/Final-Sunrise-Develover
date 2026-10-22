// -Nimah: SunriseApp.swift — implementasi MVP SunriseApp.
import SwiftUI

@main struct SunriseApp: App {
    private let container = AppContainer.live()
    var body: some Scene { WindowGroup { AppRootView(container: container).tint(AppColors.rose) } }
}
