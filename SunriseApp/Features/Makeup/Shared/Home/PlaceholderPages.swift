import SwiftUI

/// A blank page with a title, used until the design team delivers the real screen.
struct BlankPageView: View {
    let title: LocalizedStringKey

    var body: some View {
        AppColors.screen
            .ignoresSafeArea()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppColors.snow)
    }
}
