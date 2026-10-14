import SwiftUI

struct ReferenceCatalogView: View {
    @StateObject private var model: ReferenceCatalogViewModel
    init(service: any ReferenceCatalogProviding) {
        _model = StateObject(wrappedValue: ReferenceCatalogViewModel(service: service))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("A little guidance. A glow that's yours.").font(AppTypography.title)
                Text("SAMPLE CATALOG · SCAFFOLD").font(AppTypography.caption).foregroundStyle(AppColors.rose)
                switch model.state {
                case .idle, .loading: ProgressView("Loading references")
                case .failed:
                    Text("References could not be loaded.")
                    Button("Retry") { Task { await model.load() } }
                case .loaded(let references):
                    if references.isEmpty { EmptyStateView(title: "No references", message: "There are no references to show.") }
                    ForEach(references) { reference in
                        NavigationLink(value: AppRoute.referenceDetail(reference)) {
                            VStack(alignment: .leading, spacing: AppSpacing.small) {
                                Label(reference.name, systemImage: "sparkle").font(AppTypography.heading)
                                Text(reference.summary).font(AppTypography.body)
                                Text("Sample reference").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(AppSpacing.large)
                            .background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        }.foregroundStyle(AppColors.ink)
                    }
                }
                NavigationLink("Explore reference import placeholder", value: AppRoute.referenceImport)
            }.padding(AppSpacing.large)
        }
        .background(AppColors.background).foregroundStyle(AppColors.ink)
        .navigationTitle("Discover")
        .task { await model.load() }
    }
}

#Preview { NavigationStack { ReferenceCatalogView(service: MockReferenceCatalog()) } }
