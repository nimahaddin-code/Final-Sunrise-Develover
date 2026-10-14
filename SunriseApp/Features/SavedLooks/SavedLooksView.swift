import SwiftUI

struct SavedLooksView: View {
    @StateObject private var model: SavedLooksViewModel
    init(store: any SavedLooksStoring) { _model = StateObject(wrappedValue: SavedLooksViewModel(store: store)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("My Looks").font(AppTypography.title)
                Text("MOCK COLLECTION · NOT YOUR SAVED RESULTS").font(AppTypography.caption).foregroundStyle(AppColors.rose)
                switch model.state {
                case .idle, .loading: ProgressView("Loading sample entries")
                case .failed:
                    Text("Entries could not be loaded.")
                    Button("Retry") { Task { await model.load() } }
                case .loaded(let items):
                    if items.isEmpty { EmptyStateView(title: "No entries", message: "This collection is empty. Saving is not implemented.") }
                    ForEach(items) { item in
                        NavigationLink(value: AppRoute.savedLookDetail(item)) {
                            Label("Sample entry — detail scaffold", systemImage: "doc.text")
                                .padding(AppSpacing.large).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        }
                    }
                }
            }.padding(AppSpacing.large)
        }.background(AppColors.background).foregroundStyle(AppColors.ink)
        .navigationTitle("My Looks").task { await model.load() }
    }
}
