## Warna dan foto palet — -Nimah

User melihat try-on rekomendasi terlebih dahulu. Shade tidak mengubah assignment wajah/placement.
Blush: 01 Pink, 02 Peach, 03 Winter Pink, 04 Muted Mauve; eyebrow: B201 Bistre, B202 Brown,
B203 Chocolate, B204 Tan, serta Soft black. Nilai sRGB adalah pendekatan visual dari referensi pengguna,
bukan hasil pengukuran produk. Intensitas dan Before/After tersedia sebelum tutorial.

Tombol eyedropper membuka color picker manual, pilih foto dari Photos, atau foto palet menggunakan kamera belakang.
Ketuk bagian warna pada foto, cek swatch, lalu Use this colour. Cancel tidak mengubah shade.
Foto dibatasi maksimum 1024 pixel, disesuaikan orientasi EXIF, dan disampling dari piksel sRGB dengan area 3×3;
ketukan pada letterbox diabaikan. Pemrosesan gambar di background. Foto hanya di memori, tidak disimpan/upload.
Kamera wajah dihentikan selama sheet terbuka sehingga kamera belakang tidak berebut sesi.
Panah tutorial membawa warna/intensitas yang sudah dicoba ke langkah pertama tutorial rekomendasi yang sama.

Uji iPhone: pilih semua preset; ubah warna manual; import foto portrait/landscape; tap pan warna, bukan packaging;
ambil foto kamera belakang, Apply, lalu pastikan tracking wajah kembali; batalkan picker; buka tutorial dan cocokkan
warna/placement. Ulangi setelah background/foreground dan cek penolakan akses kamera. Foto tidak menjamin colour match
karena cahaya, white balance, dan warna layar berbeda.

---

## Rekomendasi otomatis dari hasil scan — -Nimah

Alur pengguna menampilkan satu hasil per kategori, bukan pilihan semua referensi.
Data saat ini adalah katalog lokal `MakeupPreferenceCatalog`, bukan database server.
`assignedBrowIDs` dan `assignedBlushIDs` menetapkan ID stabil; varian penelitian tetap disimpan
untuk provenance, tanpa picker A/B/C. Aturan MVP ini mempertahankan default sebelumnya secara eksplisit,
bukan klaim satu style yang paling benar untuk setiap orang.

| Hasil wajah | Eyebrow | Blush |
| --- | --- | --- |
| Oval | A · upward brow | A · outer sweep |
| Round | A · defined angle | A · apple |
| Square | A · rounded curve | A · placement dots |
| Oblong | B · straight | B · wide horizontal |
| Heart | B · low arch | A · upper inner |
| Diamond | A · soft arch | A · temple sweep |
| Triangle / pear, rectangle | Belum ada data | Belum ada data |

Data kosong atau tanpa scan: overlay kategori tersebut mati dan tidak diganti style generik.
Scan ulang memperbarui assignment di home; warna, intensitas, Before/After, dan on/off tetap tersedia.
Eyeliner menggunakan `EyelinerPlanner` Hanum dan output mata Khalish, bukan label bentuk wajah.
Hanya hasil personal yang diekspos; hasil mata yang tidak jelas meminta eye scan, bukan katalog liner.
Profile membuka ringkasan hasil dan akses scan ulang. Panah home membuka tutorial kategori aktif.
Akurasi posisi dan kenyamanan kamera harus diuji pada iPhone; tes simulator tidak memvalidasi hasil visual.

---

# Eyebrow & Blush Preferences

> -Nimah · 22 October 2026, scan recovery: reset/loss now invalidates old worker ownership, failed area generation retries after a cooldown, and scan UI explains positioning (near/far, movement, eyes and pose) with Scan ulang. Distance 25–60 cm is a starting suggestion, not an enforced hardware limit. Signed iPhone build succeeded and installed on Nimah New at 06:27. Simulator: 80 tests, 77 passed, 3 hardware skipped, 0 failures. Real-face repeat-use acceptance remains pending. Previous installation/test notes below are historical.

-Nimah · 22 October 2026

