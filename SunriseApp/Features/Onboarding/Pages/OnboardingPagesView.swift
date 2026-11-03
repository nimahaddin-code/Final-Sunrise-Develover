import SwiftUI

/// The two onboarding pages after the splash. Placeholder until they are designed.
struct OnboardingPagesView: View {
    let onFinish: () -> Void
    @State private var page = 0
    static let pageCount = 2

    var body: some View {
        FlowPlaceholder(title: "Onboarding \(page + 1) of \(Self.pageCount)", owner: "Khalish",
                        note: "What dandan does, before the compact opens.",
                        buttonTitle: "Next", action: next,
                        onBack: page > 0 ? { page -= 1 } : nil)
    }

    private func next() {
        if page + 1 < Self.pageCount { page += 1 } else { onFinish() }
    }
}
