// -Nimah: ReferenceImportView.swift — implementasi MVP SunriseApp.
import SwiftUI
import PhotosUI

struct ReferenceImportView: View {
    let checker: any FaceTrackingAvailabilityChecking
    let store: any SavedLooksStoring
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var loading = false
    @State private var error: String?
    @State private var styleID = "douyin"
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: AppSpacing.large) {
            Text("Your inspiration, your way.").font(AppTypography.title)
            Text("Choose a photo, then select a tutorial style yourself. No automatic makeup analysis is included.")
            PhotosPicker(selection: $selected, matching: .images) { Label("Choose from Photos", systemImage: "photo.badge.plus").font(.headline) }
            if loading { ProgressView("Loading photo") }
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
                Button("Remove photo") { selected = nil; self.image = nil }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Picker("Tutorial style", selection: $styleID) { ForEach(BundledReferenceCatalog.looks) { Text($0.name).tag($0.id) } }
            if let image, let reference = BundledReferenceCatalog.look(id: styleID) {
                NavigationLink {
                    MakeupSessionView(reference: reference, checker: checker, store: store, inspiration: image) { dismiss() }
                } label: { Label("Start with this inspiration", systemImage: "sparkles").font(.headline) }
            }
            Text("The reference stays in memory for this session. Only Before and After camera captures are saved when you choose Save.").font(.caption).foregroundStyle(AppColors.subtle)
        }.padding(AppSpacing.large) }.background(AppColors.background).foregroundStyle(AppColors.ink).navigationTitle("My inspiration").navigationBarTitleDisplayMode(.inline)
        // -Nimah: Task diganti saat selection berubah agar hasil foto lama tidak menimpa pilihan baru.
        .task(id: selected) {
            guard let selected else { return }
            loading = true; image = nil; error = nil
            defer { loading = false }
            do {
                guard let data = try await selected.loadTransferable(type: Data.self), data.count < 25_000_000,
                      let decoded = UIImage(data: data) else { throw SavedLooksError.invalidCapture }
                try Task.checkCancellation()
                image = decoded
            } catch is CancellationError { } catch { self.error = "Could not open this photo. Choose an image smaller than 25 MB." }
        }
    }
}
