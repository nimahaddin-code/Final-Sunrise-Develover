# Prompt untuk look baru (Lip, Contour, dan lainnya)

Prompt siap tempel untuk AI coding (Claude Code, Codex, dll.) saat menambah tool makeup baru ke Dandan. Alurnya sama
dengan blush, alis, dan eyeliner. Setiap tool baru dibangun dalam 7 tahap. **Setiap tahap = satu prompt = satu PR ke
`staging`.** Jangan gabungkan semua tahap dalam satu prompt, karena PR-nya jadi terlalu besar untuk dicek dan dites di HP.

## Cara pakai

1. Pilih tool baru, misalnya Lip. Salin **Spesifikasi look** untuk tool itu (bagian bawah dokumen). Kalau tool-nya
   belum ada di dokumen ini, isi **Template spesifikasi** dulu.
2. Untuk setiap tahap, susun prompt dari tiga bagian ini, berurutan:
   - **Konteks bersama**
   - spesifikasi look
   - prompt tahap yang dikerjakan
3. Kerjakan tahap 1 sampai 7 berurutan. Tahap berikutnya dimulai setelah PR tahap sebelumnya masuk `staging`.
4. Setelah tahap 2, 3, 4, dan 6 selesai, cek di HP. Simulator tidak punya kamera wajah.

| Tahap | Isi | Bisa dicek di |
| --- | --- | --- |
| 1 | Fondasi: tool baru muncul di semua alur, masih placeholder | Simulator |
| 2 | Pilihan look dan render di Try On | HP |
| 3 | Foto Expected dan Look Brief (perlengkapan) | HP |
| 4 | Tutorial langkah demi langkah | HP |
| 5 | Feedback: pengukuran, aturan, skor | Simulator (wajah buatan) + HP |
| 6 | Teks Indonesia | Simulator |
| 7 | Kalibrasi di HP | HP |

---

## Konteks bersama

Tempel blok ini di awal **setiap** prompt tahap.

```text
Kamu bekerja di repo iOS "Dandan" (SwiftUI, ARKit, Metal, MediaPipe). App ini mengajari makeup lewat kamera depan.
Tool yang sudah ada: blush, eyebrow, eyeliner. Aku menambah tool baru: <NAMA TOOL>. Spesifikasinya ada di bawah.

ALUR PER TOOL (AppRoute, jangan diubah urutannya)
Home (FeatureHomeView) -> Try On (.tryOn) -> foto Expected (.capture(.desired)) -> Look Brief (.lookBrief)
-> Tutorial (.recommendedTutorial) -> foto Result (.capture(.result)) -> Feedback (.feedback) -> Home.

WAJIB DIBACA DULU
- AGENTS.md dan CHANGELOG.md (entri teratas = perubahan terbaru), Docs/Architecture.md, Docs/NavigationFlow.md,
  Docs/CodeOwnership.md, Docs/GayaBahasa.md.
- Tool yang paling mirip sebagai contoh:
  - makeup area (warna di permukaan kulit): Blush, di SunriseApp/Features/Blush/ (TryOn, Tutorial, Feedback, Info,
    Engine) dan SunriseApp/Engine/BeautyBlushEngine.swift;
  - makeup garis: Eyeliner (SunriseApp/Features/Eyeliner/) dan Brow (SunriseApp/Features/Brow/).
- Bagian bersama: SunriseApp/Features/Screens/ (TryOn, Tutorial, Flow), SunriseApp/Engine/Feedback/ (FaceScan,
  FeedbackRules, LineProfile, PhotoAlignment), SunriseApp/Engine/Info/ToolInfo.swift,
  SunriseApp/Engine/Rules/MakeupRecommendation.swift, dan database di SunriseApp/Resources/
  (makeup-feedback.database.json, makeup-score.database.json, makeup-reference.database.json).

ATURAN
1. Kode tool baru masuk ke folder sendiri: SunriseApp/Features/<Tool>/{TryOn,Tutorial,Feedback,Info,Engine}.
   File bersama cukup diubah di bagian `switch` / `case`. Jangan ubah perilaku blush, alis, atau eyeliner.
2. Tidak ada networking, analytics, atau upload. Foto, frame, dan hasil ukur hanya di memori selama satu alur.
3. Ukuran wajah selalu dari mesh ARKit (titik FaceScan, milimeter di ruang wajah), diukur pada frame kamera yang sama
   dengan fotonya (`ScreenShot` dari engine, lihat FeatureCaptureView.shoot). Jangan ukur dari frame live yang lain.
4. Teks UI pakai suara "kakak" (Docs/GayaBahasa.md). Pesan feedback memakai bahasa yang lebih formal dan tidak boleh
   berisi angka mm, derajat, persen, atau "x". Gunakan kata panduan, misalnya "area garis putus-putus" atau
   "dari Try On". Setiap string baru juga ditambahkan ke Localizable.xcstrings (id, state "needs_review").
5. Project Xcode tidak memakai folder tersinkron: file Swift baru harus ditambahkan ke target di project.pbxproj.
   Commit hanya baris file baru itu. JANGAN commit perubahan DEVELOPMENT_TEAM (itu signing lokal).
6. Branch dari `staging`, PR ke `staging`. Jangan merge sendiri.
7. Tes dijalankan dengan:
   xcodebuild test -project SunriseApp.xcodeproj -scheme SunriseApp \
     -destination 'platform=iOS Simulator,name=<iPhone kamu>' CODE_SIGNING_ALLOWED=NO
   Semua tes harus lolos. Tambahkan tes untuk kode baru.
8. Tambahkan entri di atas AGENTS.md (apa yang berubah, kenapa, apa yang belum dicek di HP) dan CHANGELOG.md
   (2-3 poin), dengan nama penulis dan tanggal.
9. Di akhir, laporkan apa yang sudah jalan, apa yang belum dicek di HP, dan apa yang masih placeholder.
```

