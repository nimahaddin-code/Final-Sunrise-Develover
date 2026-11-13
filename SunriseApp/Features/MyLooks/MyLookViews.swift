// -Nimah: My Looks on screen: the row of saved looks on the home screen (newest first; long-press to rename or delete)
// and a saved look's detail, which is the feedback screen read only (`FeedbackView` with `SavedLookActions`).
import SwiftUI
import UIKit

// MARK: Home row

/// "My Looks" under the tool cards: one card per saved look, or a card that invites the first one.
struct MyLooksSection: View {
    let store: MyLookStore
    let onOpen: (UUID) -> Void
    @State private var looks: [MyLook] = []
    @State private var renaming: MyLook?
    @State private var newTitle = ""
    @State private var deleting: MyLook?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Looks")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.onboardingInk)
                .padding(.horizontal, AppSpacing.large)
                .accessibilityAddTraits(.isHeader)
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
