# Arsitektur MVP

> -Nimah: Acuan placement terbaru: [MakeupAccuracyPlan](MakeupAccuracyPlan.md) dan [EyelinerDeviceTesting](EyelinerDeviceTesting.md). Catatan di bawah dapat mencakup iterasi historis. Eyeliner kini strip attachment, bukan atlas; full look default OFF.

Fondasi tetap SwiftUI + MVVM ringan, iOS 17+, ObservableObject/Published dan MainActor untuk UI. Satu app target, satu test target; tidak ada dependency eksternal.

## Composition

`SunriseApp → AppContainer.live() → AppRootView → feature initializer`.

Live composition memilih BundledReferenceCatalog, DeviceFaceTrackingChecker, dan LocalSavedLooksStore. Mock di PreviewSupport tidak dipakai saat run normal. AppContainer bukan service locator: fitur menerima dependency spesifik.

AppRootView menyimpan onboarding melalui AppStorage. AppNavigator memisahkan stack Discover dan My Looks. AppRoute membawa reference atau metadata; UIKit tidak masuk model domain.

## Sesi makeup

MakeupSessionView memegang satu FaceCameraState, FaceCalibrationViewModel, dan TutorialViewModel selama sesi. Komponen LiveGuideView membungkus ARSCNView; camera tetap satu selama kalibrasi dan langkah tutorial. Beralih manual menutup sesi dan membuang capture sementara. Comparison membuka sheet, menjeda kamera, dan memakai dua UIImage dari raw camera buffer; tidak ada image di route atau container.

Sesi pause saat scene tidak aktif, layar tidak terlihat, manual mode, atau comparison. Tracking loss mereset readiness; capture memerlukan anchor tracked yang fresh; raw camera buffer terpisah dari renderer sehingga tidak memuat overlay. ARSessionDelegate queue terpisah mengukur readiness, UI dipublikasikan melalui MainActor. SceneKit render callback memutakhirkan mesh; akses flag overlay lintas thread dilindungi NSLock. Coordinator memakai unchecked Sendable hanya untuk batas framework delegate tersebut; jangan menambah state lintas-thread tanpa isolasi.

## Mesh blush

Bobot warna dihitung dari vertex face-local awal untuk dua pipi; mask per anchor tetap dan seluruh vertex/triangle diperbarui dari geometry terbaru. Node otomatis mengikuti transform anchor. Material constant/alpha, transparan di luar pipi, single-sided, tanpa depth writes. Ini POC placement; bukan render makeup fotorealistik atau klasifikasi wajah. Penempatan dan alpha wajib diuji pada iPhone.

## Persistence

LocalSavedLooksStore adalah actor. Application Support/SunriseApp/Looks/<UUID> memuat metadata.json, before.jpg, after.jpg. Semua file ditulis di folder staging tersembunyi, kemudian folder dipindahkan ke nama final setelah lengkap. List mengabaikan staging dan melaporkan metadata rusak. IDs divalidasi UUID untuk mencegah path traversal. Save batal/gagal tidak menerbitkan metadata sukses; default mock tetap menolak. Folder dikecualikan dari backup, file memakai protection until first unlock.

Deletion menghapus folder hasil secara utuh; error diteruskan ke UI. App deletion menghapus koleksi. Belum ada migrasi schema, thumbnail cache, quota total, cloud sync, atau recovery data corrupt otomatis.

## Attribution

Komentar `// -Nimah:` ada di tiap source Swift yang dibuat/diubah pada implementasi MVP. File lama yang tidak berubah tidak diberi atribusi baru. Konfigurasi memakai komentar sesuai format file. Khalish dan Hanum tidak diberi atribusi penulisan kode yang bukan pekerjaannya.

## Dotted placement — -Nimah

PlacementDots di BlushMask.swift memuat target face-local manual per step dan mencari vertex terdekat tanpa hardcoded indeks ARKit. Pemetaan didedup dan dicache per anchor/per step. SCNSphere marker diperbarui dari vertex yang sama pada setiap frame, lalu mengikuti transform anchor; bukan titik dalam koordinat layar. Render config (visibility/step/style) dilindungi NSLock. Cache dibuang saat anchor hilang. Soft area memakai jalur mesh blush sebelumnya.

Raw capture memakai ARFrame.capturedImage → CIImage portrait front-camera → CGImage. Tidak ada overlay pada hasil, tetapi orientation/mirroring belum diverifikasi physical. Sketsa mode manual adalah diagram SwiftUI, bukan AR preview atau hasil pengguna.

Mesh depth-only tanpa color writes dipasang di mode Dots agar bagian muka yang lebih dekat menghalangi marker sisi jauh. Ini self-occlusion POC; bukan occlusion rambut/tangan dan belum diuji hardware.

## Try-on architecture menggantikan live renderer lama — -Nimah

- FaceSurfaceProfile: membentuk boundary components dari triangle edges, memilih eye rims berdasarkan eye transforms dan mouth rim di bawah mata, menghitung ukuran relatif wajah serta geodesic lip neighborhood. Mask yang fit-nya hilang tidak diganti template yang mengaku akurat.
- MakeupTextureBaker: premultiplied transparent RGBA atlas per tahap dan full look; UV/triangle barycentric raster. Dibangun sekali di worker queue, diterbitkan hanya untuk session generation yang sesuai.
- LiveGuideView: persistent ARSCNFaceGeometry depth + makeup; update(from:) setiap render callback. Dot indices dipilih dari area mask pada vertex yang memang dirender, dipertahankan selama anchor hidup. Implicit SCNTransaction animation dinonaktifkan.
- World pose/perspective tetap milik ARKit; tidak smoothing pose atau scaling overlay berdasarkan pixel jarak. Geometry-local deformation dan texture UV mengikuti ekspresi. Full look warna tetap palette manual referensi, bukan skin reconstruction/ML.
- Tracking flags dipublikasikan per frame untuk renderer, UI/readiness sekitar 10Hz. Readiness memakai camera-relative face pose; fitting menunggu 2 detik stabil dan ekspresi netral/frontal.
- Preview mode/intensity/full-look terpisah dari raw captures. Capture save tetap unfiltered untuk menjaga arti Before/After physical makeup.
- 60 FPS requested, render timing dan stabilitas visual belum diukur pada iPhone. Persistent native meshes menghapus alokasi geometry per-frame versi sebelumnya; itu perubahan implementation, bukan bukti akar tunggal jitter pengguna.

Rujukan native geometry: [Apple ARSCNFaceGeometry](https://developer.apple.com/documentation/arkit/arscnfacegeometry). Topology dan UV tetap; vertex berubah mengikuti tracked face. Rendering/color fit memerlukan verifikasi fisik, terutama mata dan bibir.

## Eyebrow module — -Nimah

Foundation AR sekarang memakai ARFaceTrackingManager.shared dengan owner lease. Eyebrow menggunakan Vision dari ARFrame yang sama, ray–triangle projection dan attachment pada mesh; tidak membuat kamera baru. Kontrak, file dan batas koordinat: [EyebrowModule](EyebrowModule.md).