---

## Tahap 1 — Fondasi

```text
TAHAP 1: FONDASI. Tambahkan <NAMA TOOL> sebagai tool baru yang muncul di seluruh alur, dengan isi placeholder dulu.

Kerjakan:
1. Tambahkan case baru di `TryOnTool` (TryOnHomeModel.swift): title, symbol (SF Symbol), dan category. Tambahkan juga
   case di `MakeupCategory` (MakeupRecommendation.swift).
2. Cari semua `switch` atas TryOnTool / MakeupCategory (grep "case .eyeliner") lalu isi case baru di setiap tempat:
   MakeupFlow.swift (styleTitle, mustHave, nearby), FeatureHomeView, TryOnFeature, LookBriefView, GuidedTutorialView,
   TutorialStepsSheet, FeedbackView (lookTitle), FeedbackRules, ToolInfo, MakeupTextureBaker, MakeupTextureRenderer,
   FaceFit. Jangan pakai `default:` untuk menyembunyikan case.
3. Tambahkan field look yang dipilih ke `TutorialHandoff` (contoh: `lipLook: LipLook? = nil`), meniru blushStyle.
4. Buat SunriseApp/Features/<Tool>/Info/<Tool>Info.swift yang mengisi ToolInfo (nama look, deskripsi, tools,
   products), meniru BlushInfo.swift.
5. Isi mustHave dan nearby dari spesifikasi, dengan gambar `kit-*` kalau sudah ada dan SF Symbol kalau belum.
6. Kartu tool baru muncul di Home. Try On, Tutorial, dan Feedback boleh menampilkan placeholder
   ("Segera hadir" atau kamera polos), tapi alurnya harus bisa jalan dari awal sampai akhir di Simulator
   ("Continue without photo").
7. Tes: GuidedFlowTests (atau tes baru) memastikan tool baru melewati semua route tanpa crash, dan tool lama tidak berubah.

Belum perlu: render makeup, tutorial, atau feedback asli.
```

## Tahap 2 — Pilihan look dan render di Try On

