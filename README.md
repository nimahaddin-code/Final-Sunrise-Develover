# Final-Sunrise-Develover

**SunriseApp** adalah nama produk sementara untuk aplikasi panduan makeup berbasis AR. Repository ini berisi **project scaffold untuk kolaborasi tim**, belum aplikasi selesai.

## Mulai di sini

- Tech lead: [pembagian workstream](Docs/TeamWorkstreams.md).
- Engineer: [arsitektur](Docs/Architecture.md), [kontrak integrasi](Docs/IntegrationContracts.md), [kontribusi](CONTRIBUTING.md).
- QA: [test dan checklist](Docs/Testing.md), [hasil validasi](Docs/Validation.md).
- Produk: [scope milestone](Docs/ProductScope.md), [alur navigasi](Docs/NavigationFlow.md), [keputusan fondasi](Docs/Decisions/0001-project-foundation.md).

## Requirement dan setup

- Mac dengan Xcode 15+ lengkap dan iOS Simulator runtime yang terpasang. Build environment yang benar-benar diperiksa tercantum di Validation.md.
- Minimum iOS 17, iPhone portrait. Satu dependency eksternal: MediaPipe Tasks Vision (eyeliner) lewat Swift Package Manager (`https://github.com/google-ai-edge/mediapipe`, produk MediaPipeTasksVision). Xcode mengunduhnya saat pertama kali membuka project; simulator hanya arm64 (Apple Silicon). Lihat [ADR 0002](Docs/Decisions/0002-mediapipe-eyeliner.md).
- Buka `SunriseApp.xcodeproj`, pilih scheme **SunriseApp**, pilih iPhone Simulator, lalu Run (Cmd+R).
- Untuk iPhone fisik: pilih target → Signing & Capabilities → development Team milikmu, gunakan bundle identifier unik bila diperlukan, trust perangkat dan aktifkan Developer Mode, lalu Run. Team ID pribadi tidak disimpan di repository.
- Untuk test: Product → Test (Cmd+U) atau ikuti CLI di Docs/Testing.md.

## Apa yang bekerja

Onboarding session-only, dua tab, typed navigation dengan path terpisah, empat reference sample, detail, jalur placeholder seluruh fitur, previous/next langkah tutorial, loading/empty/error state, mock injection, design tokens light/dark, dan kerangka unit test/CI.

## Apa yang belum diimplementasikan

Kamera, ARKit face tracking, cek dukungan perangkat asli, face calibration, import Photos, capture, comparison foto, persistence, dan analisis gambar. Setiap layar terkait berlabel scaffold. My Looks menampilkan metadata contoh, bukan hasil pengguna; tombol Save disabled dan mock save melempar notImplemented. Onboarding tampil ulang pada app launch berikutnya.

Target berikutnya adalah blush yang mengikuti face mesh pada iPhone. Empat langkah lainnya tetap manual sampai implementasinya benar-benar ada. Import reference tidak mencakup analisis makeup otomatis.

Tidak ada permission kamera/foto, networking, analytics, penyimpanan data pengguna, app icon final, atau brand final pada tahap ini. Nama SunriseApp dipusatkan pada target/configuration dan pengenalan scaffold agar mudah diganti.

## Struktur

```text
.github/                  CI, template PR dan issue
Docs/                     scope, arsitektur, kontrak, workstream, test, ADR
SunriseApp.xcodeproj/      app + unit test target, shared scheme
SunriseApp/
  App/                    entry point, composition root, navigation
  Core/                   model bersama dan service contracts
  DesignSystem/           warna, typography, spacing, komponen
  Features/               satu area per fitur
  Resources/              named colors dan string catalog
  PreviewSupport/         sample data + mock untuk scaffold/preview
  Configuration/          Info.plist tanpa permission hardware
SunriseAppTests/           Navigation, Features, TestSupport
```

## Menambah fitur dan menggunakan mock

Inject service via initializer seperti ReferenceCatalogView(service:). Untuk preview, gunakan MockReferenceCatalog(items:), MockFaceTrackingChecker(result:) atau MockSavedLooksStore(items:). Default seluruh mock dikomposisikan di AppContainer.scaffold(); jangan akses container dari fitur.

Buat file dalam Features/<Feature>, tambahkan ke group/target Xcode yang tepat, tulis test perilaku yang bermakna, lalu update status fitur dan docs. Kontrak bersama diubah melalui PR terkoordinasi. Stateless View tidak memerlukan ViewModel. ViewModel memakai MainActor, ObservableObject dan Published secara konsisten.

String UI memakai string catalog berbahasa sumber English. Copy placeholder panjang dan konten sample sengaja masih untuk pengembangan. Tambahkan translation/localization review pada milestone UI nyata. Warna berasal dari named asset dan mendukung dark mode; font memakai text styles Dynamic Type. UI belum dianggap terverifikasi sampai checklist visual dijalankan.

## Status GitHub

Repository publik: [nimahaddin-code/Final-Sunrise-Develover](https://github.com/nimahaddin-code/Final-Sunrise-Develover), branch utama `main`.

Clone untuk mulai bekerja:

```sh
git clone https://github.com/nimahaddin-code/Final-Sunrise-Develover.git
cd Final-Sunrise-Develover
open SunriseApp.xcodeproj
```

Status build/test lokal ada di Validation.md; hasil CI remote dapat dilihat di tab Actions. Tidak ada branch protection atau pengaturan akun yang diubah.
