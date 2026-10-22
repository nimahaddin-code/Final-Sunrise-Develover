// -Nimah: ComparisonView.swift — implementasi MVP SunriseApp.
import SwiftUI

struct CaptureComparisonView: View {
    let before: UIImage
    let after: UIImage
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) { photo(before, title: "Before").frame(minWidth: 135); photo(after, title: "After").frame(minWidth: 135) }
            VStack { photo(before, title: "Before"); photo(after, title: "After") }
        }
    }
    private func photo(_ image: UIImage, title: LocalizedStringKey) -> some View {
        VStack { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)); Text(title).font(.headline) }
    }
}
struct ComparisonView: View {
    let referenceID: String
    let before: UIImage
    let after: UIImage
    let store: any SavedLooksStoring
    var onFinish: () -> Void
    @State private var saving = false
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        ScrollView { VStack(spacing: AppSpacing.large) {
            Text("Your glow, captured.").font(AppTypography.title)
            CaptureComparisonView(before: before, after: after)
            Text("Actual camera captures. Different framing or lighting can affect comparison. No beauty scoring or automatic assessment.").font(.caption).foregroundStyle(AppColors.subtle)
            PrimaryButton(title: saved ? "Saved to My Looks ✓" : saving ? "Saving…" : "Save this look") { Task { await save() } }.disabled(saving || saved)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button(saved ? "Done" : "Finish without saving", action: onFinish).disabled(saving)
            Text("Saved only on this device. Delete the result from My Looks whenever you like.").font(.caption).foregroundStyle(AppColors.subtle)
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("Before & after").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(saving || saved)
    }
    @MainActor private func save() async {
        guard !saving, !saved else { return }; saving = true; error = nil
        defer { saving = false }
        do {
            guard let b = before.jpegData(compressionQuality: 0.8), let a = after.jpegData(compressionQuality: 0.8) else { throw SavedLooksError.invalidCapture }
            _ = try await store.save(referenceID: referenceID, before: b, after: a)
            saved = true
        } catch { self.error = error.localizedDescription }
    }
}
