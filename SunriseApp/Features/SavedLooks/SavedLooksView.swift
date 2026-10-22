// -Nimah: SavedLooksView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct SavedLooksView: View {
    @StateObject private var model: SavedLooksViewModel
    let store: any SavedLooksStoring
    init(store: any SavedLooksStoring) { self.store = store; _model = StateObject(wrappedValue: SavedLooksViewModel(store: store)) }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text("Your glow journal").font(AppTypography.title)
            Text("Your captures, kept on this device.").foregroundStyle(AppColors.subtle)
            switch model.state {
            case .idle, .loading: ProgressView("Loading looks")
            case .failed:
                Text("Your saved looks could not be loaded. Your files have not been removed.")
                Button("Retry") { Task { await model.load() } }
            case .loaded(let items):
                if items.isEmpty { EmptyStateView(title: "Your first glow awaits", message: "Complete a camera tutorial and save your Before and After photos here.") }
                ForEach(items) { item in
                    NavigationLink(value: AppRoute.savedLookDetail(item)) {
                        HStack {
                            Image(systemName: "heart.fill").foregroundStyle(AppColors.rose)
                            VStack(alignment: .leading) {
                                Text(BundledReferenceCatalog.look(id: item.referenceID)?.name ?? "My look").font(.headline)
                                Text(item.createdAt, style: .date).font(.caption).foregroundStyle(AppColors.subtle)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.padding(AppSpacing.large).background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                    }.foregroundStyle(AppColors.ink)
                }
            }
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("My Looks")
        .onAppear { Task { await model.load() } }
    }
}
