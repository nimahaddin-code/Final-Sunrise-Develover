# Setup dan acceptance Eyebrow Guide — -Nimah

> -Nimah, 20 October 2026: live eyebrow mapping sekarang wajib Eye & Brow Scan dan rumus nose–pupil–outer eye; baca [EyeBrowMapping](EyeBrowMapping.md). Catatan bounds/fixed arch sebelumnya di bawah adalah riwayat implementasi.

> -Nimah, 19 October 2026: scope terbaru mencakup closed eyebrow outline, lima forehead style dan tutorial manual. Baca [BrowForeheadGuide](BrowForeheadGuide.md) untuk status terbaru, batas hairline dan testing; catatan sebelumnya di bawah adalah riwayat.

## Jalankan di iPhone

1. Gunakan folder proyek **Final-Sunrise-Develover** ini. Buka `SunriseApp.xcodeproj`, scheme **SunriseApp**.
2. Minimum deployment iOS 17; build iterasi ini menggunakan Xcode 26.6 dan SDK iOS 26.5. Pilih Team dan bundle identifier yang sesuai akun developer. Signing existing dipertahankan.
3. Hubungkan/trust iPhone, aktifkan Developer Mode dan **buka kunci perangkat**. Pilih iPhone sebagai Run Destination, lalu Run.
4. Selesaikan onboarding bila perlu, buka **Discover → Eyebrow Guide**. Izinkan kamera.
5. Wajah frontal, kedua alis terlihat, cahaya cukup, mata/bibir rileks. Tahan stabil sekitar dua detik, lalu tunggu Vision menyelesaikan pemetaan.
6. Straight + Both merupakan default. Pink menunjukkan intended makeup guide. Pilih Dots / Dashed untuk melihat masing-masing.
7. Pilih Soft Arch / High Arch / Feathered dan periksa bahwa bentuk guide berubah. Gunakan Show guide dan Refit eyebrows.
8. Debug build: buka Developer debug → Full mesh + detected brow points. White points menunjukkan landmarks yang dipetakan, pink guide menunjukkan shape aplikasi makeup.

Runtime `ARFaceTrackingConfiguration.isSupported` menentukan dukungan, bukan daftar model asumsi. Simulator menampilkan unsupported state; tidak ada fake camera/live overlay. Permission denied menyediakan Settings dan recheck. Sesi di-pause saat background, kembali/navigation dan interruption ditangani oleh foundation AR.

Tidak perlu izin Photos untuk modul alis. NSCameraUsageDescription menjelaskan pemrosesan landmark lokal. Tidak ada capture/save/rekaman atau upload di layar alis.

## Menjalankan tests

Xcode → Product → Test. Sebagian tes hardware native mesh milik fitur existing di-skip pada Simulator. Tes Vision pada foto bundled memakai inference CPU di Simulator jika GPU context tidak tersedia; ini inference Vision sungguhan, bukan stub hasil wajah.

Contoh command (ganti destination sesuai perangkat sendiri):

