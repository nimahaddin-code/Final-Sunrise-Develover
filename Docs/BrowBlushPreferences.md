## Blush v0.2.1 — feedback perangkat · -Nimah (27 Oktober 2026)

Pengguna mengonfirmasi blush terlihat, tetapi meminta lebih lebar/halus. JSON aktif dan ekspor standalone
`output/blush-reference-v0.2.1/blush-reference.v0.2.1.json` sekarang sinkron untuk enam preset aktif.
Rasio area ellipse desain meningkat sekitar 45–53%; area aktual tetap terkena safe-mask dan bukan diukur
langsung dari foto. Kurva radial memakai smoothstep mix JSON; mask inward tiap batas dikalikan terpisah,
lebar transisi 0.022 W. Grid blush 48x32 tetap dicache; warna/intensitas tidak memicu rebinding.
34 tes makeup lolos, 0 gagal (`/tmp/sunrise-blush-v021-tests.log`), termasuk pembandingan luas/warna off-center
terhadap parameter v0.2.0, kontinuitas tepi, safety mask, actual pixel rendering dan binding reuse.
Revisi ini tetap proposal kalibrasi; penerimaan visual/performa di iPhone pending. Tidak mengubah alis,
eyeliner, hasil scan, atau rute Retake. Tidak memaksa scan ulang.

## Blush v0.2.0 — JSON aktif dan renderer · -Nimah

Revisi JSON berikutnya langsung dihubungkan ke aplikasi dalam pekerjaan yang sama. Tetap perlu build/install;
bukan hot update dari server. Tidak otomatis merge ke staging/main.

Visual lebar/membaur diterjemahkan ke enam preset aktif: radius utama 0.150–0.190 dan radius kecil 0.095–0.115
kali lebar **penuh** wajah, falloff power 1.10–1.15, alpha maksimum 0.44–0.48, intensitas awal 0.72.
`mask_edge_feather` 0.012 W dipakai oleh `BlushPigmentField.coverage` sebagai smoothstep ke dalam batas aman.
Medan warna tetap satu per pipi, tidak mengecil menjadi titik saat terpotong batas dan tidak memakai panah.
Render contract dibundel di `tracking_and_rendering.blush_wide_wash_contract`; parameter runtime dikonsumsi
oleh decoder/generator/renderer, bukan sekadar instruksi teks. Rules/palettes alis dan Hanum eyeliner dipertahankan.
Revisi ini target visual hasil arahan pengguna, belum ukuran yang dikalibrasi di perangkat atau jaminan pixel-identik.

## Kalibrasi ukuran alis v0.1.1 — -Nimah

Feedback pengguna: badan alis terlalu kecil. Salinan JSON integration memakai half-thickness 0.065 dari
panjang alis teramati (sebelumnya 0.035). Ini ketebalan desain yang dikalibrasi, bukan ketebalan hasil deteksi.
Sumber penelitian v0.1.0 di workspace tidak ditimpa. Panjang kepala-ke-ekor dan batas displacement tetap.

## Implementasi JSON di integration — 26 Oktober 2026 · -Nimah

`integration/latest-hanum-khalish` membundel JSON penelitian utuh, tanpa mengubah status draft sumber.
Mode integrasi mengaktifkan preset untuk kalibrasi sesuai permintaan pengguna. Tidak ada database jaringan.
`MakeupRuleDatabase` memvalidasi join assignment, keunikan ID, parameter wajib, unit, batas numerik, dan RGB.
Kegagalan decode tidak kembali diam-diam ke assignment lama.

Rasio blush dikalikan **lebar penuh** mesh wajah dalam meter. Mata tiap sisi menjadi anchor; sumbu native
ARKit face-local mengikuti pose melalui barycentric attachments. Radius dan sudut JSON tidak diperbesar lagi
oleh renderer. Warna adalah satu medan alpha `(1-r²)^power` per pipi. Mask hidung konservatif dipakai jika
formula ala tidak tersedia. Batas mata saat ini memakai proksi konservatif pusat mata, belum kontur kelopak
terukur. Tidak ada masking tangan/hijab untuk brow/blush; eyeliner Hanum tetap menggunakan jalurnya sendiri.

