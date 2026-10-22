# Testing MVP

> -Nimah: Acuan placement terbaru: [MakeupAccuracyPlan](MakeupAccuracyPlan.md) dan [EyelinerDeviceTesting](EyelinerDeviceTesting.md). Catatan di bawah dapat mencakup iterasi historis. Eyeliner kini strip attachment, bukan atlas; full look default OFF.

## Build / unit test

Buka SunriseApp.xcodeproj, scheme SunriseApp, pilih iPhone Simulator, Cmd+U. Tidak perlu Team untuk Simulator.

```sh
xcodebuild build -project SunriseApp.xcodeproj -scheme SunriseApp \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SunriseMVPDerived CODE_SIGNING_ALLOWED=NO

xcrun simctl list devices available
xcodebuild test -project SunriseApp.xcodeproj -scheme SunriseApp \
  -destination 'platform=iOS Simulator,id=YOUR_AVAILABLE_UDID' \
  -derivedDataPath /tmp/SunriseMVPSimulatorDerived CODE_SIGNING_ALLOWED=NO
```

Test fondasi: navigation stack, boundaries/empty tutorial, catalog retry/cancel, saved error, injected unsupported, mock save rejection. Test MVP tambahan: readiness dua detik/reset loss/gap, mask symmetry/out-of-area, save/reopen/delete capture pair, incomplete save rejection, traversal rejection, corrupt metadata. Storage tests memakai folder temporary terisolasi, tidak menyentuh data pengguna.

## Demo Simulator

1. Onboarding → Find my glow.
2. Discover → satu look → Start my tutorial.
3. Pastikan pesan unsupported menyebut Simulator dan tidak meminta izin kamera.
4. Continue with manual tutorial → lima langkah → Finish.
5. My Looks harus kosong pada instalasi baru; jangan isi dengan hasil palsu.
6. Import → system Photos picker; pilih foto dari library Simulator bila ada → preview → pilih style → Start. Cancel/remove harus tetap usable.
7. Relaunch: onboarding tidak muncul lagi. Source unit tests tidak menggantikan pemeriksaan UI ini.

## Acceptance iPhone fisik (wajib)

- Pilih Team dan bundle identifier unik; trust/Developer Mode, Run.
- Support check: compatible device masuk permission; unsupported tetap manual.
- Deny kamera, buka Settings, allow, kembali. Uji permission belum ditentukan dan granted.
- Hold still 2 detik, uji pergerakan/gap/loss agar readiness tidak sukses palsu.
- Capture Before tidak punya overlay. Pada blush, cek kedua pipi saat turn/tilt/smile/dekat/jauh, varied face proportions dan lighting. Rekam hasil dan tuning mask jika perlu.
- Toggle guide; Next mematikan blush pada contour sampai lips. Back ke blush boleh mengembalikan guide.
- Tracking lost menonaktifkan capture; recovery, interruption, retry, background/foreground, lock/unlock, tab switch, comparison sheet harus menjeda/melanjutkan kamera dengan benar.
- Capture After: periksa portrait orientation/mirroring dan overlay off. Compare bukan scoring; konsistensi lighting/framing tanggung jawab pengguna.
- Save, Done, My Looks, relaunch, buka dua capture, delete/cancel/delete-confirm/relaunch. Uji storage error tanpa mengklaim berhasil.
- Import iCloud foto, cancel, unavailable/large asset. Foto referensi tidak boleh dianalisis/terunggah.
- Periksa small phone, text terbesar, VoiceOver, light/dark. Uji memory koleksi dan foto besar.

## CI

Workflow macOS Simulator di .github/workflows tetap tersedia. Hasil lokal terbaru dicatat di Validation.md; jangan menyatakan CI remote lulus sebelum ada workflow run yang mendukung klaim tersebut.

## Checklist dotted Glam — -Nimah

- Catalog menampilkan Sculpted Glam dengan foto referensi pilihan pengguna. Detail menjelaskan breakdown manual dan keterbatasan hasil.
- Manual mode: sketsa titik berganti tiap langkah. Tidak ada kamera palsu atau capture palsu.
- iPhone: Dots/Soft area untuk blush; toggle visibility dan Back/Next harus menampilkan area yang tepat.
- Smile, blink, buka/tutup mulut, turn/tilt dan tracking loss. Pastikan titik menempel pada mesh; cek area mata/bibir dengan cermat sebelum menyebut placement valid.
- Capture saat titik tampil, lalu periksa hasil Before/After bebas marker dan orientasi/mirroring benar.
- Regresi unit: target per langkah tidak kosong, pemetaan indeks valid, tidak ada duplikasi, mesh kosong aman.

## Protokol validasi iPhone 17 — belum dijalankan

1. Jalankan versi terbaru dari source ini, bukan GlowGuide lama. Catat model/iOS/build dan kondisi cahaya.
2. Kalibrasi frontal dengan mata/bibir rileks; pastikan fit lengkap atau area partial dinyatakan hidden.
3. Gunakan Points + makeup lalu Makeup only dan Original. Periksa bahwa Original benar-benar baseline kamera.
4. Gerakkan jarak perlahan sekitar 20, 30, 40, dan 60 cm, kemudian maju-mundur lebih cepat. Angka ini titik pengujian, bukan janji range sensor. Catat frame tracking loss dan marker yang meleset.
5. Uji putar/tilt kiri-kanan, senyum, blink, mulut buka/tutup. Periksa lip bleed ke gigi, liner ke sclera, sisi jauh menembus wajah, dan lag antara kamera serta makeup.
6. Jika membuat video evaluasi lokal, anotasi eyelid/lip corners dan bandingkan error yang dinormalisasi terhadap lebar wajah. Tentukan kriteria penerimaan tim dari bukti ini; unit test tidak mengukur error camera pixels.
7. Profiling Instruments untuk CPU/GPU/frame time dan thermal. Request 60 FPS tidak berarti actual FPS konstan. Uji sekurangnya beberapa menit, termasuk refit dan background/resume.
8. Capture/save tetap unfiltered; verifikasi orientasi, mirroring dan tidak ada marker/virtual color tersimpan.

Regresi tambahan: topology fit pada synthetic holes, scale invariance, partial-fit hiding, invalid topology/UV handling, cached texture alpha, preview mode flags, dan readiness menunggu fit. Synthetic fixture bukan wajah asli dan bukan klaim akurasi hardware.

## Retest preview warna — -Nimah

1. Jalankan build terbaru dari proyek SunriseApp yang sama pada iPhone 17, buka Sculpted Glam dan selesaikan kalibrasi.
2. Aktifkan full look, pilih Makeup only dan intensitas 80–100%. Bandingkan dengan Original camera dalam cahaya yang sama: pipi, bibir dan kelopak seharusnya berubah warna.
3. Pilih Points + makeup: titik dan warna harus berada di area yang sama. Uji maju/mundur perlahan dan menoleh; catat area meleset, jitter atau warna tersembunyi.
4. Turunkan intensitas ke nol: warna harus hilang. Points only hanya menampilkan panduan. Foto tersimpan masih raw camera, tidak memuat efek virtual.
5. Bila perbedaan warna belum terlihat pada perangkat, hasil tetap dianggap belum lolos acceptance test walaupun tes simulator lulus.