```text
TAHAP 2: TRY ON. Tampilkan look <NAMA TOOL> di wajah secara live.

Kerjakan:
1. Model look di Features/<Tool>/TryOn/: enum/struct look dengan id, title, deskripsi, dan parameter bentuk
   (titik mesh ARKit atau landmark yang jadi patokan, ukuran, kelembutan tepi). Daftar look ada di spesifikasi.
2. Picker look: <Tool>LookPicker meniru BlushLookPicker (GlassPickerRow + StyleCircle, circle pertama = tanpa makeup),
   plus ikon per look di StyleIcons.swift.
3. Shade dan intensitas memakai sistem yang sama dengan blush (PaletteColorPicker, handoff.shades, handoff.intensities).
4. Render:
   - Makeup area (lip, contour, highlighter, eyeshadow): pakai jalur Metal ARKit-UV seperti blush
     (BeautyBlushEngine + atlas tekstur). Gambar mask look di ruang UV mesh ARKit, lalu warnai di shader. Tambahkan
     region/mode baru, jangan ubah jalur blush.
   - Makeup garis: ikuti pola eyeliner (overlay dari landmark MediaPipe).
   - Ikuti aturan oklusi dan tepi dari spesifikasi (misalnya gigi dan bagian dalam mulut untuk lip).
5. Target terukur: engine menyediakan outline target (seperti BlushGuideSnapshot) supaya foto Expected bisa membaca
   area yang digambar.
6. Tombol Continue di Try On tetap mati sampai ada look yang dipilih.
7. Tes: unit test untuk geometri look (mask di posisi yang benar pada mesh buatan, simetris kiri-kanan). Kalau bisa,
   render fixture seperti BeautyBlushEngine.renderAtlasFixture.

Laporkan apa yang perlu dicek di HP: posisi, tepi, ikut gerak kepala, cahaya.
```

## Tahap 3 — Foto Expected dan Look Brief

```text
TAHAP 3: FOTO EXPECTED + LOOK BRIEF.

Kerjakan:
1. FeatureCaptureView.cameraConfiguration: untuk tool baru, foto .desired menggambar look-nya, dan foto .result tetap
   menjalankan engine tanpa pigmen (kamera polos), meniru blush (measuresBlushTarget, pigmentHalf none).
2. Saat shutter, outline target tool ini ikut disimpan (seperti `outline` di FaceScan). FaceScan diukur dari frame
   `ScreenShot` yang sama dengan fotonya. Pastikan baris developer menunjukkan "frame same".
3. LookBriefView: foto Expected, nama look, deskripsi, dan perlengkapan dari ToolInfo/mustHave/nearby. Crop wajah
   mengikuti area tool (seperti `LookBriefView.crop` untuk mata).
4. FeedbackPointCheck (developer tools) harus menampilkan titik pink tepat di makeup virtual tool ini pada foto Expected.
5. Tes: FaceScan buatan dengan `rendered` di area target -> FeedbackPointCheck.changed hanya berisi titik di area itu.
```

## Tahap 4 — Tutorial

```text
TAHAP 4: TUTORIAL.

Kerjakan:
1. Features/<Tool>/Tutorial/<Tool>Tutorial.swift: daftar lesson (FaceGuideLesson: judul pendek + instruksi
   maksimal ±12 kata) dari spesifikasi, meniru BlushTutorial.swift.
2. Overlay panduan yang menempel di wajah per langkah (garis putus-putus target, animasi tangan atau kuas), meniru
   BlushTutorialOverlay. Overlay mengikuti pengaturan Reduce Motion dan thermal state.
3. Kalau tool punya sisi kiri/kanan, ikuti tutorial per sisi yang sudah ada (sideLayout, swipe antar langkah, tombol
   compare: sisi yang sedang dikerjakan kamera polos, sisi lain look target). Tool tengah seperti lip boleh satu sisi
   saja, sesuai spesifikasi.
4. TutorialStepsSheet: gambar langkah `tutorial-<tool>-1…n` kalau sudah ada, kotak abu kalau belum.
5. Tes: jumlah lesson = jumlah langkah overlay; tutorial bisa maju/mundur dan selesai ke foto Result.
```

