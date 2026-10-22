# Brow & Forehead Guides — -Nimah

> -Nimah, 20 October 2026: live eyebrow mapping sekarang wajib Eye & Brow Scan dan rumus nose–pupil–outer eye; baca [EyeBrowMapping](EyeBrowMapping.md). Catatan bounds/fixed arch sebelumnya di bawah adalah riwayat implementasi.

Implementasi dalam proyek existing Final-Sunrise-Develover / SunriseApp, tanpa proyek duplikat. Mengikuti referensi pengguna: full camera, region selector, style cards dan bottom tutorial card. Thumbnail adalah sketsa vector shape, bukan foto hasil filter.

## Cara mencoba di iPhone

1. Buka SunriseApp.xcodeproj, pilih scheme SunriseApp dan iPhone kompatibel. Aktifkan Developer Mode dan signing Team, lalu Run.
2. Discover → Brow & Forehead Guides → izinkan kamera. Hadapkan wajah lurus, kedua alis terlihat, tahan stabil untuk pemetaan.
3. Choose region → Eyebrows atau Forehead. Pilih style; untuk forehead pilih Contour/Highlight, lalu atur Top limit agar guide berada di kulit yang terlihat.
4. Start tutorial. Next berpindah instruksi secara manual. Tidak ada penilaian gerakan/hasil makeup.
5. Guide settings menyediakan mode dots/dashed/both, show/hide, Refit dan debug mesh pada build Debug. Ulang Refit setelah mengubah posisi awal atau saat alignment tidak tepat.

Simulator menampilkan fallback kamera yang jelas dan mengizinkan Preview steps; tidak membuat wajah atau tracking palsu.

## Bentuk guide

Eyebrow: closed outline dari batas atas dan bawah, meruncing ke tail. Straight, Soft Arch, High Arch dan Feathered mengubah shape; Feathered menambah arah stroke. Empat langkah: titik head/arch/tail, batas atas, batas bawah, isi dan blend.

Forehead Contour: Hairline adalah band melengkung atas; Temple dua area samping; Soft Sculpt area lebar. Forehead Highlight: Center Highlight area tengah sempit, Soft Glow area tengah lebih lebar. Tiga langkah: placement, blend, review. Semua area punya closed boundary.

## Teknologi dan batas

Satu shared ARSession, ARKit face mesh, Vision eyebrow landmarks dan SceneKit. Snapshot kamera/anchor yang sama dipakai untuk ray–triangle mapping alis. Forehead diturunkan dari brow anchors dan batas mesh atas yang tersedia. Triangle indices + barycentric weights dievaluasi ulang terhadap vertex terbaru setiap frame. Tidak ada manual screen scaling berdasar jarak.

Tidak ada hairline detection, hand/hair/hijab segmentation, atau forehead landmark model tersendiri. Top limit adalah kalibrasi proporsional manual, bukan segmentasi kulit. Region di luar mesh ditolak, sehingga sebagian style dapat gagal pada mesh/pose tertentu. ARKit mesh yang jarang tetap membatasi detail. Kehilangan tracking menyembunyikan attachment dan meminta pemetaan ulang.

Tahap tracking memperlihatkan sparse mesh vertices; itu bukan semua landmark semantik Vision. Tahap choose-region menampilkan dua region jika mapping tersedia; tahap tutorial hanya region aktif. Fitur ini tidak menambahkan pewarnaan virtual ke eyebrow/forehead.

## Struktur

- Core/AR: shared session, snapshot, Vision, projection.
- Features/Eyebrow/FaceGuideFlow.swift: fase dan instruksi.
- Features/Eyebrow: mapper, outline generator, pipeline, renderer, view model dan camera-first UI.
- Features/Forehead/ForeheadGuide.swift: kategori, lima style, batas dan mesh binding.
- Features/Forehead/ForeheadSceneRenderer.swift: dashed/dots area renderer dan sparse tracking points.
- SunriseAppTests/Features/ForeheadGuideTests.swift: closed boundaries, mesh limits, deformation, phase/region separation dan native neutral mesh gate.

Kode iterasi ini ditandai -Nimah. Referensi tugas menempatkan forehead pada Nimah Addini; penugasan Khalish/Hanum lainnya tetap mengikuti kesepakatan tim.

## Hasil dan acceptance

19 October 2026: Xcode 26.6, iOS SDK 26.5. Simulator suite 59 tests: 56 pass, 3 hardware skip, 0 failures. Signed generic iPhone build succeeds; build terbaru terpasang pada iPhone 17. UI region → style → tutorial diperiksa di Simulator. Tidak ada klaim live acceptance dari Simulator atau neutral geometry.

Uji iPhone berikut masih wajib: dua alis tepat pada sisi masing-masing; outline tetap di kulit saat jarak 25/35/50 cm dan yaw/pitch kecil; forehead tetap di atas brow saat Top limit berubah; semua lima style dapat dipetakan pada mesh nyata; loss/refit tidak meninggalkan guide lama; mata berkedip tidak menarik guide ke pipi. Periksa hairline/hijab secara manual. Catat screenshot/video dan error yang terlihat sebelum menyatakan akurat.

Build lokal belum dipush ke GitHub. ZIP MVP diperbarui pada lokasi yang sama.

## Live Before/After preview — -Nimah, 19 October 2026

Choose style sekarang memiliki Before/After, Intensity dan Placement guide. After menampilkan simulasi cokelat untuk alis/contour atau terang untuk highlight; Before memakai kamera live yang sama tanpa efek maupun garis. Tutorial juga menyediakan kontrol ini. Tidak mengambil/menyimpan foto perbandingan dalam modul ini.

Patch warna dibentuk dari polygon guide yang sama, dengan feather di dalam batas polygon. Grid di-bind ke triangle mesh dan dievaluasi terhadap vertex terbaru setiap frame. Tidak menggunakan UV atlas lama. Binding patch dibuat sekali per guide/style/height; render positions diperbarui setiap frame. Performa pada iPhone dan kualitas blending di wajah masih perlu diuji. Alis asli tidak dihapus atau ditipiskan; ini overlay warna, bukan rekonstruksi fotorealistis atau AI transfer.

Signed iPhone build berhasil. Instalasi versi preview ini gagal karena perangkat tidak lagi terhubung; build sebelumnya sudah terpasang, tetapi bukan bukti preview terbaru ada di iPhone. Simulator UI telah diperiksa; tidak menyediakan AR face tracking.

-Nimah, preview verification: Simulator 62 tests — 59 passed, 3 hardware skips, 0 failures. Tests cover concave mask/feather, Before isolation and patch movement with mesh deformation. Build iPhone succeeds; live on-face preview and performance remain unverified.
