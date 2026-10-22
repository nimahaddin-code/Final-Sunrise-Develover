# Final-Sunrise-Develover — MVP

> -Nimah: Team integration now includes Khalish face-shape/Try On and Hanum MediaPipe eyeliner alongside Nimah Brow & Blush Studio. [Source attribution and preserved modules](Docs/CodeOwnership.md). Historical scope/dependency notes below predate this merge.

> -Nimah · follow-up overlay kedua: signed build berhasil dan terpasang di iPhone 17 Nimah New pada 08:32. Simulator 81 tes: 78 pass, 3 hardware skip, 0 fail. Percobaan baru mengaktifkan After/guide lagi; dropout singkat pada anchor sama melanjutkan mapping. Acceptance gejala perangkat tetap belum dikonfirmasi pengguna. Rincian: Docs/BrowBlushPreferences.md.

> -Nimah · 22 October 2026, scan recovery: reset/loss now invalidates old worker ownership, failed area generation retries after a cooldown, and scan UI explains positioning (near/far, movement, eyes and pose) with Scan ulang. Distance 25–60 cm is a starting suggestion, not an enforced hardware limit. Signed iPhone build succeeded and installed on Nimah New at 06:27. Simulator: 80 tests, 77 passed, 3 hardware skipped, 0 failures. Real-face repeat-use acceptance remains pending. Previous installation/test notes below are historical.

> -Nimah · 22 October 2026: **Discover → Brow & Blush Studio** kini menyediakan pilihan face shape manual, preset eyebrow/blush sesuai referensi pengguna, Before/After dan tutorial. Kontrak hasil analisis Holly tersedia; classifier belum tersambung. Build iPhone berhasil; 75 tes lulus + 3 hardware skip. Instalasi terbaru gagal karena koneksi iPhone terputus; alignment wajah nyata belum diverifikasi. [Panduan dan batas terbaru](Docs/BrowBlushPreferences.md). Catatan iterasi di bawah adalah riwayat.

> -Nimah, update eyeshadow: seluruh makeup live kini memakai **vertex colors** untuk area non-eyeliner dan **strip attachments** untuk eyeliner. Atlas lama tidak digunakan pada jalur live. Bentuk mask area non-eyeliner masih estimasi dan belum lolos acceptance wajah nyata.

Produk sementara: **SunriseApp**, aplikasi iPhone SwiftUI untuk belajar makeup. Implementasi MVP ini diberi komentar `// -Nimah:`. Khalish dan Hanum adalah rekan coder; usulan pembagian iterasi berikut ada di [TeamWorkstreams](Docs/TeamWorkstreams.md).

## Status eyeliner terbaru — -Nimah

Tutorial sekarang default **satu layer aktif**, full look/previous steps harus dipilih. Eyeliner memakai strip triangle attachments; titik berbagi attachment yang sama. Tersedia kontrol wing/thickness dan debug wireframe/region/UV pada build Debug. **Penilaian alignment di wajah nyata belum lulus acceptance**, meskipun tes mesh netral hardware dan render sintetis dapat berjalan.

Mulai dari [rencana dan diagnosis](Docs/MakeupAccuracyPlan.md), [uji wajah di iPhone](Docs/EyelinerDeviceTesting.md), serta [hasil verifikasi](Docs/Validation.md). Preview shadow/lips/blush/contour lain masih eksperimen; perluas implementasi setelah gate eyeliner wajah nyata lolos.


## Outline mengikuti alis terdeteksi — -Nimah, 20 October 2026

Build final berhasil dipasang ke iPhone 17 pada 09:13. Buka ulang modul dan Refit. 69 tes lulus + 3 hardware skip; alignment wajah nyata tetap belum dinilai.

Koreksi terbaru mengikuti garis tengah seluruh titik eyebrow dengan least-squares, memakai lebar deteksi aktual. Formula nose–eye menjadi referensi opsional (default off), tidak lagi menarik outline ke atas/luar alis. Titik tutorial mengikuti outline yang sama. Ini belum segmentasi rambut pixel-level. Baca [EyeBrowMapping](Docs/EyeBrowMapping.md) untuk perubahan dan batas; catatan formula-shape di bawah adalah riwayat.

## Koreksi tinggi alis — -Nimah, 20 October 2026

Curve live kini mengikuti tinggi puncak hasil scan; menghapus penambahan arch besar berdasarkan lebar alis. Kedalaman patokan mata memakai mesh sekitar kelopak, bukan pusat bola mata. Ini kombinasi landmark 2D + permukaan mesh 3D, bukan pemindai pupil 3D langsung. Detail dan batas di [EyeBrowMapping](Docs/EyeBrowMapping.md).

67 tes lulus + 3 skip hardware; build iPhone berhasil. Versi koreksi belum terpasang karena perangkat terkunci. Akurasi wajah nyata belum terverifikasi. Setelah memasang versi baru, lakukan Refit. Catatan iterasi sebelumnya di bawah merupakan riwayat.

## Eye & Brow Scan terbaru — -Nimah, 20 October 2026