## Tahap 5 — Feedback

```text
TAHAP 5: FEEDBACK. Bandingkan foto Expected (target) dengan foto Result (hasil), lalu beri skor dan pesan.

Kerjakan:
1. Features/<Tool>/Feedback/<Tool>Feedback.swift, meniru BlushFeedback (makeup area) atau EyelinerFeedback/BrowFeedback
   (makeup garis):
   - Target = titik mesh yang warnanya diubah makeup virtual di foto Expected (rendered vs lab), atau outline engine.
   - Hasil = titik mesh di foto Result yang berubah dibanding kulit polos. Pakai FeedbackSkin.shift untuk koreksi
     cahaya dan FeedbackPhotoCheck untuk cek foto.
   - Hitung metrik dari spesifikasi (cakupan, offset, ukuran, ketajaman tepi, warna, intensitas, simetri).
   - Batasi area pencarian supaya bagian wajah lain tidak terbaca sebagai makeup (pelajaran dari blush: kelopak mata
     pernah terbaca sebagai blush).
   - Rekam Mark per sisi (`FaceScan.mark` / `FeedbackRecorder.mark`) supaya kartu "Benerin ini dulu" bisa menandai foto.
2. makeup-feedback.database.json -> tools.<tool>: part_vocab, looks, rules (id, metric, direction, priority, weight,
   suppresses, messages per band slight/clear/large dalam en + id: title, say, steps), praise, dan symmetry.
   Rule "<tool>.none" untuk makeup yang tidak ditemukan.
3. makeup-score.database.json -> tools.<tool>: kartu placement dan shade dengan metric, weight, dan thresholds ok/slight/clear.
4. Sambungkan ke FeedbackComposer.assemble dan provider feedback sesuai tool. Tambahkan cek foto khusus tool
   (misalnya mulut terbuka atau tersenyum untuk lip) di bagian capture database.
5. Tes dengan wajah buatan seperti BlushFeedbackTests / LineFeedbackTests:
   - makeup tepat di target -> skor >= 0.9 dan ada pujian
   - setiap rule utama terpicu oleh kasus yang sesuai
   - tidak ada makeup -> "<tool>.none" di kedua kartu dan tanpa pujian
   - tidak ada pesan yang berisi angka atau placeholder `{}` (seperti testNoMessageShowsMeasurements)
   - mark pertama ada di sisi yang benar
```

## Tahap 6 — Teks Indonesia

```text
TAHAP 6: TEKS INDONESIA. Ikuti prompt di Docs/GayaBahasa.md.

Kerjakan:
1. Cari semua string baru tool ini di Localizable.xcstrings yang belum punya terjemahan "id" atau masih kosong.
2. Tulis versi Indonesia: UI dengan suara kakak, pesan feedback lebih formal tanpa angka. Istilah makeup yang memang
   dipakai cewek Indonesia tetap bahasa Inggris (lip tint, lip liner, contour, blend, shade).
3. Periksa en/id di makeup-feedback.database.json untuk tool ini: arti sama, panjang id maksimal ±120% dari en, dan
   placeholder ({part}, {zone}) sama persis.
4. Masukkan key di posisi alfabet (tanpa membedakan huruf besar/kecil), state "needs_review".
```

## Tahap 7 — Kalibrasi di HP

