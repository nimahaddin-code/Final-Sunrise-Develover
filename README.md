# Final-Sunrise-Develover — MVP

Produk sementara: **SunriseApp**, aplikasi iPhone SwiftUI untuk belajar makeup. Implementasi MVP ini diberi komentar `// -Nimah:`. Khalish dan Hanum adalah rekan coder; usulan pembagian iterasi berikut ada di [TeamWorkstreams](Docs/TeamWorkstreams.md).

## Menjalankan

1. Ekstrak paket MVP dan buka `SunriseApp.xcodeproj`.
2. Gunakan Xcode 15+ lengkap, scheme **SunriseApp**, minimum iOS 17.
3. Simulator: pilih iPhone Simulator dan Run. Katalog serta tutorial manual dapat didemokan; Simulator tidak menjalankan live face tracking.
4. iPhone: pilih development Team di Signing & Capabilities, gunakan bundle identifier unik bila perlu, hubungkan/trust iPhone, aktifkan Developer Mode, lalu Run.
5. Pilih look → Start my tutorial → izinkan kamera → hadapkan wajah dan tahan stabil 2 detik → Capture before → ikuti 5 langkah → Capture after → Save → buka My Looks.

Dukungan AR diputuskan lewat `ARFaceTrackingConfiguration.isSupported`. Jika tidak mendukung atau kamera ditolak, jalur tutorial manual tetap tersedia. Jangan memakai hasil Simulator sebagai bukti tracking perangkat fisik.

## Fitur yang diimplementasikan

- Onboarding dengan preferensi tersimpan.
- Katalog Douyin, Clean Girl, Soft Glam, Latte; ilustrasi wajah dan detail langkah.
- Import PhotosPicker: preview/removal, pilih style tutorial manual, error/cancel, batas input 25 MB. Foto inspirasi tidak dianalisis dan hanya berada dalam memori sesi.
- Runtime support check, izin kamera/Settings, tracking readiness 2 detik, interruption/retry, pause saat background/tab berubah atau comparison dibuka.
- Blush POC: mask warna vertex pada face mesh yang mengikuti anchor dan deformasi wajah; toggle overlay. Penempatan pipi masih perkiraan, perlu penyesuaian hasil uji iPhone.
- Tutorial lima langkah dengan instruksi per look; contour, eyeshadow, eyeliner, dan lips adalah **manual**, tanpa overlay AR.
- Capture Before saat overlay belum aktif; After setelah langkah lips dengan overlay off. Comparison dua foto nyata, tanpa scoring atau automatic alignment.
- Simpan lokal metadata + dua JPEG per look, reload daftar/detail, dan delete dengan konfirmasi. Folder foto tidak ikut backup otomatis. Tidak ada akun, server, atau analytics.
- Manual mode tidak membuat capture/hasil palsu dan tidak menawarkan save tanpa foto.

## Batas MVP

Live AR **belum diverifikasi di iPhone fisik**. Build yang berhasil bukan bukti posisi blush sudah tepat. Tidak ada AI analysis, face-shape/skin analysis, auto-personalization, reference transfer, AR empat langkah lain, photorealistic skin blending, atau occlusion tangan/rambut. Artwork katalog merupakan ilustrasi. Portrait iPhone saja, English UI, belum ada app icon final.

Data foto hilang jika aplikasi dihapus; tidak ada cloud sync atau ekspor Photos. Koleksi tidak punya thumbnail cache/pagination dan perlu pengembangan untuk banyak foto. Import saat ini membaca Data lalu UIImage; foto besar tetap memerlukan pengujian memory pada perangkat rendah.

## Struktur

```text
SunriseApp/
  App/                  entry point, DI, navigation
  Core/                 shared models + service contracts
  DesignSystem/         tokens, buttons, look artwork
  Features/
    Onboarding/         first launch
    ReferenceCatalog/   bundled catalog + loading state
    ReferenceDetail/    look overview
    ReferenceImport/    PhotosPicker inspiration
    FaceCalibration/    support check + readiness
    LiveGuide/          ARSCNView, camera lifecycle, mesh mask
    Tutorial/           session orchestration + step instructions
    Comparison/         capture comparison + save
    SavedLooks/         actor-backed local files, journal, delete
  PreviewSupport/       mocks only, not production composition
  Resources/            colors and source strings
  Configuration/        Info.plist + camera description
SunriseAppTests/         navigation, service state, storage, readiness
Docs/                   architecture, contracts, testing, team handoff
.github/                CI and issue/PR templates
```

## Kolaborasi dan test

MVVM ringan memakai MainActor/ObservableObject, initializer DI, service Sendable, dan storage actor. `AppContainer.live()` memakai service nyata; `scaffold()` tetap tersedia untuk preview/test. Mock save tetap menolak sukses palsu. Baca [Architecture](Docs/Architecture.md), [IntegrationContracts](Docs/IntegrationContracts.md), [CONTRIBUTING](CONTRIBUTING.md).

Cmd+U menjalankan unit test. Perintah CLI, checklist perangkat, dan bukti pemeriksaan ada di [Testing](Docs/Testing.md) serta [Validation](Docs/Validation.md).

## Status versi

Repository publik awal: [Final-Sunrise-Develover](https://github.com/nimahaddin-code/Final-Sunrise-Develover). Perubahan MVP dikerjakan pada branch lokal `feature/nimah-mvp`; paket ini berisi versi MVP. Jangan mengasumsikan branch main di GitHub sudah memuat perubahan lokal ini. Tidak ada deployment App Store atau upload data pengguna.
