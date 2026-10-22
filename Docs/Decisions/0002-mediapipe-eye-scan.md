# ADR 0002 — MediaPipe untuk scan bentuk mata

Status: accepted. Tanggal: 22 Oktober 2026.

## Konteks

Setelah scan mesh 3D wajah (ARKit + Vision) menghasilkan bentuk wajah, onboarding perlu satu langkah lagi: scan bentuk mata (kemiringan, bukaan, jarak antar mata). Vision hanya memberi kontur mata tanpa iris. MediaPipe Face Landmarker memberi 478 titik, termasuk iris, sehingga ukuran mata dapat dinormalisasi terhadap diameter iris dan titik kelopak lebih rapat. ADR 0001 menyatakan tanpa dependency eksternal, sehingga keputusan ini mengubahnya secara terbatas.

## Keputusan

- Tambahkan **MediaPipeTasksVision** sebagai **Swift Package** dari `https://github.com/google-ai-edge/mediapipe` (repo resmi Google, produk `MediaPipeTasksVision`), dikunci ke **revision** `50505c8312c7eacb1bd411cecdc4cc9fd08d53cb` (tag `v1.1.1`). Revision yang ter-resolve juga tercatat di `SunriseApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` dan harus di-commit. Aturan versi biasa ("Up to Next Major") tidak bisa dipakai: `Package.swift` MediaPipe memakai `.unsafeFlags(["-Xlinker", "-all_load"])`, dan SwiftPM menolak itu untuk dependency berbasis versi (error: "uses unsafe build flags"). Google sendiri menyarankan referensi lewat branch atau revision. Revision dipilih daripada branch `master` agar tidak berubah sendiri. Naik versi = ganti revision ke tag baru lewat PR sendiri.
- Package hanya ditautkan ke target `SunriseApp`, bukan `SunriseAppTests`.
- MediaPipe hanya dipakai oleh `Features/EyeShape`, dan `import MediaPipeTasksVision` hanya di `MediaPipeEyeDetector.swift`. Pengukur dan classifier menerima titik biasa (`SIMD3<Float>`) sehingga bisa diuji tanpa MediaPipe atau kamera.
- Model `face_landmarker.task` dibundel di `Resources/` pada saat development. Tidak ada unduhan saat runtime.
- Urutan onboarding: izin kamera → scan mesh 3D (tetap) → tombol Next → scan mata (MediaPipe, baru) → Beranda dengan info bentuk mata. Skip tetap tersedia di setiap langkah.
- Kamera: setelah scan mesh selesai, `ARSession` dihentikan lalu `AVCaptureSession` kamera depan sendiri dimulai untuk scan mata (Opsi A). Dua sesi tidak berjalan bersamaan.

## Alasan dan konsekuensi

- Package resmi lebih sederhana daripada CocoaPods: tidak perlu alat tambahan, tidak perlu workspace, folder `Pods/` (sekitar 1,2 GB) tidak ada, dan CI tidak berubah. CocoaPods sempat dicoba lebih dulu dan dibuang; lihat riwayat Git.
- Package memakai `binaryTarget` (xcframework dari `dl.google.com` dengan checksum tetap di `Package.swift`), dengan slice perangkat dan Simulator, sehingga test di Simulator dan CI tetap berjalan. Unduhan hanya terjadi saat Xcode me-resolve package (build time); aplikasi tidak memakai jaringan.
- Hanya satu salinan MediaPipe yang boleh ada di proses. Menautkannya ke target test juga, atau memasangnya lewat CocoaPods bersamaan, membuat app crash saat launch ("Function with name ... already registered").
- Privasi tidak berubah: tidak ada jaringan, analitik, atau unggahan. Frame kamera tidak disimpan; hanya hasil klasifikasi mata yang disimpan.
- Swift 5 strict concurrency: kelas MediaPipe tidak `Sendable`, jadi dibungkus `@unchecked Sendable` di satu tempat dan inferensi dijalankan di luar main actor.
- Ukuran IPA belum diperiksa; cek sebelum rilis.

## Tinjau ulang jika

MediaPipe menambah ukuran aplikasi terlalu besar, Vision cukup akurat untuk iris, atau versi baru mengubah API (uji ulang eval dataset bentuk mata).