Sebelum guide/preview live: scan dua mata, pupil, alis dan hidung, lalu tunggu tiga observasi stabil. Titik awal dihitung vertikal dari sisi hidung; arch lewat ray hidung–pupil; tail lewat ray hidung–sudut luar mata. Posisi arch tidak lagi fixed di 64% lebar brow. Style, outline dan preview mengikuti mapping yang sama. Garis rumus bisa ditampilkan/dimatikan. Jika landmark tidak tersedia atau gate gagal, tidak ada fallback template live.

Panduan, rumus dan batasnya: [EyeBrowMapping](Docs/EyeBrowMapping.md). Ini pemetaan makeup berbasis landmark, bukan jaminan pixel-perfect. Simulator: 65 tes lulus + 3 skip hardware, build iPhone berhasil. Instalasi versi scan terbaru tertahan perangkat terkunci; akurasi wajah nyata belum diverifikasi.

## Preview Before/After terbaru — -Nimah

Di **Discover → Brow & Forehead Guides → pilih region/style**, pilih **Before** untuk kamera asli atau **After** untuk simulasi warna alis/contour/highlight. Intensity dan Placement guide dapat diatur sebelum maupun saat tutorial. Detail teknologi, batas dan status instalasi ada di [BrowForeheadGuide](Docs/BrowForeheadGuide.md). Versi preview terbaru berhasil dibuild untuk iPhone; belum terpasang karena perangkat terputus.

## Eyebrow + Forehead update — 19 October 2026, -Nimah

Buka **Discover → Brow & Forehead Guides**. Flow: kamera → tracking → pilih region → pilih style → tutorial manual Next. Alis memakai outline atas/bawah, forehead memakai closed area guides. Keduanya mengikuti triangle attachments pada mesh terbaru; bukan gambar yang ditempel ke layar.

- Eyebrow: Straight, Soft Arch, High Arch, Feathered; tutorial 4 langkah.
- Forehead Contour: Hairline, Temple, Soft Sculpt.
- Forehead Highlight: Center Highlight, Soft Glow; tutorial forehead 3 langkah.
- Batas atas forehead dapat diatur. **Tidak mendeteksi hairline/rambut/hijab otomatis**; sesuaikan ke kulit yang terlihat. Guide di luar mesh ditolak.
- Dots / dashed / both, hide/show, refit dan debug tetap tersedia.
- Ini panduan bentuk/area, bukan filter hasil warna makeup, penilaian otomatis, atau janji hasil identik dengan foto.

Simulator: 59 tes, 56 lulus / 3 skip hardware / 0 gagal. Signed build iPhone berhasil dan terpasang. Akurasi live pada wajah belum diverifikasi; perangkat terkunci saat pemeriksaan. Status ini menggantikan angka dan scope eyebrow versi sebelumnya di bawah.

Panduan terbaru: [BrowForeheadGuide](Docs/BrowForeheadGuide.md).

## Riwayat modul Eyebrow Guide — -Nimah

Buka **Discover → Eyebrow Guide**. Fitur ini menampilkan guide alis, bukan filter warna: dots/dashed, Straight/Soft Arch/High Arch/Feathered, Show guide, Refit dan debug mesh. Vision memetakan alis ke mesh ARKit; seluruh modul memakai satu shared ARSession. Tidak ada hardcoded eyebrow vertex indices, AI transfer, atau sesi kamera kedua.

**Verifikasi iterasi alis:** build iPhone berhasil dan terpasang; Simulator 48 tes lulus + 2 skip hardware. Uji kamera/placement alis fisik belum dilakukan karena iPhone terkunci.

Lihat [arsitektur dan batas pemetaan](Docs/EyebrowModule.md) serta [setup/testing alis](Docs/EyebrowTesting.md). Build-verified dan device-tested dicatat terpisah; belum ada klaim pixel-perfect tracking.

## Menjalankan

1. Ekstrak paket MVP dan buka `SunriseApp.xcodeproj`.
2. Gunakan Xcode lengkap, scheme **SunriseApp**, minimum iOS 17. Iterasi ini diuji dengan Xcode 26.6 / SDK iOS 26.5.
3. Simulator: pilih iPhone Simulator dan Run. Katalog serta tutorial manual dapat didemokan; Simulator tidak menjalankan live face tracking.
4. iPhone: pilih development Team di Signing & Capabilities, gunakan bundle identifier unik bila perlu, hubungkan/trust iPhone, aktifkan Developer Mode, lalu Run.
5. Pilih look → Start my tutorial → izinkan kamera → hadapkan wajah dan tahan stabil 2 detik → Capture before → ikuti 5 langkah → Capture after → Save → buka My Looks.

Dukungan AR diputuskan lewat `ARFaceTrackingConfiguration.isSupported`. Jika tidak mendukung atau kamera ditolak, jalur tutorial manual tetap tersedia. Jangan memakai hasil Simulator sebagai bukti tracking perangkat fisik.

## Fitur yang diimplementasikan

