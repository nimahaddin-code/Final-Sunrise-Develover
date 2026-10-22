# Arsitektur fondasi

## Pilihan utama

SwiftUI, iOS 17+, MVVM ringan, satu app target dan satu unit test target. Satu-satunya dependency eksternal adalah MediaPipe Tasks Vision (Swift Package) untuk scan mata ([ADR 0002](Decisions/0002-mediapipe-eye-scan.md)); `import MediaPipeTasksVision` hanya boleh ada di satu file, `Features/EyeShape/MediaPipeEyeDetector.swift`. Tidak ada package internal. Observasi konsisten menggunakan `ObservableObject` + `@Published`; semua ViewModel dan navigator adalah `@MainActor`.

Organisasi berdasarkan fitur. Model yang dibagi katalog/detail/tutorial/saved berada di Core. Rendering dan media belum memiliki model karena belum ada kebutuhan implementasi yang terbukti. Tidak ada UIImage atau ARFaceAnchor di domain bersama.

## Aliran dependency

```text
SunriseApp
  -> AppContainer.scaffold() (composition root)
  -> AppRootView
       -> AppNavigator (onboarding + tab + stack)
       -> Feature View(initializer dependency)
            -> Feature ViewModel(initializer service)
                 -> Sendable service contract
                      -> mock saat ini / implementasi nyata di milestone berikut
```

AppContainer tidak diakses dari ViewModel, singleton, atau Environment. Root memilih service dan meneruskannya ke layar yang memerlukan. Layar stateless memakai input immutable dan callback atau typed NavigationLink. Navigator hanya mengelola navigasi, bukan state fitur.

## State

- AppNavigator: onboarding session-only, tab terpilih, path Discover dan My Looks yang terpisah.
- Katalog/Saved: idle, loading, loaded (termasuk empty), failed. Cancellation kembali ke idle; retry eksplisit.
- Tutorial: langkah aktif dan batas previous/next, tidak ada klaim completion atau persistensi.
- Kalibrasi: availability hasil injection; default mock `.notChecked`. Tidak ada runtime hardware check.

Semua service bersifat async, Sendable. File I/O dan pemrosesan gambar di implementasi nyata harus berjalan di luar main actor; ViewModel menerima hasil dan memperbarui state di main actor. Mock saat ini adalah value types immutable. Stub test yang perlu mutasi memakai actor.

## Menambah implementasi nyata

1. Setujui kontrak dan error semantics melalui PR kecil.
2. Buat implementasi dalam fitur pemilik; jangan menaruh framework hardware di domain.
3. Ganti dependency di composition root pada PR integrasi, pertahankan mock untuk preview/test.
4. Implementasikan state loading/empty/error/permission dan cancellation yang relevan.
5. Baru hapus label placeholder pada fitur yang terverifikasi.

AppRoute memakai ID stabil untuk alur tutorial. Detail reference dan sample saved detail menerima snapshot metadata melalui route untuk menghindari service lookup tersembunyi. Deep link dan pemulihan navigasi lintas peluncuran belum termasuk; tinjau ulang route payload jika fitur tersebut ditambahkan.

## Keterbatasan fondasi

Tidak ada runtime camera/AR/Photos, persistence, analytics, networking, atau app icon final. No camera capability dibuat. Jangan tambahkan entitlement ARKit wajib yang akan menghalangi instalasi perangkat dengan fallback manual.
