// -Nimah: My Looks on screen: the row of saved looks on the home screen (newest first; long-press to rename or delete)
// and a saved look's detail, which is the feedback screen read only (`FeedbackView` with `SavedLookActions`).
import SwiftUI
import UIKit

// MARK: Home row

/// "My Looks" under the tool cards: one card per saved look, or a card that invites the first one.
struct MyLooksSection: View {
    let store: MyLookStore
    let onOpen: (UUID) -> Void
    /// Opens the My Looks page.
    var onSeeAll: () -> Void = {}
    @State private var looks: [MyLook] = []
    @State private var renaming: MyLook?
    @State private var newTitle = ""
    @State private var deleting: MyLook?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Looks")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.dandanPink)
            }
            .padding(.horizontal, AppSpacing.large)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if looks.isEmpty {
                        MyLookEmptyCard()
                    }
                    ForEach(looks) { look in
                        Button { onOpen(look.id) } label: { MyLookCard(look: look, store: store) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { newTitle = look.title; renaming = look } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = look } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .padding(.horizontal, AppSpacing.large)
            }
        }
        .task { await reload() }
        .onAppear { Task { await reload() } }
        .alert("Rename look", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Look name", text: $newTitle)
            Button("Save") {
                guard let look = renaming else { return }
                Task { _ = try? await store.rename(look.id, to: newTitle); await reload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to 30 characters.")
        }
        .confirmationDialog("Delete this look?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { look in
            Button("Delete", role: .destructive) { Task { try? await store.delete(look.id); await reload() } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The photos and the result will be removed from your phone.")
        }
    }

    private func reload() async { looks = await store.all() }
}

/// No look saved yet.
private struct MyLookEmptyCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.dandanPink)
                .frame(width: 56, height: 56)
                .background(AppColors.dandanPink.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text("Your first look will show up here. Try one!")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.onboardingInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One saved look: the result photo (the tool's area), title, tool and date, and the score with which way it went.
struct MyLookCard: View {
    let look: MyLook
    let store: MyLookStore
    @State private var thumbnail: UIImage?

    private var tool: TryOnTool? { TryOnTool(storageKey: look.tool) }

    /// Up or down against the attempt before, when there was one.
    static func trend(_ look: MyLook) -> Int {
        guard let now = look.score.overall, let before = look.previousScores.last?.overall else { return 0 }
        return now > before + 0.005 ? 1 : now < before - 0.005 ? -1 : 0
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color(white: 0.92)
                if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(look.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.onboardingInk)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let tool { Image(systemName: tool.symbol).font(.system(size: 11)) }
                    Text(look.updatedAt, format: .relative(presentation: .named))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.onboardingBody)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let score = look.score.overall {
                VStack(spacing: 2) {
                    MyLookScoreRing(score: score)
                    switch Self.trend(look) {
                    case 1: Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                    case -1: Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundStyle(AppColors.dandanPink)
                    default: EmptyView()
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: look.updatedAt) { await loadThumbnail() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(Text("Opens the result"))
    }

    private var accessibilityText: Text {
        let toolName = tool.map { String(localized: $0.category.title) } ?? ""
        let date = look.updatedAt.formatted(.relative(presentation: .named))
        if let score = look.score.overall {
            return Text("\(look.title), \(toolName), score \(Int((score * 100).rounded())) percent, \(date)")
        }
        return Text("\(look.title), \(toolName), \(date)")
    }

    private func loadThumbnail() async {
        guard let data = await store.photo(look, .result), let image = UIImage(data: data) else { thumbnail = nil; return }
        let area = look.photosCropped ? image : (tool.flatMap { MyLookFeedback.focused(image, tool: $0) } ?? image)
        thumbnail = await area.byPreparingThumbnail(ofSize: CGSize(width: 168, height: 168 * area.size.height / max(area.size.width, 1)))
            ?? area
    }
}

/// The small score ring of a card.
struct MyLookScoreRing: View {
    let score: Double

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.dandanPink.opacity(0.18), lineWidth: 4)
            Circle().trim(from: 0, to: score)
                .stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(Int((score * 100).rounded()))")
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(AppColors.onboardingInk)
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: Detail

/// A saved look, read only: its photos and feedback, Try again, rename and delete.
struct MyLookDetailView: View {
    let id: UUID
    let store: MyLookStore
    /// Try again with this look: its expected photo and measured target when saved (nil: start from Try On).
    let onRetry: (MyLook, UIImage?, FaceScan?) -> Void
    let onDeleted: () -> Void
    let onBack: () -> Void

    @StateObject private var photos = MakeupFlowStore()
    @State private var look: MyLook?
    @State private var feedback: MakeupFeedback?
    @State private var missing = false

    var body: some View {
        Group {
            if let look, let feedback, let handoff = MyLookFeedback.handoff(for: look) {
                FeedbackView(handoff: handoff, store: photos, provider: FixedFeedbackProvider(feedback: feedback),
                             saved: SavedLookActions(title: look.title, photosCropped: look.photosCropped,
                                                     onRetry: retry, onRename: rename, onDelete: delete),
                             onBackToTutorial: {}, onDone: onBack)
            } else if missing {
                VStack(spacing: AppSpacing.medium) {
                    Text("This look is no longer saved.").font(.title3.weight(.semibold))
                    Button("Back", action: onBack).buttonStyle(.borderedProminent).tint(AppColors.buttonInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { OnboardingGlow().ignoresSafeArea() }
                .toolbar(.hidden, for: .navigationBar)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { OnboardingGlow().ignoresSafeArea() }
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .navigationBarBackButtonHidden()
        .task { await load() }
    }

    private func load() async {
        guard let saved = await store.get(id) else { missing = true; return }
        func image(_ photo: MyLookStore.Photo) async -> UIImage? { await store.photo(saved, photo).flatMap(UIImage.init(data:)) }
        photos.desired = await image(.expected)
        photos.result = await image(.result)
        photos.alignedResult = await image(.compare)
        feedback = MyLookFeedback.feedback(for: saved, database: FeedbackDatabase.load())
        look = saved
    }

    private func retry() {
        guard let look else { return }
        Task {
            let target = await store.target(look)
            onRetry(look, photos.desired, target)
        }
    }

    private func rename(_ title: String) {
        Task { if let renamed = try? await store.rename(id, to: title) { look = renamed } }
    }

    private func delete() {
        Task {
            try? await store.delete(id)
            onDeleted()
        }
    }
}

/// Hands back a feedback that is already made (a saved look's), with no loading time.
struct FixedFeedbackProvider: MakeupFeedbackProviding {
    let feedback: MakeupFeedback

    func feedback(for request: MakeupFeedbackRequest, progress: @escaping @MainActor @Sendable (Double) -> Void) async -> MakeupFeedback {
        await progress(1)
        return feedback
    }
}

// MARK: My Looks page

/// -Nimah: the My Looks page (design "My looks"): All / Favorites, a two-column grid of saved looks (result photo, score,
/// heart, the look's icon, title, shade and strength), long-press for Favourite, Rename, Redo This Look and Delete, the
/// pencil to pick several looks and delete them, and an empty state for each filter.
struct MyLooksPage: View {
    let store: MyLookStore
    let onBack: () -> Void
    let onOpen: (UUID) -> Void
    let onRedo: (UUID) -> Void
    let onFindLook: () -> Void

    enum Filter { case all, favorites }

    @State private var looks: [MyLook] = []
    @State private var loaded = false
    @State private var filter = Filter.all
    @State private var editing = false
    @State private var chosen: Set<UUID> = []
    @State private var renaming: MyLook?
    @State private var newTitle = ""
    @State private var deleting: [MyLook] = []

    private var favorites: [MyLook] { looks.filter(\.isFavorite) }
    private var shown: [MyLook] { filter == .all ? looks : favorites }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar
            Text("My looks")
                .font(.system(size: 34, weight: .black)).fontWidth(.expanded)
                .foregroundStyle(AppColors.onboardingInk)
                .accessibilityAddTraits(.isHeader)
            if !looks.isEmpty { filterBar }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { OnboardingGlow().ignoresSafeArea() }
        .safeAreaInset(edge: .bottom) { if editing && !chosen.isEmpty { deleteBar } }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .task { await reload() }
        .onAppear { Task { await reload() } }
        .alert("Rename look", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Look name", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let look = renaming else { return }
                Task { _ = try? await store.rename(look.id, to: newTitle); await reload() }
            }
        } message: {
            Text("Choose a name you'll remember.")
        }
        .alert(deleting.count > 1 ? "Delete \(deleting.count) looks?" : "Delete this look?",
               isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button(deleting.count > 1 ? "Delete Looks" : "Delete Look", role: .destructive) {
                let ids = deleting.map(\.id)
                Task {
                    for id in ids { try? await store.delete(id) }
                    chosen.subtract(ids)
                    if chosen.isEmpty { editing = false }
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleting.count > 1 ? "Their photos and scores will be removed from this phone. You can't undo this."
                                    : "Its photo and score will be removed from this phone. You can't undo this.")
        }
    }

    private var topBar: some View {
        HStack {
            roundButton(symbol: "chevron.left", label: "Back", action: onBack)
            Spacer()
            if !looks.isEmpty {
                roundButton(symbol: editing ? "checkmark" : "pencil", label: editing ? "Done" : "Select looks") {
                    withAnimation(.snappy) { editing.toggle(); chosen = [] }
                }
            }
        }
        .padding(.top, AppSpacing.small)
    }

    private func roundButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.onboardingInk)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// All (n) / Favorites (n), a white capsule on the chosen one.
    private var filterBar: some View {
        HStack(spacing: 0) {
            segment(.all, Text("All (\(looks.count))"))
            segment(.favorites, favorites.isEmpty ? Text("Favorites") : Text("Favorites (\(favorites.count))"))
        }
        .padding(3)
        .background(.black.opacity(0.06), in: Capsule())
    }

    private func segment(_ value: Filter, _ label: Text) -> some View {
        Button { withAnimation(.snappy) { filter = value } } label: {
            label
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.onboardingInk)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background {
                    if filter == value {
                        Capsule().fill(.white).shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == value ? .isSelected : [])
    }

    @ViewBuilder private var content: some View {
        if !loaded {
            ProgressView().padding(.top, 80)
        } else if looks.isEmpty {
            emptyAll
        } else if shown.isEmpty {
            emptyFavorites
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(shown) { look in tile(look) }
                }
                .padding(.top, 4)
                .padding(.bottom, AppSpacing.large)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tile(_ look: MyLook) -> some View {
        Button {
            if editing {
                if chosen.contains(look.id) { chosen.remove(look.id) } else { chosen.insert(look.id) }
            } else {
                onOpen(look.id)
            }
        } label: {
            MyLookTile(look: look, store: store, editing: editing, chosen: chosen.contains(look.id)) {
                Task { _ = try? await store.setFavorite(look.id, !look.isFavorite); await reload() }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !editing {
                Button { Task { _ = try? await store.setFavorite(look.id, !look.isFavorite); await reload() } } label: {
                    Label(look.isFavorite ? "Unfavourite" : "Favourite", systemImage: look.isFavorite ? "heart.fill" : "heart")
                }
                Button { newTitle = look.title; renaming = look } label: { Label("Rename", systemImage: "pencil") }
                Button { onRedo(look.id) } label: { Label("Redo This Look", systemImage: "arrow.clockwise") }
                Divider()
                Button(role: .destructive) { deleting = [look] } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private var deleteBar: some View {
        Button(role: .destructive) { deleting = looks.filter { chosen.contains($0.id) } } label: {
            Text("Delete (\(chosen.count))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.red, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, AppSpacing.small)
    }

    /// No look saved yet.
    private var emptyAll: some View {
        VStack(spacing: 10) {
            HStack(spacing: -18) {
                MyLookIcon(tool: .eyebrow, lookId: "").frame(width: 64, height: 64)
                MyLookIcon(tool: .blush, lookId: BlushPlacementStyle.sunkissed.rawValue).frame(width: 76, height: 76).zIndex(1)
                MyLookIcon(tool: .eyeliner, lookId: LinerLook.cat.rawValue).frame(width: 64, height: 64)
            }
            .accessibilityHidden(true)
            Text("No looks yet").font(.system(size: 20, weight: .bold)).foregroundStyle(AppColors.onboardingInk)
            Text("Complete your first tutorial to save your look here.")
                .font(.system(size: 15)).foregroundStyle(AppColors.onboardingBody).multilineTextAlignment(.center)
            Button(action: onFindLook) {
                Text("Find a Look")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 44).frame(minHeight: 52)
                    .background(AppColors.buttonInk, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    /// Looks saved, none with a heart.
    private var emptyFavorites: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppColors.dandanPink)
                .frame(width: 72, height: 72)
                .background(.white, in: Circle())
                .accessibilityHidden(true)
            Text("No favourites yet").font(.system(size: 20, weight: .bold)).foregroundStyle(AppColors.onboardingInk)
            Text("Tap ♡ on a look you love to keep it here.")
                .font(.system(size: 15)).foregroundStyle(AppColors.onboardingBody).multilineTextAlignment(.center)
            Button("See All Looks") { withAnimation(.snappy) { filter = .all } }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.dandanPink)
                .padding(.top, 4)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func reload() async {
        looks = await store.all()
        loaded = true
        chosen = chosen.intersection(looks.map(\.id))
    }
}

/// One look in the grid: the result photo with the score and the heart, then its icon, title, shade and strength.
struct MyLookTile: View {
    let look: MyLook
    let store: MyLookStore
    var editing = false
    var chosen = false
    let onFavorite: () -> Void
    @State private var photo: UIImage?

    private var tool: TryOnTool? { TryOnTool(storageKey: look.tool) }

    /// "#RRGGBB" to a colour.
    static func color(_ hex: String?) -> Color? {
        guard let hex, hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color(white: 0.9)
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { if let photo { Image(uiImage: photo).resizable().scaledToFill() } }
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let score = look.score.overall { MyLookScoreBadge(score: score).padding(8) }
                }
                .overlay(alignment: .topTrailing) { corner.padding(8) }
            HStack(spacing: 8) {
                if let tool { MyLookIcon(tool: tool, lookId: look.lookId).frame(width: 36, height: 36) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.onboardingInk)
                        .lineLimit(1)
                    if let intensity = look.intensity {
                        HStack(spacing: 4) {
                            Circle().fill(Self.color(look.shades.first?.hex) ?? AppColors.dandanPink).frame(width: 8, height: 8)
                            Text("\(Int((intensity * 100).rounded()))% intensity")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.onboardingBody)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if chosen { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.dandanPink, lineWidth: 3) }
        }
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        .task(id: look.updatedAt) { await loadPhoto() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(look.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The heart, or a tick circle while picking looks to delete.
    @ViewBuilder private var corner: some View {
        if editing {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(chosen ? AppColors.dandanPink : .white, chosen ? .white : .clear)
                .shadow(color: .black.opacity(0.25), radius: 3)
        } else {
            Button(action: onFavorite) {
                Image(systemName: look.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(look.isFavorite ? AppColors.dandanPink : .white)
                    .frame(width: 32, height: 32)
                    .background(look.isFavorite ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.35)), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(look.isFavorite ? "Unfavourite" : "Favourite")
        }
    }

    private var accessibilityValue: Text {
        let score = look.score.overall.map { Int(($0 * 100).rounded()) }
        let intensity = look.intensity.map { Int(($0 * 100).rounded()) } ?? 0
        if let score { return Text("Score \(score), \(intensity)% intensity") }
        return Text("\(intensity)% intensity")
    }

    private func loadPhoto() async {
        guard let data = await store.photo(look, .result), let image = UIImage(data: data) else { photo = nil; return }
        photo = await image.byPreparingThumbnail(ofSize: CGSize(width: 360, height: 360 * image.size.height / max(image.size.width, 1)))
            ?? image
    }
}

/// The score in a dark circle with a pink ring, over the photo.
struct MyLookScoreBadge: View {
    let score: Double

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.55))
            Circle().stroke(.white.opacity(0.25), lineWidth: 3).padding(2)
            Circle().trim(from: 0, to: score)
                .stroke(AppColors.dandanPink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            Text(verbatim: "\(Int((score * 100).rounded()))")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

/// The look's own icon, as on Try On, in a round skin-coloured disc.
struct MyLookIcon: View {
    let tool: TryOnTool
    let lookId: String

    var body: some View {
        ZStack {
            Circle().fill(AppColors.browCanvas)
            switch tool {
            case .blush:
                BlushStyleIcon(look: BlushPlacementStyle(rawValue: lookId) ?? .sunkissed)
            case .eyebrow:
                BrowStyleIcon(assetName: (BrowOverlay.all.first { $0.id == lookId } ?? BrowOverlay.all.first)?.assetName ?? "")
            case .eyeliner:
                GeometryReader { proxy in
                    LinerLookThumbnail(look: LinerLook(rawValue: lookId) ?? .classic, ink: AppColors.onboardingInk)
                        .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.52)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            case .lips:
                LipStyleIcon(style: LipStyle(rawValue: lookId) ?? .natural)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}
