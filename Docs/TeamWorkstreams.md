# Pembagian iterasi MVP — Nimah, Khalish, Hanum

> -Nimah · 22 October 2026: Pembagian dari tech lead saat ini: **Holly: deteksi/analisis bentuk wajah; Nimah: eyebrow + blush; Hanum: eyeliner**. Katalog preferensi dan preview eyebrow/blush sudah tersedia, analisis Holly belum tersambung. [Kontrak, referensi dan acceptance](BrowBlushPreferences.md). Pembagian lama di bawah merupakan riwayat/usulan sebelumnya.

> -Nimah, 19 October 2026: scope terbaru mencakup closed eyebrow outline, lima forehead style dan tutorial manual. Baca [BrowForeheadGuide](BrowForeheadGuide.md) untuk status terbaru, batas hairline dan testing; catatan sebelumnya di bawah adalah riwayat.

> -Nimah: Instruksi terbaru menetapkan tech lead mengerjakan Eyes & Eyebrows. Kontrak modul dan handoff region lain ada di [EyebrowModule](EyebrowModule.md). Nama PIC Lips/Nose dan Cheeks/Forehead/Jaw/Chin belum ditetapkan di instruksi baru; tabel lama di bawah tetap usulan historis.

Ini daftar area kerja, bukan asumsi jumlah anggota. Satu PIC dapat memegang beberapa area; tech lead menetapkan nama melalui issue. Area bisa mulai paralel menggunakan mock setelah kontrak minimum disepakati.

## Prioritas placement eyeliner — -Nimah

Pembagian berikut adalah **usulan tugas berikutnya**, bukan atribusi penulis kode atau delegasi otomatis. Tech lead dapat menyesuaikan PIC. Kode iterasi ini ditandai -Nimah.

| PIC usulan | Deliverable | Dependensi | Acceptance |
| --- | --- | --- | --- |
| Nimah | Integrasi build, pengujian iPhone 17, review anatomy bersama makeup artist/tester | Source eyeliner + perangkat + persetujuan tester | Original vs eyeliner only diuji pada wajah; anotasi lokasi; hasil PASS/FAIL jujur dan keputusan toleransi dicatat |
| Khalish | Audit upper-rim attachment dan opsi landmark untuk eyelid sulit | Debug region + sampel yang diizinkan | Tidak ada pigmen hidung/pipi; dokumentasikan batas mesh; detektor tambahan hanya jika error/latency terukur membaik |
| Hanum | QA scope tutorial, kontrol style, debug UI dan regresi lifecycle | Kontrak state di MakeupAccuracyPlan.md | Previous/next kembali satu layer; full look eksplisit; refit/background/anchor replacement tidak memunculkan hasil lama |

Urutan wajib: audit/debug → eyeliner → **gate wajah nyata** → baru perluas attachment/fine adjustment shadow/lips/blush/contour → integrasi full look tervalidasi. Buat satu PR kecil per area, koordinasikan project.pbxproj dan file kontrak. Panduan acceptance ada di EyelinerDeviceTesting.md; usulan metrik belum disepakati dan belum diukur.

## Tim dan handoff saat ini

| Nama | Usulan area iterasi berikut | Pekerjaan berikutnya |
| --- | --- | --- |
| Nimah (tech lead) | Integrasi, camera/calibration/AR | Uji iPhone, tuning pipi, lifecycle dan capture orientation |
| Khalish | Katalog/detail/import dan tutorial | Review konten look, import memory, UI/accessibility |
| Hanum | Comparison, local persistence, My Looks | End-to-end save/relaunch/delete, thumbnail dan storage quota |

Implementasi MVP pada paket ini diberi komentar `// -Nimah:` sesuai permintaan. Ini tidak mengklaim Khalish atau Hanum menulis kode yang dibuat pada fase ini. Status fitur dan batas pengujian terbaru ada di ProductScope.md dan Validation.md. Rincian delapan area di bawah menjadi backlog/handoff; beberapa deliverable awal sudah diimplementasikan dan perlu divalidasi lebih lanjut.

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
- Kontrak: media import session-only; koordinasikan perubahan ownership jika reference kelak ikut disimpan.
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
- Kontrak: SavedLookMetadata, SavedLooksStoring; save dua JPEG memakai staging folder; pertahankan kontrak transaksi saat mengembangkannya.
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