Alis mempertahankan centerline observasi, dengan dua segmen cubic dan displacement maksimum JSON. Ketebalan
awal adalah rasio desain terhadap lebar alis, bukan diakui sebagai ketebalan yang terukur dari Vision.
Head fade, taper dan edge feather menjaga ujung lebih lembut. Palette dan intensitas awal dibaca dari JSON.
Warna custom tidak mengganti preset penempatan. Before/After dan kategori tunggal tetap berlaku.

Database sumber: `output/makeup-reference-database-v1` pada workspace SUNRISE. Tes geometri/simulator tidak
membuktikan akurasi wajah nyata. Validasi visual iPhone masih diperlukan sebelum publikasi staging.

## Koreksi kegagalan persiapan awal — -Nimah

Frame yang ditawarkan selama face scan dibatasi 400 ms dengan satu pekerjaan aktif; collector berhenti setelah
fit berhasil. Frame akhir yang buruk tidak menghapus hasil valid. Pemetaan awal memakai kontur alis terdeteksi
meski titik tambahan pupil/hidung tidak tersedia. Garis rumus tidak dibuat jika datanya tidak ada.
Rekomendasi eyeliner netral tidak lagi memblokir pembukaan aplikasi. Jika fitting tetap gagal, hasil klasifikasi
dipertahankan dan pengguna bisa melanjutkan dengan kategori tersedia. Brow/blush tanpa fit diberi keterangan
dan dinonaktifkan; tidak ditampilkan sebagai sukses. Tidak ada pengukuran ulang di try-on.

---

## Scan hanya di awal aplikasi — -Nimah

Setiap cold launch: face scan → eye scan → persiapan fit makeup di awal → try-on. Welcome hanya muncul pertama kali.
Scan bukan autentikasi identitas; yang diukur tetap bentuk wajah/mata. Tidak ada klasifikasi/kalibrasi ulang per fitur.
Frame akhir face scan digunakan untuk Vision pemetaan alis/pipi di background selama layar awal masih aktif.
`LaunchMakeupFit` menahan attachment/mesh di memori sesi aplikasi saja; foto tidak disimpan, data tidak diupload.
Try-on memakai attachment ini dengan vertex ARKit live; anchor baru diperbolehkan hanya dengan topologi yang sama.
Tracking gerakan masih diperlukan untuk menempelkan overlay, tetapi tidak meminta user scan/diam/mengatur jarak lagi.
Alis, blush, eyeliner yang punya assignment valid langsung aktif. Tidak ada tombol scan ulang di try-on.
Pindah tutorial, color picker, dan kembali ke home tidak mengulang flow awal. Gagal persiapan ditangani di awal.
Referensi pear/rectangle tetap belum tersedia; cache fitting tidak mengarang rekomendasi yang belum ada.

---

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
Data aktif dibaca sekali dari JSON lokal `Resources/makeup-reference.database.json` oleh `MakeupRuleDatabase`.
`assignedBrowIDs` dan `assignedBlushIDs` menetapkan ID stabil; varian penelitian tetap disimpan
untuk provenance, tanpa picker A/B/C. Pilihan JSON menggantikan default A sebelumnya. Semua parameter masih proposal kalibrasi,
bukan hasil pengukuran poster atau klaim style universal.

Sejak 2026-10-27 daftar bentuk alis diganti dengan sembilan bentuk baru (urutan picker): Bold arch, Slim arch,
Soft natural, Flat straight, Curved arch, Peaked angle, Slim straight, Full arch, Bold straight. Kategori bentuknya
mengikuti tangkapan layar efek TikTok dari pengguna (`brow_D` di `source_registry`); parameternya usulan engineering.
Arah referensi per bentuk wajah dipetakan ke bentuk terdekat; tabel riwayat di bawah memakai nama lama.

| Hasil wajah | Eyebrow | Blush |
| --- | --- | --- |
| Oval | C · soft natural | B · cheekbone |
| Round | C · bold arch | D · high cheekbone |
| Square | C · curved arch | B · apple |
| Oblong | C · flat straight | D · horizontal |
| Heart | B · slim straight | B · center cheek |
| Diamond | C · slim arch | A · temple sweep |
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
