# Pengujian

## Unit test fondasi

Satu target `SunriseAppTests`, dimasukkan dalam shared scheme SunriseApp. Test mencakup onboarding/tab state, reset satu stack tanpa merusak stack lain, batas navigasi langkah termasuk empty tutorial, catalog failure/retry/cancellation, saved-list error, injected unsupported tracking, dan penolakan mock save. Tidak ada hardware call di unit test.

Jalankan dari Xcode dengan Product → Test (Cmd+U) pada iPhone Simulator. CLI dari root repo:

```sh
xcrun simctl list devices available
xcodebuild test -project SunriseApp.xcodeproj -scheme SunriseApp \
  -destination 'platform=iOS Simulator,id=REPLACE_WITH_AVAILABLE_UDID' \
  -derivedDataPath /tmp/SunriseDerived CODE_SIGNING_ALLOWED=NO
```

Build compile-only untuk iPhone tanpa signing:

```sh
xcodebuild build -project SunriseApp.xcodeproj -scheme SunriseApp \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/SunriseDerived CODE_SIGNING_ALLOWED=NO
```

Build test bundle tanpa menjalankan Simulator:

```sh
xcodebuild build-for-testing -project SunriseApp.xcodeproj -scheme SunriseApp \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/SunriseSimulatorDerived CODE_SIGNING_ALLOWED=NO
```

## Checklist manual scaffold

- Onboarding tampil saat launch; Explore membuka dua tab dan tidak meminta kamera/foto.
- Discover berlabel sample; keempat reference membuka detail yang tepat.
- Import hanya menjelaskan placeholder dan tidak membuka Photos.
- Calibration default menunjukkan dukungan belum dicek; Skip membuka tutorial tanpa klaim wajah terdeteksi.
- Previous/Next tutorial berhenti pada batas; Live Guide tidak menampilkan kamera palsu.
- Comparison tanpa foto dan Save disabled. Return to Discover menghapus stack Discover.
- My Looks jelas berisi sample metadata; detail tidak menampilkan foto seolah capture pengguna.
- Tab switching menjaga path masing-masing, Back bekerja, restart mengulang onboarding.
- Periksa text terbesar, VoiceOver, small iPhone, light/dark mode. Perbaiki layout yang memotong teks atau tombol.

## Checklist milestone AR berikutnya

Uji pada iPhone yang lolos runtime isSupported: izin allow/deny, Settings return, background/foreground, lock/unlock, interruption, tracking loss/recovery, kepala berputar/miring, ekspresi, jarak, lighting, variasi wajah. Verifikasi cheek overlay mengikuti mesh, bukan screen overlay. Test fallback pada device unsupported. Simulator hanya memvalidasi fallback/UI; bukan live AR.

## CI

`.github/workflows/ios-build.yml` memakai macos-15, Xcode default runner, memilih iPhone Simulator yang benar-benar tersedia, lalu build dan menjalankan unit test. Pemilihan device menggunakan JSON simctl; gagal jelas jika tidak ada runtime. Tidak ada signing/secrets dan tidak ada deployment. Hasil xcresult dan log diupload 7 hari.

Referensi konfigurasi action: [checkout](https://github.com/actions/checkout), [upload-artifact](https://github.com/actions/upload-artifact), [runner macOS](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md). Workflow belum membuktikan CI lulus sampai dijalankan di remote repo.

Hasil pemeriksaan workspace akan dicatat di Validation.md; bedakan compile-only, unit test execution, dan UI/device execution.
