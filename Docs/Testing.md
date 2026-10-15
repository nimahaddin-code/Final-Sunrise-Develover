# Testing MVP

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
