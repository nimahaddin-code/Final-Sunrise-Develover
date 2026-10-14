# ADR 0001 — Fondasi iOS berdasarkan fitur

Status: accepted untuk scaffold. Tanggal: 14 Oktober 2026.

## Konteks

Tim membutuhkan batas folder dan kontrak agar pekerjaan UI dapat dibagi sebelum AR/capture selesai. Nama produk belum ditentukan. Milestone ini harus dapat dijelajahi tanpa kamera atau perangkat fisik.

## Keputusan

- Nama repository persis Final-Sunrise-Develover, target sementara SunriseApp.
- SwiftUI + MVVM ringan, iOS 17+, ObservableObject/@Published dan MainActor konsisten.
- Satu app target dan satu unit test target, tanpa dependency eksternal atau package terpisah.
- Features memegang implementasi masing-masing; Core memuat hanya model/kontrak bersama yang digunakan.
- Initializer DI; AppContainer hanya composition root, bukan service locator.
- NavigationStack typed routes, path per tab, onboarding session-only.
- Mock eksplisit untuk katalog/metadata; save throws notImplemented; hardware dan media belum diimplementasikan.
- Explicit PBXGroup agar folder Xcode sesuai disk dan tetap kompatibel Xcode 15+.

## Alasan dan konsekuensi

Batas ini mengurangi perubahan file bersama dan memungkinkan UI tanpa perangkat. File project masih dapat menjadi titik konflik sehingga integrasi konfigurasi dikoordinasikan. Mock berada di PreviewSupport tetapi sengaja masuk target app untuk scaffold; sebelum rilis, audit composition root agar tidak membawa data contoh sebagai data pengguna.

## Tinjau ulang jika

Tim membutuhkan package boundary karena dependensi lintas fitur membesar, deep link/persisted navigation, workflow capture/import memerlukan media ownership, atau spike AR menetapkan kebutuhan session interface. ADR baru harus menjelaskan masalah terukur sebelum menambah abstraksi.