## Cara mencoba

Buka **Discover → Brow & Blush Studio** pada proyek SunriseApp yang sama. Kamera → scan landmark stabil → pilih bentuk wajah → Eyebrows atau Blush → pilih kartu referensi → Before/After → tutorial. Simulator menampilkan pilihan dan tutorial dengan pesan kamera tidak tersedia; tidak memalsukan tracking.

Pilih bentuk wajah manual selama analisis Holly belum tersambung. Tersedia delapan kategori dan Not sure. Change dapat mengganti pilihan. Referensi adalah preferensi estetika, bukan aturan universal. Satu region aktif ditampilkan pada satu waktu; belum ada preview gabungan eyebrow dan blush.

Before menyembunyikan makeup dan guide; After menampilkan simulasi. Intensity mengatur warna. Placement guide mengatur outline. Tutorial berjalan manual dan tidak menilai aplikasi makeup pengguna.

## Preset dari referensi pengguna

| Bentuk wajah | Eyebrow | Blush |
| --- | --- | --- |
| Oval | A lifted; B soft arch; C natural | A outer sweep; B/C cheekbone; D apple |
| Bulat | A angular; B/C high arch | A apple; B/C cheekbone; D high lift; E apple* |
| Persegi | A rounded; B angular; C rounded | A placement dots; B/C apple; D diagonal blend; E horizontal oval* |
| Lonjong | B/C straight | B/C/D horizontal blend |
| Persegi panjang | Tidak dipisahkan oleh sumber | Tidak dipisahkan oleh sumber |
| Hati | B low arch; C thin, berlabel inverted triangle | A upper-inner; B/C center; D center/down; E inner cheek, berlabel inverted triangle* |
| Diamond | A/B/C soft arch | A temple sweep; E temple sweep* |
| Triangle/Pear | Referensi triangle ambigu; tidak ditetapkan | Referensi triangle ambigu; tidak ditetapkan |

*E hanya interpretasi area pipi dari anotasi foto. Tanda di hidung/dagu dan warna garis yang tidak dijelaskan tidak dijadikan instruksi blush. Label angular face tidak disamakan otomatis dengan persegi; face length tidak disamakan otomatis dengan lonjong.

B eyebrow merupakan pembacaan visual. A blush juga pembacaan visual. UI menandai evidence sumber, bukan menyebut semuanya rekomendasi tervalidasi. Rectangle, pear dan unknown menawarkan eksplorasi manual, tanpa mengarang dukungan sumber. Explore other styles menghapus atribusi referensi yang dipilih sebelumnya.

[Chart blush asli pengguna](References/BlushPreferenceComparison.png) · [Chart eyebrow asli pengguna](References/BrowPreferenceComparison.png)

## Implementasi dan batas presisi

Alis mengikuti centerline least-squares dari landmark alis terdeteksi serta span aktual, kemudian variasi style kecil. Thin mengubah ketebalan; bukan menaikkan seluruh outline ke template. Rumus nose–pupil–outer eye tetap referensi opsional, bukan penentu tinggi outline. Bentuk preview tidak dijanjikan identik dengan gambar sumber dan belum berupa segmentasi rambut.

Blush memiliki 12 variasi placement. Area ditentukan relatif terhadap landmark mata/hidung dan lebar mesh wajah, kemudian diikat ke triangle permukaan. Boundary, guide dan patch warna mengikuti vertex terbaru ketika wajah bergerak. Area dibatasi ke sisi luar hidung dan di bawah mata. Tutorial mengarahkan area dan arah baur. Tekstur warna memiliki tepi lembut, tetapi belum simulasi kosmetik fotorealistis.

Scan memerlukan landmark mata, alis dan hidung terlihat dan beberapa observasi stabil. Ini landmark 2D yang diproyeksikan ke mesh ARKit, bukan pemindai iris 3D. Belum ada segmentasi rambut/hijab/tangan, penyesuaian warna otomatis terhadap pencahayaan, atau jaminan presisi semua pose/jarak. Bila mapping tidak valid, guide tidak dipublikasikan sebagai siap. Uji wajah nyata tetap wajib.

