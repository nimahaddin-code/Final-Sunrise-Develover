# Kontrak integrasi

Kontrak berada di `Core/Services/Contracts`. Semua Sendable; fungsi async dapat dipanggil dari ViewModel MainActor. Implementasi nyata bertanggung jawab mengisolasi state mutable dan pekerjaan berat. Framework UI/AR tidak boleh bocor ke kontrak domain.

| Kontrak | Pemilik | Input → output | Error / cancellation | Mock | Konsumen |
| --- | --- | --- | --- | --- | --- |
| ReferenceCatalogProviding.references | Katalog | Tidak ada → array MakeupReference, ID stabil | throws; ViewModel mengubah error ke failed dan CancellationError ke idle | MockReferenceCatalog (data configurable, default 4 sample) | ReferenceCatalogViewModel; detail menerima selected reference |
| FaceTrackingAvailabilityChecking.availability | Kalibrasi/AR | Tidak ada → notChecked/supported/unsupported(reason) | Nonthrowing; belum cek harus tetap notChecked. Tidak mewakili permission/session state | MockFaceTrackingChecker (default notChecked) | FaceCalibrationViewModel; nanti fallback live guide |
| SavedLooksStoring.list | Comparison/Saved | Tidak ada → metadata hasil | throws; ViewModel menangani failed/cancellation | MockSavedLooksStore (default 1 metadata berlabel sample) | SavedLooksViewModel |
| SavedLooksStoring.save | Comparison/Saved | SavedLookMetadata → Void hanya jika benar-benar tersimpan | Mock selalu throws SavedLooksError.notImplemented; error I/O riil ditentukan pada milestone persistence | MockSavedLooksStore, tidak mengubah koleksi | Belum dipanggil UI; Save disabled. Test memverifikasi penolakan |

## Model bersama

- MakeupReference: String ID stabil, nama, ringkasan. Konten saat ini sample.
- Tutorial: referenceID, urutan TutorialStep. TutorialStep adalah enum lima elemen dengan ID rawValue stabil.
- SavedLookMetadata: String ID stabil, referenceID, Date. Tidak membawa foto atau path disk.
- FaceTrackingAvailability: status kapabilitas saja; supported tidak berarti wajah terdeteksi.

Error katalog/saved saat ini dipetakan ke pesan UI generik; detail logging tanpa data pribadi bisa ditambahkan saat ada layanan nyata. Error unsupported bukan exception; tampilkan fallback. Mock error lebih lanjut dapat dibuat dalam test support.

## Batas AR yang sengaja belum dikunci

Belum ada protocol rendering atau FaceSessionManager. Tim AR terlebih dahulu membuktikan tracking blush pada iPhone. Pisahkan lifecycle session, permission, tracking status, dan rendering. Tetapkan kontrak session setelah spike menemukan kebutuhan nyata; hindari mendesain semua overlay dari awal.

Wajib pada PR AR:

- Check ARFaceTrackingConfiguration.isSupported sebelum sesi dijalankan.
- Handle permission, denial/Settings, session failure, interruption, tracking loss, background pause/resume.
- Mesh/anchor benar-benar mengikuti wajah dan deformasi; bukan gambar di screen coordinates.
- Kalibrasi hanya mengukur readiness/stabilitas, bukan analisis bentuk wajah.
- Fallback manual tetap dapat dijalankan.
- Blush satu-satunya target overlay awal; langkah lainnya manual.
- Jangan persist mesh atau kirim foto ke server tanpa kebutuhan dan keputusan produk.

## Batas media yang perlu keputusan sebelum implementasi

Import reference hanya untuk inspirasi; tidak otomatis menjadi tutorial. Proposal berikutnya harus menentukan owned media ID, format thumbnail, cancellation, batas ukuran gambar, dan cleanup lifecycle. Comparison harus memakai dua capture nyata yang dapat dibedakan, tanpa scoring. Kontrak metadata `save` belum cukup untuk media: sepakati transaksi metadata+file, deletion, migration, dan error sebelum mengaktifkan Save. Tidak ada API palsu yang mengaku sudah menyimpan foto.

## Proses perubahan kontrak

Buat PR kontrak dengan contoh input/output dan error. Tech lead serta konsumen memberi review, lalu update mock, test, docs, dan composition root dalam satu rangkaian yang dapat dibuild. Jangan mengganti mock default menjadi service produksi tanpa memeriksa efek ke semua layar.