```text
TAHAP 7: KALIBRASI. Aku akan kirim screenshot dari HP: layar feedback dengan developer tools menyala (baris "shutters",
"rules", dan foto titik Expected/Result), untuk tiga percobaan:
(a) makeup tepat seperti Try On, (b) makeup sengaja meleset, (c) tanpa makeup.

Kerjakan:
1. Untuk setiap percobaan, cek apakah titik pink duduk di makeup, apakah "frame same" muncul, dan apakah rule yang
   muncul cocok dengan yang sengaja dibuat.
2. Kalau titik meleset: cari masalah koordinat dulu sebelum mengubah ambang.
3. Kalau titik sudah pas tapi skor salah: sesuaikan ambang di database (detection, thresholds), bukan di kode, dan catat
   alasannya di AGENTS.md.
4. (a) harus dapat skor tinggi, (b) harus menyebut kesalahan yang benar, (c) harus "<tool>.none" tanpa pujian.
   Tambahkan tes wajah buatan untuk setiap kasus yang diperbaiki.
```

---

## Spesifikasi look: Lip

```text
SPESIFIKASI: LIP
Jenis: makeup area di tengah wajah (bibir atas + bawah). Tutorial satu kali untuk bibir, bukan per sisi kiri/kanan.

LOOK (Try On)
1. Natural Tint: tint tipis rata di seluruh bibir, tepi lembut, intensitas rendah.
2. Gradient (blurred lip): warna paling pekat di bagian dalam bibir, memudar ke garis bibir.
3. Full Bold: warna pekat rata sampai garis bibir, tepi tegas.
(Shade dari palet lip; intensitas pakai slider yang sama.)

RENDER
- Area bibir dari mesh ARKit (vertex sekitar mulut). Bagian dalam mulut, gigi, dan lidah tidak boleh diwarnai: pakai
  batas bibir bagian dalam dan matikan pigmen saat jawOpen tinggi.
- Kalau garis bibir dari ARKit kurang presisi di HP, uji MediaPipe face landmarker (landmark bibir) sebagai garis tepi,
  dan laporkan hasilnya sebelum mengganti.
- Gradient: pakai jarak ke tengah bibir dalam ruang UV.

FOTO
- Cek foto: mulut tertutup (jawOpen rendah), tidak tersenyum lebar (smile rendah). Kalau gagal, minta foto ulang.

PERLENGKAPAN
- mustHave: Lip tint atau lipstick (produk, tampilkan shade), Lip liner (opsional, "kalau ada").
- nearby: micellar water, cotton bud (untuk merapikan tepi), lip balm (opsional, sebelum mulai).

TUTORIAL
1. Oles lip balm tipis, tunggu sebentar.
2. Gambar garis tepi bibir dengan pelan, ikuti garis putus-putus (lewati kalau tidak pakai liner).
3. Isi bibir dari tengah ke luar.
4. (Gradient) Tepuk-tepuk tepinya pakai jari biar memudar.
5. Katupkan bibir pelan, lalu rapikan tepi pakai cotton bud.

FEEDBACK (metrik)
- Placement: cakupan area bibir target, warna keluar garis bibir (overline atas/bawah, sudut bibir), simetri kiri-kanan
  bibir (berdasarkan sisi wajah), dan bagian yang belum terisi.
- Shade: perbedaan hue dari shade pilihan, intensitas dibanding Try On, kerataan (patchy), dan untuk Gradient,
  apakah bagian dalam lebih pekat dari tepi.
- Rule: lip.none, lip.coverage.low, lip.outside.upper/lower/corner, lip.edge.harsh (untuk Natural/Gradient),
  lip.gradient.flat, lip.intensity.too_light/too_strong, lip.hue.warmer/cooler, lip.patchy, lip.symmetry.
- Hati-hati: warna bibir asli sudah merah/pink, jadi bandingkan dengan foto bibir polos. Bayangan di sudut bibir
  jangan terbaca sebagai lip.
```

## Spesifikasi look: Contour

