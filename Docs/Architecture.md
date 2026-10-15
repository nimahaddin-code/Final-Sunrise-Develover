# Arsitektur MVP

Fondasi tetap SwiftUI + MVVM ringan, iOS 17+, ObservableObject/Published dan MainActor untuk UI. Satu app target, satu test target; tidak ada dependency eksternal.

## Composition

`SunriseApp → AppContainer.live() → AppRootView → feature initializer`.

Live composition memilih BundledReferenceCatalog, DeviceFaceTrackingChecker, dan LocalSavedLooksStore. Mock di PreviewSupport tidak dipakai saat run normal. AppContainer bukan service locator: fitur menerima dependency spesifik.

AppRootView menyimpan onboarding melalui AppStorage. AppNavigator memisahkan stack Discover dan My Looks. AppRoute membawa reference atau metadata; UIKit tidak masuk model domain.

## Sesi makeup

MakeupSessionView memegang satu FaceCameraState, FaceCalibrationViewModel, dan TutorialViewModel selama sesi. Komponen LiveGuideView membungkus ARSCNView; camera tetap satu selama kalibrasi dan langkah tutorial. Beralih manual menutup sesi dan membuang capture sementara. Comparison membuka sheet, menjeda kamera, dan memakai dua UIImage capture aktual; tidak ada image di route atau container.

Sesi pause saat scene tidak aktif, layar tidak terlihat, manual mode, atau comparison. Tracking loss mereset readiness; snapshot memerlukan anchor tracked yang fresh dan overlay off. ARSessionDelegate queue terpisah mengukur readiness, UI dipublikasikan melalui MainActor. SceneKit render callback memutakhirkan mesh; akses flag overlay lintas thread dilindungi NSLock. Coordinator memakai unchecked Sendable hanya untuk batas framework delegate tersebut; jangan menambah state lintas-thread tanpa isolasi.

## Mesh blush

Bobot warna dihitung dari vertex face-local awal untuk dua pipi; mask per anchor tetap dan seluruh vertex/triangle diperbarui dari geometry terbaru. Node otomatis mengikuti transform anchor. Material constant/alpha, transparan di luar pipi, single-sided, tanpa depth writes. Ini POC placement; bukan render makeup fotorealistik atau klasifikasi wajah. Penempatan dan alpha wajib diuji pada iPhone.

## Persistence

LocalSavedLooksStore adalah actor. Application Support/SunriseApp/Looks/<UUID> memuat metadata.json, before.jpg, after.jpg. Semua file ditulis di folder staging tersembunyi, kemudian folder dipindahkan ke nama final setelah lengkap. List mengabaikan staging dan melaporkan metadata rusak. IDs divalidasi UUID untuk mencegah path traversal. Save batal/gagal tidak menerbitkan metadata sukses; default mock tetap menolak. Folder dikecualikan dari backup, file memakai protection until first unlock.

Deletion menghapus folder hasil secara utuh; error diteruskan ke UI. App deletion menghapus koleksi. Belum ada migrasi schema, thumbnail cache, quota total, cloud sync, atau recovery data corrupt otomatis.

## Attribution

Komentar `// -Nimah:` ada di tiap source Swift yang dibuat/diubah pada implementasi MVP. File lama yang tidak berubah tidak diberi atribusi baru. Konfigurasi memakai komentar sesuai format file. Khalish dan Hanum tidak diberi atribusi penulisan kode yang bukan pekerjaannya.
