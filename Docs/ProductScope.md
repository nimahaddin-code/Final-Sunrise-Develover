# Scope MVP

> -Nimah · 22 October 2026: Eyebrow/blush sekarang memiliki pilihan face shape manual, preset berbasis referensi, eksplorasi, preview Before/After dan tutorial. Input analisis Holly siap diterima, classifier belum tersambung; satu region aktif, bukan full-look gabungan. [Scope dan batas](BrowBlushPreferences.md).

> -Nimah, 19 October 2026: scope terbaru mencakup closed eyebrow outline, lima forehead style dan tutorial manual. Baca [BrowForeheadGuide](BrowForeheadGuide.md) untuk status terbaru, batas hairline dan testing; catatan sebelumnya di bawah adalah riwayat.

> -Nimah: Acuan placement terbaru: [MakeupAccuracyPlan](MakeupAccuracyPlan.md) dan [EyelinerDeviceTesting](EyelinerDeviceTesting.md). Catatan di bawah dapat mencakup iterasi historis. Eyeliner kini strip attachment, bukan atlas; full look default OFF.

Tanggal: 15 Oktober 2026. Author kode implementasi: `-Nimah`. Produk sementara: SunriseApp.

| Fitur | Status implementasi | Verifikasi yang diperlukan |
| --- | --- | --- |
| Onboarding / empat look / detail | Implemented | UI dan relaunch |
| Photo inspiration | System PhotosPicker, preview, pilih style manual | iCloud/large asset/cancellation di perangkat |
| Support check / permission | Implemented, fallback manual | Supported/denied Settings return |
| Calibration / blush mesh | POC implemented | Wajib uji iPhone fisik, placement belum tervalidasi |
| Lima langkah tutorial | Implemented, empat langkah manual | Content/layout accessibility |
| Before/After | Actual camera snapshots, no scoring | Orientasi/mirroring/lighting di iPhone |
| Save/load/delete | Local actor per-result folder | Unit regression + physical end-to-end |

Manual mode hanya tutorial, tanpa camera capture/save. Foto referensi tetap di memori; hanya capture Before/After yang disimpan. Belum ada AI analysis, skin/face-shape analysis, cloud, atau AR contour/eyeshadow/eyeliner/lips.

Label `-Nimah` menandai kode yang dibuat dalam fase ini. Nama Khalish/Hanum di dokumen adalah usulan tanggung jawab iterasi, bukan klaim siapa menulis kode tersebut.

## Referensi glam + dotted guide

Sculpted Glam ditambahkan dari foto yang diberikan pengguna. Template titik di lima area dibuat manual dan mesh-attached. Blush memiliki pilihan Dots/Soft area; tahap lain pada look ini titik saja, bukan virtual color makeup. Look sebelumnya tidak berubah cakupannya (AR blush + instruksi manual lainnya). Sketsa titik tersedia di mode manual dan detail. Tidak ada analisis otomatis foto atau jaminan wajah identik.

## Status live try-on terbaru

Sculpted Glam kini mempunyai virtual preview warna + titik, full-look/current-step, opacity, Original comparison dan Refit. Template sketsa tidak lagi menjadi dasar live fitting. Camera image yang disimpan tetap asli tanpa virtual color. Tidak ada lash generation, foundation/skin smoothing, makeup transfer otomatis, atau jaminan hasil identik. Ketepatan pixel eyelid/wing/lip boundary belum terbukti; partial fit menyembunyikan area yang tidak ditemukan.

## Eyebrow iteration — -Nimah

Eyebrow Guide adalah modul placement guide terpisah dari warna makeup lama, memakai real Vision + shared ARKit session. Empat style mengubah geometri, bukan label. P0/P1 source dan algoritme tersedia untuk uji perangkat; acceptance tracking/placement wajah nyata belum selesai karena perangkat terkunci. P2 belum dibuat. Batas mapping dan confidence ada di EyebrowModule.md.
