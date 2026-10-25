import SwiftUI

/// Edits the scans exported from the iPhone app's Scan Debug tab. It has no camera or scanning: it only opens `.sunrisescan`
/// files (AirDrop them over), lets you correct the face and eye points with the mouse, and saves raw and corrected point files.
@main struct SunriseDebugMacApp: App {
    @StateObject private var library = ScanLibrary()

    var body: some Scene {
        Window("Sunrise Scan Editor", id: "main") {
            ContentView(library: library)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { library.open([$0]) }
        }
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
