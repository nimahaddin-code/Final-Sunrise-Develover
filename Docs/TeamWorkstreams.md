# Usulan pembagian pekerjaan tim

Ini daftar area kerja, bukan asumsi jumlah anggota. Satu PIC dapat memegang beberapa area; tech lead menetapkan nama melalui issue. Area bisa mulai paralel menggunakan mock setelah kontrak minimum disepakati.

## 1. Foundation dan integrasi

- Tujuan: menjaga app dapat dibuild dan integrasi antarfitur konsisten.
- Area: App/, Core/, project.pbxproj, shared scheme, .github/.
- Kontrak: AppRoute, AppContainer, seluruh service contracts; koordinasikan dengan pemilik fitur.
- Dependensi: keputusan scope dan API dari tiap workstream.
- Deliverable: wiring layanan nyata, navigasi, review kontrak, build CI yang hijau.
- Acceptance: seluruh route dapat dijangkau; tab history terpisah; build dan test lulus; tidak ada file yatim atau rahasia.
- Belum termasuk: implementasi fitur kamera/AI dan perubahan pengaturan akun GitHub.

## 2. Onboarding, katalog, detail reference

- Tujuan: pengguna memahami aplikasi dan memilih look.
- Area: Features/Onboarding, ReferenceCatalog, ReferenceDetail; konten Assets/Strings lewat koordinasi design.
- Kontrak: ReferenceCatalogProviding dan MakeupReference; output pilihan ke AppRoute.
- Dependensi: design tokens; katalog dapat dikerjakan menggunakan MockReferenceCatalog.
- Deliverable: UI nyata, konten reference, persistence onboarding bila disetujui.
- Acceptance: loading/empty/error/retry, empat look, akses detail, accessibility dan text besar; tidak mengklaim personalisasi otomatis.
- Belum termasuk: import, analisis foto, sesi AR.

## 3. Import reference

- Tujuan: memilih foto inspirasi pribadi tanpa janji analisis otomatis.
- Area: Features/ReferenceImport.
- Kontrak: belum ada media contract; sepakati owned reference ID/lifecycle dengan tutorial dan persistence sebelum wiring.
- Dependensi: API media milestone berikut; UI dapat dimulai dari placeholder dan fixture berlabel.
- Deliverable: PhotosPicker, preview/removal, cancellation/error, pengelolaan ukuran gambar.
- Acceptance: cancel tidak dianggap error; iCloud/unreadable asset ditangani; tidak ada klaim makeup extraction; foto tidak terkirim ke server.
- Belum termasuk: AI, broad library browsing, transfer makeup otomatis.

## 4. Face calibration dan live AR guide

- Tujuan: membuktikan blush mengikuti face mesh pada iPhone.
- Area: Features/FaceCalibration, Features/LiveGuide; configuration permission dikoordinasikan Foundation.
- Kontrak: FaceTrackingAvailabilityChecking; usulkan session contract setelah spike.
- Dependensi: akses iPhone kompatibel; UI manual/fallback tidak menunggu spike.
- Deliverable: runtime support check, permission/session lifecycle, calibration readiness, mesh blush proof of concept.
- Acceptance: cheek overlay mengikuti posisi/ekspresi; tracking loss ditangani; background pause; unsupported fallback; bukti video/test perangkat dengan keterbatasan placement.
- Belum termasuk: shape detection, skin analysis, AR empat langkah lainnya, photorealistic blending.

## 5. Tutorial flow

- Tujuan: membimbing lima langkah secara jelas.
- Area: Features/Tutorial; Core/Models/Tutorial lewat PR bersama.
- Kontrak: Tutorial/TutorialStep, referenceID; session integration nanti disepakati AR.
- Dependensi: konten katalog; dapat dikerjakan dengan mock tanpa AR.
- Deliverable: instruksi per look, state langkah, progress dan navigasi, integrasi blush jika tersedia.
- Acceptance: previous/next di batas aman; state/restore disepakati; langkah manual ditandai; tidak mengklaim completion otomatis.
- Belum termasuk: penilaian makeup atau analisis wajah.

## 6. Comparison dan saved looks

- Tujuan: membandingkan capture nyata dan menyimpan koleksi lokal.
- Area: Features/Comparison, Features/SavedLooks; kontrak SavedLooksStoring melalui koordinasi.
- Kontrak: SavedLookMetadata, SavedLooksStoring; proposal transaksi media diperlukan sebelum save aktif.
- Dependensi: capture dari AR/camera dan media ownership dari import bila reference ikut disimpan. UI boleh menggunakan metadata sample tanpa foto palsu.
- Deliverable: comparison, file storage, metadata, reload/delete, error/cleanup policy.
- Acceptance: capture asalnya jelas; tanpa overlay jika dipilih produk; simpan/relaunch/hapus konsisten; gagal I/O tidak menampilkan sukses; media dan metadata tidak orphan.
- Belum termasuk: cloud, social sharing, beauty scoring, automatic photo alignment.

## 7. Design system dan accessibility

- Tujuan: pengalaman blush pink premium yang konsisten dan terbaca.
- Area: DesignSystem, Resources/Assets.xcassets, Localizable.xcstrings.
- Kontrak: token dan komponen reusable; koordinasikan perubahan API komponen dengan konsumen.
- Dependensi: kebutuhan semua fitur; dapat dikerjakan sejak awal.
- Deliverable: light/dark colors, typography/spacing, komponen dan string catalog yang konsisten.
- Acceptance: Dynamic Type tidak memotong aksi utama; VoiceOver dapat memahami kontrol; kontras warna diperiksa; layout small iPhone dan dark mode diverifikasi.
- Belum termasuk: nama/brand final, final marketing artwork, app icon App Store.

## 8. QA dan device testing

- Tujuan: membedakan bukti compile, unit test, UI, dan AR perangkat nyata.
- Area: SunriseAppTests, Docs/Testing.md; test code mengikuti fitur yang diuji.
- Kontrak: acceptance criteria tiap workstream dan stub Sendable.
- Dependensi: build/test environment; runtime AR membutuhkan perangkat kompatibel.
- Deliverable: unit regression, checklist eksplorasi, laporan perangkat, triage bug.
- Acceptance: hasil test menyebut commit/environment; failure dapat direproduksi; tidak menyamakan Simulator dengan validasi tracking.
- Belum termasuk: klaim produksi atau full UI automation target pada tahap scaffold.

## File bersama dan urutan integrasi

| File/area | Risiko konflik | Mekanisme |
| --- | --- | --- |
| AppRootView / AppRoute | Route baru mengubah destination switch | PR wiring kecil oleh Foundation, payload disepakati pemilik fitur |
| AppContainer | Pergantian mock memengaruhi semua screen | Update injection + test + status fitur dalam PR yang sama |
| project.pbxproj / scheme | Konflik IDs dan target membership | Satu PR konfigurasi saat integrasi; verifikasi group disk dan build ulang |
| Core contracts / models | Perubahan signature memutus konsumen | PR kontrak lebih dulu, review konsumen, update mock bersamaan |
| Design tokens / strings / assets | Perubahan global dan konten terduplikasi | Design PIC memeriksa API/token; tiap fitur menambahkan key deskriptif |

Urutan saran: kontrak minimum → UI berbasis mock dan spike AR dapat berjalan paralel → review kontrak media/session → integrasi layanan nyata per fitur → pengujian perangkat dan accessibility. Jangan menunggu AR untuk mengerjakan katalog atau tutorial manual.