- Onboarding dengan preferensi tersimpan.
- Katalog Sculpted Glam (foto pilihan pengguna), Douyin, Clean Girl, Soft Glam, Latte; detail langkah.
- Import PhotosPicker: preview/removal, pilih style tutorial manual, error/cancel, batas input 25 MB. Foto inspirasi tidak dianalisis dan hanya berada dalam memori sesi.
- Runtime support check, izin kamera/Settings, tracking readiness 2 detik, interruption/retry, pause saat background/tab berubah atau comparison dibuka.
- Sculpted Glam: virtual color preview blush, contour, eyeshadow, eyeliner, dan lips + titik placement. Tersedia Points + makeup / Makeup only / Points only / Original; intensity dan full-look toggle.
- Tutorial lima langkah dengan instruksi per look. Sculpted Glam memakai preview warna dan titik yang di-fit ke permukaan; look lain tetap fokus blush. Ini simulasi, bukan prediksi hasil makeup fisik atau analisis foto.
- Before/After diambil dari buffer kamera asli agar titik dan mesh tidak masuk foto. Orientasi portrait/mirroring perlu diuji iPhone. Comparison dua foto nyata, tanpa scoring atau automatic alignment.
- Simpan lokal metadata + dua JPEG per look, reload daftar/detail, dan delete dengan konfirmasi. Folder foto tidak ikut backup otomatis. Tidak ada akun, server, atau analytics.
- Manual mode tidak membuat capture/hasil palsu dan tidak menawarkan save tanpa foto.

## Batas MVP

Alignment live AR **belum dinilai pada wajah pengguna**. Build dan tes mesh netral di iPhone bukan bukti posisi makeup sudah tepat. Preview lima area tersedia secara eksperimental; belum ada AI analysis, face-shape/skin analysis, auto-personalization, reference transfer, photorealistic skin blending, atau occlusion tangan/rambut. Artwork katalog merupakan ilustrasi. Portrait iPhone saja, English UI, belum ada app icon final.

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

## Update referensi glam dan titik — -Nimah

Foto referensi pilihan pengguna dibundel lokal sebagai GlamReference, tidak diunggah ke layanan eksternal. Pilih **Sculpted Glam** untuk melihat foto, breakdown manual, dan sketsa titik. Pada iPhone kompatibel titik mengikuti vertex face mesh dan berganti tiap langkah. Simulator menampilkan sketsa edukasi dengan label yang jelas.

Template fixed-coordinate lama sekarang hanya dipakai sketsa. Live try-on memakai ukuran mesh aktual, rim mata yang dekat eye transforms, dan ring bibir yang diturunkan dari topology. Mata/bibir disembunyikan jika fit tidak tersedia. Seluruh alignment tetap perlu uji perangkat. Tidak ada janji hasil wajah identik dengan orang pada foto. Tidak ada pengubahan struktur wajah, lash filter, atau auto-makeup transfer.

## Try-on + tracking update — -Nimah

Pada iPhone kompatibel, pilih Sculpted Glam → kalibrasi sambil menatap lurus dengan mata/bibir rileks → Capture before & begin. Mode default **Points + makeup** menampilkan preview warna full look bersama titik tahap aktif. Menu di atas kamera dapat memilih Original, Points only, atau Makeup only. Intensity dan full-look/current-step tersedia di kontrol tutorial. Foto yang disimpan tetap kamera asli tanpa virtual effect; capture preview belum disediakan.

Renderer menggunakan dua ARSCNFaceGeometry yang dipakai ulang: depth untuk self-occlusion dan makeup dengan transparent UV texture. Texture dibake sekali di worker queue setelah tracking stabil; tidak ada pembuatan geometry/material per frame atau resampling titik tiap tahap. Pose dikelola ARKit secara langsung, tanpa screen-space resizing atau low-pass global yang menambah lag. Preferred render rate 60 FPS adalah permintaan, bukan hasil benchmark.

Fit memakai topology dan proporsi mesh actual; bukan AI reference transfer. Bibir memakai geodesic neighborhood dari inner rim; eye effects memakai rim yang dekat eye transforms. Ini pendekatan coarse mesh, belum contour segmentation pixel-level. Original mode tidak mengubah wajah. Tombol Refit face dapat mengulang kalibrasi; jarak kamera ditampilkan sebagai hint, tidak ada hard lock jarak tertentu.

Pengguna melaporkan memakai **iPhone 17**. Perangkat tersebut belum tersedia untuk pengujian fisik di sesi ini. Build dan synthetic tests tidak membuktikan jitter, eyeliner/lip alignment, atau error pada setiap jarak telah terselesaikan. Tidak ada janji presisi di semua kondisi.

### Update preview warna — -Nimah

Pemetaan vertikal atlas makeup diperbaiki dan pigmen Sculpted Glam diperjelas. Sebanyak 27 tes simulator lulus, termasuk uji piksel render. Retest iPhone fisik tetap diperlukan; langkahnya ada di Docs/Testing.md. Ini pembaruan pada proyek Final-Sunrise-Develover yang sama, bukan proyek GlowGuide baru.
