import SwiftUI

struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: "tray") } description: { Text(message) }
    }
}
