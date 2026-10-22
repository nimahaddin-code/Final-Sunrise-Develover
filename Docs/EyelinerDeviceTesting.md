# Uji wajah nyata: eyeliner — -Nimah

## Menjalankan build yang benar

1. Buka proyek `SunriseApp.xcodeproj` dari folder Final-Sunrise-Develover ini; jangan membuka GlowGuide atau ekstraksi ZIP lama.
2. Pilih scheme SunriseApp, iPhone 17, Team yang sudah terkonfigurasi, lalu Run. Jangan uninstall app karena dapat menghapus saved looks.
3. Pilih Sculpted Glam → Start my tutorial → kalibrasi mata/bibir rileks → Capture before.
4. Next sampai **Eyeliner**. Label harus `Tutorial · Eyeliner only`; full look dan previous steps OFF.
5. Pilih Makeup only, intensity 80%, style default. Bergantian ke Original camera untuk melihat perbedaannya. Points + makeup harus mengikuti strip yang sama; titik memang lebih besar daripada garis.
6. Untuk diagnosis pilih Developer diagnostics → Eye attachments + region IDs. Cyan/magenta membedakan kedua region; jangan menafsirkan warna debug sebagai warna makeup.

## Matriks pengujian

Catat versi OS, build, kondisi cahaya, ukuran wajah, style, mode dan scope. Jangan menilai hanya dari screenshot full look.

| Kasus | Yang dinilai | Hasil saat ini |
| --- | --- | --- |
| Frontal, mata terbuka | Garis tepat di atas bulu mata; hidung/pipi bersih; titik sesuai strip | Belum dinilai pada wajah pengguna |
| Original → Makeup → Points + makeup | Posisi konsisten, hanya visibilitas berubah | Tes render sintetis; live belum dinilai |
| Wing/thickness minimum–maksimum | Bentuk berubah dalam area mata; tidak berpindah region | Algoritme diuji; live belum dinilai |
| Mendekat/menjauh perlahan | Projection mengikuti ukuran/pose; tidak melayang | Live belum dinilai |
| Yaw/pitch/roll bertahap | Attachment mengikuti permukaan; sisi tertutup tidak menembus wajah | Depth render ada; live belum dinilai |
| Kedip satu/dua mata | Efek pada mata berkedip disembunyikan, kembali setelah terbuka | Logic ada; live belum dinilai |
| Buka mulut | Eyeliner tetap di mata; atlas lips disembunyikan bila aktif | Logic ada; live belum dinilai |
| Wajah keluar frame, kembali | Efek hilang saat invalid; tidak membeku | Logic ada; live belum dinilai |
| Refit, background, interruption | Hasil fitting lama tidak diterapkan ke anchor/generation baru | Lifecycle guard ada; live belum dinilai |
| Previous/next, scope | Default satu layer; tidak ada layer eyeliner tertinggal pada langkah lain | Scope unit test; UI live belum dinilai |
| Wajah/eyelid berbeda, cahaya berbeda | Catat error per area; partial fit menyebut keterbatasan | Belum dinilai |

## Format laporan

- Tanggal / tester / perangkat / OS / build:
- Reference / step / scope / mode / style / intensity:
- Cahaya / pose / jarak perkiraan:
- Region yang salah / repro steps:
- Screenshot atau video hanya bila tester menyetujui; penyimpanan dilakukan secara eksplisit, bukan otomatis oleh aplikasi:
- Anotasi upper lash line dan ukuran lebar mata:
- Alignment P50/P95 / jitter / latency: tulis **belum diukur** jika tidak ada alat/data.
- Keputusan: PASS / FAIL / belum diuji. Kelulusan hardware mesh netral harus dicatat terpisah dari wajah nyata.

Jangan melanjutkan klaim akurasi semua fitur sebelum gate eyeliner wajah nyata lolos. Usulan ambang dan backlog ada di MakeupAccuracyPlan.md.

## Retest kasus eyeshadow di pipi — -Nimah

- Build terbaru tidak memakai atlas pada makeup live. Semua area non-eyeliner memakai warna per vertex dari mask yang sama dengan titik; ini perbaikan jalur render, bukan klaim mask anatomi sudah sempurna.
- Pilih **Eyeshadow**, full look OFF, previous steps OFF, Makeup only, intensity 80%.
- Periksa kelopak atas, lalu hidung dan pipi bawah. Jika masih ada warna gelap di bawah, acceptance tetap FAIL.
- Berganti ke Original camera dan Points + makeup; gerakkan kepala/mendekat perlahan. Catat jika warna tidak mengikuti area titik.
- Jangan menyamakan kelulusan render mesh netral dengan ketepatan warna pada wajah nyata. Pengujian bentuk mask/eyelid dan jitter masih harus dilakukan.
