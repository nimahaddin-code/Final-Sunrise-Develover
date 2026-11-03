import SwiftUI

/// The compact opens, then zooms into its mirror, which becomes the Try On camera. Placeholder until it is designed.
struct CompactOpeningView: View {
    let onFinish: () -> Void

    var body: some View {
        FlowPlaceholder(title: "Compact opening", owner: "Khalish",
                        note: "A compact opens, then zooms into the mirror, which becomes the camera.",
                        buttonTitle: "Open camera", action: onFinish)
    }
}
