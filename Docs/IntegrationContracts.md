# Kontrak integrasi MVP

> -Nimah · 22 October 2026: Kontrak baru FaceShapeAssessment → katalog eyebrow/blush → preview/tutorial dijelaskan di [BrowBlushPreferences](BrowBlushPreferences.md). Origin manual/analysis dibedakan; unknown tidak menghasilkan klasifikasi palsu.

> -Nimah: Acuan placement terbaru: [MakeupAccuracyPlan](MakeupAccuracyPlan.md) dan [EyelinerDeviceTesting](EyelinerDeviceTesting.md). Catatan di bawah dapat mencakup iterasi historis. Eyeliner kini strip attachment, bukan atlas; full look default OFF.

Semua service di Core Sendable; ViewModel MainActor menerima dependency via initializer. Framework rendering tetap berada di fitur LiveGuide.

| Kontrak | Live implementation | Input / output dan error |
| --- | --- | --- |
| ReferenceCatalogProviding.references | BundledReferenceCatalog | Async array empat look, ID tetap; signature throws untuk sumber lain |
| FaceTrackingAvailabilityChecking.availability | DeviceFaceTrackingChecker | Runtime ARFaceTrackingConfiguration.isSupported; Simulator unsupported; tidak meminta kamera dan tidak mengklaim tracking aktif |
| SavedLooksStoring.list | LocalSavedLooksStore actor | Metadata Codable sorted descending; corrupt file dilaporkan |
| save(referenceID:before:after:) | LocalSavedLooksStore actor | Dua Data JPEG nonempty <15MB per file → metadata UUID; directory staging dipindah atomik; errors diteruskan |
| imageData(for:kind:) | LocalSavedLooksStore actor | UUID + before/after → Data; missingCapture/invalidIdentifier/I/O error |
| delete(id:) | LocalSavedLooksStore actor | Hapus satu folder; UUID wajib; I/O error tampil di UI |
| legacy save(metadata) | Tidak dipakai oleh UI | Live menolak karena capture tidak ada; mock throws notImplemented |

Mock default media operations menolak notImplemented; fitur tidak boleh menganggap mock sebagai penyimpanan asli. Sample metadata hanya untuk preview/test, bukan koleksi pengguna live.

Session capture hanya melalui FaceCameraState di MainActor dengan snapshot ARSCNView. Tidak ada UIImage/ARFaceAnchor di shared model. FaceCameraState memiliki weak view dan callback pause yang weak terhadap coordinator/view untuk menghindari siklus retain.

ARSessionDelegate queue mengukur tracking readiness; renderer memutakhirkan mesh; MainActor mempublikasikan tracking/error. Indikator supported terpisah dari permission, anchor tracked, readiness, serta failure. Failure/retry/lifecycle harus dipertahankan ketika tim mengubah session.

Photos import memakai system picker, batas input 25MB, dan selection task cancellation. Reference hanya inspirasi lokal; user memilih style tutorial sendiri. Tidak ada analisis otomatis.

AR implementation mengikuti [Apple ARFaceTrackingConfiguration](https://developer.apple.com/documentation/arkit/arfacetrackingconfiguration) dan pola geometry pada [Tracking and visualizing faces](https://developer.apple.com/documentation/arkit/tracking-and-visualizing-faces). Simulator tidak memvalidasi tracking. Physical acceptance test wajib sebelum mengklaim placement berhasil.

## Native try-on contracts — -Nimah

FaceCameraState memegang previewMode (points+look/look/points/original), previewStrength, previewFullLook, fitReady, fitMessage, distanceMeters. Readiness tidak boleh mengaktifkan Begin sebelum fit tersedia. FaceSurfaceProfile/Baker memakai value arrays dan immutable CGImage hasil bake; tidak menyimpan geometry pengguna ke disk/server. Session generation membuang bake lama setelah restart. Live renderer dimiliki render thread, tracking/readiness dimiliki session queue, konfigurasi/pending result memakai NSLock, dan UI MainActor. Mocks tetap tidak mengakses kamera.

## Eyebrow shared-session contract — -Nimah

Jangan membuat sesi AR/AVCapture per facial region. Pakai ARFaceTrackingManager.shared dan lease aktif. Hasil asynchronous harus terikat epoch/anchor; region guide memakai triangle attachment dari snapshot frame yang sama. Lihat [EyebrowModule](EyebrowModule.md) sebelum menambahkan Lips/Nose/Cheeks.

## Saved face/eye output → try-on — -Nimah

FaceAnalysis/EyeAnalysis own initial classification; FaceShapeStore persists latest face and separate eyes. AppRootView maps face shape to MakeupFaceShape (triangle → pear) and passes analysis to Nimah studio. Saved analysis enters chooseStyle directly for a requested region, chooseRegion otherwise. Live AR/Vision alignment runs automatically, and tutorial text is not blocked by mapping readiness. Manual shape override remains possible.

MakeupPlan(scan:chosenShape:eyeScan:) and MakeupPlan(shape:eyeScan:) adapt the separate EyeShapeResult to Hanum EyeScan. Both use opening/eye width, inner-corner gap/eye width and canthal tilt degrees. Lid is mapped only from the user's explicit choice; mayBeHooded never becomes a lid diagnosis. No sample count is stored by the separate result, so the adapter uses zero (unknown, unused by planner confidence), not an invented count. Nonfinite/invalid measurements or confidence ≤ 0.1 use a neutral plan; this is a conservative prototype gate, not a measured accuracy threshold. A separate result takes precedence over old embedded face-eye measurements, including when it is unclear. Without a separate result, the old saved eye measurement remains compatible.

Hanum formulas are unchanged. Face-shape labels do not select eyeliner; eye measurements do. No eyeshadow work is included.