## Kontrak Holly dan Hanum

Holly memasok hasil ke `FaceShapeAssessment(shape: .oval, origin: .analysis, confidence: nil)` dan meneruskannya melalui parameter `assessment` pada `EyebrowOverlayView(checker:assessment:)`. Pada view model gunakan `applyAssessment(_:)`. Nilai confidence opsional, bukan ukuran akurasi overlay. Classifier belum dibuat dalam modul ini. Mapping label: oval, round, square, oblong, rectangle, heart, diamond, pear; unknown untuk hasil tidak pasti. Manual override tetap tersedia dan ditandai Selected manually.

Nimah memiliki katalog preferensi, fitting eyebrow, blush placement, preview dan tutorial. Hanum tetap memiliki eyeliner; perubahan ini tidak menambahkan sesi kamera kedua atau memindahkan kepemilikan eyeliner. Integrasikan kontrak model terlebih dahulu, koordinasikan project.pbxproj, lalu uji satu shared ARSession.

Source utama: Features/MakeupPreferences, Features/Eyebrow, Features/Forehead/ForeheadSceneRenderer.swift dan Features/LiveGuide/LiveGuideView.swift. Renderer area bersama dipakai ulang untuk blush. Seluruh tambahan diberi penanda -Nimah.

## Verifikasi 22 October 2026

- Signed build iPhone: berhasil.
- Simulator: 78 tes dijalankan, 75 lulus, 3 hardware skip, 0 gagal.
- Tes mencakup katalog, sumber ambigu/tidak tersedia, manual override, pergantian style, batas area blush, deformasi mesh, Before dan hilangnya tracking.
- UI simulator: pemilihan bentuk wajah, kartu blush A–E, sumber pilihan dan masuk tutorial diperiksa. Kamera live tidak tersedia di simulator.
- Instalasi build terbaru ke iPhone belum berhasil: koneksi perangkat terputus (connection reset). Akurasi wajah nyata dan performa belum diverifikasi. Build sukses bukan bukti placement sudah presisi.

Uji iPhone: scan ulang; coba A/B/D pada wajah yang sama; bandingkan Before/After; gerakkan dekat/jauh dan menoleh; pastikan alis mengikuti rambut, blush tetap di pipi, dan hilang saat tracking gagal. Periksa kedua sisi wajah, ekspresi/senyum, cahaya berbeda, dan tepi hijab. Catat PASS/FAIL serta screenshot yang diizinkan sebelum mengklaim acceptance.

## Follow-up: kamera bergerak tetapi overlay hilang — -Nimah

Laporan pengguna setelah build scan recovery: percobaan kedua tetap kehilangan overlay meskipun kamera bergerak. Perbaikan sebelumnya belum terbukti menyelesaikan gejala perangkat. Iterasi ini menangani dua jalur terpisah: pilihan Before/Hide/intensity nol tidak terbawa diam-diam ke percobaan preset/region berikutnya; kalibrasi pada anchor yang sama disimpan selama dropout tracking kurang dari satu detik, dengan overlay tetap disembunyikan selama tracking tidak valid. Loss lebih lama atau anchor baru tetap memerlukan kalibrasi baru. Ini belum membuktikan penyebab tunggal laporan pengguna.

Tombol Tampilkan ulang makeup / Scan ulang tersedia pada pilihan style dan tutorial. Memilih Before atau Hide masih berlaku sampai pengguna memilih percobaan baru atau menekan tombol tersebut. Tidak ada overlay yang ditampilkan saat tracking hilang. Tes regresi mencakup Before → preset berikut, guide hidden → region berikut, dropout pendek → resume tanpa Vision baru, dropout panjang → mapping baru. Acceptance di wajah nyata tetap menunggu percobaan pengguna.

Verifikasi iterasi follow-up: 81 tes / 78 pass / 3 hardware skip / 0 fail; signed build berhasil, instalasi iPhone 17 Nimah New berhasil pada 08:32. Live repeat-use acceptance belum dikonfirmasi.