```sh
xcodebuild -project SunriseApp.xcodeproj -scheme SunriseApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Test source baru: EyebrowTests.swift. Meliputi semua inverse EXIF transforms, ray intersection pada pose kamera berbeda, side association, variasi posisi alis, rejection data invalid, curve/style distinctions, mode renderer, deformasi mesh, stale worker setelah tracking lost, failure inference, shared lease, serta deteksi Vision pada foto reference bundled.

## Checklist perangkat fisik

| Kasus | Acceptance | Status saat dokumentasi dibuat |
| --- | --- | --- |
| Buka fitur | Kamera depan live, status mencari/face detected sesuai keadaan | Belum diuji modul alis pada perangkat |
| Frontal | Dua region tepat pada alis, tidak di mata/hidung/pipi | Belum diuji |
| Dots ↔ Dashed ↔ Both | Attachment tidak berpindah; tampilan berubah | Algoritme/renderer fixture diuji; live belum |
| Straight | Bentuk relatif lurus, bounds mengikuti pengguna | Geometri fixture diuji; live belum |
| Soft/High/Feathered | Arch/strokes benar-benar berbeda | Geometri fixture diuji; live belum |
| Menoleh kiri/kanan, tilt | Guide mengikuti pose dan permukaan, tidak melayang | Belum diuji |
| Dekat/jauh | Ukuran mengikuti proyeksi, tidak digeser/scaled manual | Proyeksi fixture diuji; live belum |
| Angkat alis, ekspresi | Guide bergerak bersama deformasi alis | Deformasi fixture diuji; live belum |
| Wajah keluar frame | Guide hilang saat lost; return memicu mapping baru | State/worker fixture diuji; live belum |
| Refit, background, ganti modul | Hasil lama ditolak; satu owner sesi; tidak membeku | Lease/state diuji; lifecycle live belum |
| Permission denied/unsupported | Pesan dan tindakan jelas, tidak ada overlay palsu | Source/UI Simulator diperiksa |
| Berbagai wajah/cahaya | Catat per-region error dan kasus tidak terpetakan | Belum diuji |

Catat tester, OS/build, mode/style, kondisi cahaya dan langkah reproduksi. Jika mengambil screenshot/video untuk review, lakukan secara eksplisit dengan persetujuan tester. Aplikasi tidak menyimpannya otomatis.

Jangan menandai P0/acceptance live PASS hanya berdasarkan kelulusan unit test, gambar referensi, atau kemampuan build. Belum ada angka pixel error, jitter, FPS atau latency live yang diukur.

## Hasil sesi implementasi

Hasil final build/test ditambahkan di bawah setelah selesai. iPhone 17 terdeteksi terhubung, tetapi Xcode meminta unlock sehingga run/tests fisik dapat terhalang. Catatan fitur makeup lama tidak menjadi bukti modul alis baru.

### Verifikasi akhir — 18 Oktober 2026 — -Nimah

- **Implemented:** real ARKit/Vision pipeline, region mapper, dots, rounded dashed curves, empat style geometry, show/hide, refit, support/permission fallback, Debug mesh/landmarks/status dan satu session manager dengan owner lease.
- **Build verified:** Xcode 26.6 / SDK iOS 26.5, generic iOS signed Debug build **BUILD SUCCEEDED**. Konfigurasi Debug sekarang memiliki SWIFT_ACTIVE_COMPILATION_CONDITIONS DEBUG agar debug controls dan launch shortcut benar-benar dikompilasi. Bundle dan Team existing dipertahankan.
- **Simulator tests:** 50 discovered, **48 passed, 2 hardware tests skipped, 0 failures, TEST SUCCEEDED**. Dua skip adalah native ARKit mesh tests fitur existing yang memang tidak berjalan di Simulator. Tes eyebrow baru termasuk Vision pada foto reference bundled lulus.
- **Simulator Vision:** percobaan awal gagal Code 9 / inference context. Penyelesaian: pilih CPU compute device pada supported compute stages via API iOS 17, hanya pada Simulator. Inference foto bundled kemudian lulus. Provider/pipeline kini membedakan failure inference dari landmark tidak ditemukan.
- **Installed:** build akhir berhasil dipasang pada iPhone 17 terhubung dengan com.sunrise.foundation tanpa uninstall atau menghapus saved looks.
- **Device run blocked:** Xcode meminta unlock; test process dihentikan setelah tidak dapat melanjutkan. Percobaan launch devicectl mengembalikan Locked. Tidak ada tes kamera/face mapping alis pada perangkat yang diklaim lulus.
- **UI checked:** entry Discover → Eyebrow Guide, unsupported message, style selector, dots/dashed/both dan Show guide dilihat di Simulator. QA menemukan DEBUG belum aktif lalu project flag diperbaiki. Pemeriksaan ulang visual build final tertahan karena Mac terkunci; cabang Debug sudah build/test verified, belum diverifikasi visual final.
- **Remaining acceptance:** lokasi dots/curves pada alis asli, EXIF portrait front-camera convention/mirroring, head turn/tilt/dekat/jauh, ekspresi, jitter/latency, occlusion dan keragaman wajah/cahaya. Jangan menandai keseluruhan P0 live PASS sebelum checklist ini dijalankan pada iPhone yang terbuka.
- **Not implemented:** P2 tutorial alis bertahap, feedback benar/salah, ekstraksi style reference, automatic makeup analysis. Modul ini tidak mengaplikasikan virtual makeup.
- Paket source proyek yang sama diperbarui lokal; belum dipush ke GitHub.

-Nimah, preview verification: Simulator 62 tests — 59 passed, 3 hardware skips, 0 failures. Tests cover concave mask/feather, Before isolation and patch movement with mesh deformation. Build iPhone succeeds; live on-face preview and performance remain unverified.

## Verifikasi — -Nimah, 20 October 2026

Simulator: 68 tes, 65 lulus, 3 hardware skip, 0 gagal. Meliputi intersection formula, kebutuhan eye/pupil/nose, penolakan mata tertutup, titik kedua sisi, gate tiga timestamp berbeda, frame berulang/perubahan mapping, loss dan Before/After. Test runner sempat gagal launch karena simulator Busy; pengulangan tanpa parallel runner selesai sukses.

Signed iPhone build berhasil. Percobaan install ditolak CoreDevice karena iPhone terkunci saat developer disk image dipasang (kAMDMobileImageMounterDeviceLocked). Versi Eye & Brow Scan ini belum terpasang dan belum diuji pada wajah nyata. UI controls diperiksa di Simulator; scan live tidak disimulasikan. Source/ZIP lokal diperbarui; belum dipush ke GitHub.

## Koreksi alis terlalu tinggi — -Nimah, 20 October 2026

Penyebab source yang ditemukan: curve live menambah `span * archRatio` di atas level start/tail, sehingga High Arch dapat naik sekitar 10 mm pada span 4 cm. Kini memakai `mapping.arch.y` hasil scan sebagai baseline. Batas delta style kecil dipakai bersama rumus ray yang sama untuk curve dan keypoints; tidak menggeser seluruh overlay ke bawah dengan screen offset.

Kedalaman bidang mata tidak lagi memakai pusat bola mata (`eyeTransform.z`). Vertex mesh nyata di sekitar kelopak diproyeksikan ke sensor dan dicocokkan dengan contour eye; median kedalamannya menentukan bidang pupil. Jika coverage/proximity tidak cukup, scan ditolak. Pusat eye transform hanya membantu identitas sisi dan pencarian area. Ini tetap pendekatan permukaan kelopak berbasis mesh 3D + landmark 2D, **bukan pemindaian 3D pupil/iris secara langsung**.

Verifikasi terbaru: 70 tes, 67 lulus, 3 skip hardware, 0 gagal; signed iPhone build berhasil. Regresi menguji seluruh centerline/arch tidak melewati batas tinggi scan dan kedalaman mesh berbeda dari pusat mata. Batas delta 1 mm bukan hasil pengukuran error di wajah. Perangkat terdeteksi namun masih terkunci (`passcodeRequired: true`); versi koreksi belum dipasang atau diuji live. Setelah memasang build baru, lakukan Refit agar attachment lama tidak dipakai.

-Nimah, final verification 20 October 2026: 72 tests, 69 passed, 3 hardware skipped, 0 failures. Signed iPhone build succeeds. Final observed-brow outline/tutorial build installed successfully on iPhone 17 at 09:13 Asia/Makassar. On-face alignment after installation has not been measured or accepted. Reopen module and Refit to clear previous calibration. Source remains local, not pushed.