```text
SPESIFIKASI: CONTOUR
Jenis: makeup area per sisi (kiri/kanan), warna lebih gelap dan dingin dari kulit, tepi sangat lembut. Penempatan
mengikuti bentuk wajah dari face scan (FaceShapeAssessment, punya Khalish).

LOOK (Try On)
1. Soft Sculpt: hanya di bawah tulang pipi, tipis.
2. Defined: bawah tulang pipi + garis rahang + pelipis.
3. Nose (opsional, tambahan): dua garis tipis di sisi hidung.
Aturan per bentuk wajah (contoh, kalibrasi dengan referensi di makeup-reference.database.json):
- Round: garis pipi lebih diagonal dan pelipis lebih banyak.
- Square: rahang dilembutkan di sudutnya.
- Long: dahi atas dan dagu, garis pipi lebih datar.
- Oval/Heart: Soft Sculpt standar; Heart tambah dahi samping.

RENDER
- Mask di ruang UV mesh ARKit: garis dari depan telinga ke arah sudut bibir, berhenti sejajar tengah mata, di cekungan
  bawah tulang pipi. Tepi blur lebar, opacity rendah.
- Warna: shade contour (cool/neutral brown), multiply ke kulit, bukan menutup.

FOTO
- Cek cahaya ketat: contour = kulit sedikit lebih gelap, jadi bayangan dari lampu bisa terbaca sebagai contour.
  Pakai screen light yang sama untuk kedua foto. Kalau cahaya berbeda jauh, minta foto ulang.

PERLENGKAPAN
- mustHave: Contour (stick/cream atau powder, tampilkan shade), Brush angled atau sponge.
- nearby: micellar water, cotton pad, setting powder (opsional).

TUTORIAL (per sisi)
1. Cari cekungan pipi: kempiskan pipi sebentar, rasakan tulangnya.
2. Gambar garis tipis dari depan telinga ke arah sudut bibir, berhenti di tengah mata.
3. Baurkan ke arah atas dan ke telinga sampai tidak ada garis.
4. (Defined) Sapukan tipis di garis rahang dan pelipis, baurkan.
5. (Nose) Garis tipis di sisi hidung, baurkan.

FEEDBACK (metrik)
- Placement: offset tinggi garis pipi (terlalu tinggi/rendah dari cekungan), terlalu maju ke arah mulut, panjang,
  sudut, dan simetri kiri-kanan.
- Shade: penggelapan dibanding Try On (terlalu gelap/tipis), terlalu hangat (jadi kayak bronzer), dan tepi tajam
  (belum dibaurkan).
- Rule: contour.none, contour.offset.too_high/too_low, contour.too_forward, contour.length.too_long/short,
  contour.angle, contour.darkness.too_dark/too_light, contour.hue.too_warm, contour.edge.harsh, contour.symmetry.*.
- Ambang deteksi lebih kecil dari blush (perubahan L* kecil). Wajib ada koreksi cahaya (FeedbackSkin.shift) dan
  batas area supaya bayangan rahang/leher tidak terbaca.
```

## Template spesifikasi (untuk look lain)

Salin template ini dan isi semua bagiannya, misalnya untuk highlighter atau eyeshadow. Bagian yang belum tahu tetap
diisi "belum tahu, tolong usulkan". Jangan dikosongkan.

```text
SPESIFIKASI: <NAMA TOOL>
Jenis: makeup area / makeup garis; per sisi atau tengah.

LOOK (Try On)
1. <nama look>: <di mana, seberapa pekat, bentuk tepi>
2. ...
Aturan per bentuk wajah / bentuk mata: <kalau ada>

RENDER
- Area/garis diambil dari: <mesh ARKit / landmark MediaPipe>
- Yang tidak boleh ikut terwarnai: <mata, gigi, alis, ...>
- Warna: <cara campur ke kulit: tint, multiply, kilau>

FOTO
- Cek khusus: <mata terbuka, mulut tertutup, cahaya sama, ...>

PERLENGKAPAN
- mustHave: <produk (tampilkan shade?), alat>
- nearby: <untuk memperbaiki salah>

TUTORIAL
1. <instruksi maksimal ±12 kata>
...

FEEDBACK (metrik)
- Placement: <metrik>
- Shade: <metrik>
- Rule: <tool>.none, ...
- Hati-hati: <apa yang bisa salah terbaca sebagai makeup>
```
