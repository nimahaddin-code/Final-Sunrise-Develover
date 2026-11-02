// -Nimah: ReferenceCatalogView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct ReferenceCatalogView: View {
    @StateObject private var model: ReferenceCatalogViewModel
    init(service: any ReferenceCatalogProviding) { _model = StateObject(wrappedValue: ReferenceCatalogViewModel(service: service)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                Text("A little guidance. A glow that's yours.").font(AppTypography.title)
                // -Nimah: Pintu masuk modul alis terpisah dari tutorial makeup lama.
                NavigationLink(value:AppRoute.eyebrowGuide) {
                    HStack(spacing:AppSpacing.medium) {
                        Image(systemName:"eyebrow").font(.title2)
                        VStack(alignment:.leading) {
                            Text("Brow & Blush Studio").font(.headline)
                            Text("Face shape · placement preferences · live preview").font(.caption)
                        }
                        Spacer(); Image(systemName:"chevron.right")
                    }.padding(AppSpacing.large).background(AppColors.card,in:RoundedRectangle(cornerRadius:AppSpacing.cornerRadius))
                }.foregroundStyle(AppColors.rose)
                Text("THE LOOK EDIT").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(AppColors.rose)
                switch model.state {
                case .idle, .loading: ProgressView("Loading references")
                case .failed:
                    Text("References could not be loaded.")
                    Button("Retry") { Task { await model.load() } }
                case .loaded(let items):
                    if items.isEmpty { EmptyStateView(title: "No references", message: "There are no references to show.") }
                    ForEach(items) { reference in
                        NavigationLink(value: AppRoute.referenceDetail(reference)) {
                            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                                LookArtwork(referenceID: reference.id)
                                Text(reference.name).font(AppTypography.heading)
                                Text(reference.summary).font(.subheadline).foregroundStyle(AppColors.subtle)
                            }.padding(AppSpacing.medium).background(AppColors.card, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                        }.foregroundStyle(AppColors.ink)
                    }
                }
                NavigationLink(value: AppRoute.referenceImport) { Label("Use my own inspiration", systemImage: "photo.on.rectangle.angled").font(.headline) }
                Text("Artwork is illustrative. Uploaded inspiration is not analyzed automatically.").font(AppTypography.caption).foregroundStyle(AppColors.subtle)
            }.padding(AppSpacing.large)
        }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("Discover").task { await model.load() }
    }
}
#Preview { NavigationStack { ReferenceCatalogView(service: MockReferenceCatalog()) } }
