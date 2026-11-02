// -Nimah: SavedLookDetailView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct SavedLookDetailView: View {
    let look: SavedLookMetadata
    let store: any SavedLooksStoring
    @Environment(\.dismiss) private var dismiss
    @State private var before: UIImage?
    @State private var after: UIImage?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmDelete = false
    var body: some View {
        ScrollView { VStack(spacing: AppSpacing.large) {
            Text(BundledReferenceCatalog.look(id: look.referenceID)?.name ?? "My look").font(AppTypography.title)
            Text(look.createdAt, style: .date).foregroundStyle(AppColors.subtle)
            if let before, let after { CaptureComparisonView(before: before, after: after) }
            else if error == nil { ProgressView("Loading photos") }
            if let error { Text(error).foregroundStyle(.red); Button("Retry loading") { Task { await load() } } }
            Button("Delete this look", role: .destructive) { confirmDelete = true }.disabled(busy)
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("Saved look").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Delete these photos from this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete look", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        }
    }
    @MainActor private func load() async {
        error = nil
        do {
            let b = try await store.imageData(for: look.id, kind: .before)
            let a = try await store.imageData(for: look.id, kind: .after)
            guard let before = UIImage(data: b), let after = UIImage(data: a) else { throw SavedLooksError.missingCapture }
            self.before = before; self.after = after
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func delete() async {
        busy = true; defer { busy = false }
        do { try await store.delete(id: look.id); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
