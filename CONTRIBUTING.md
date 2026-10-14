# Panduan kontribusi

Baca README, Docs/Architecture.md, dan Docs/IntegrationContracts.md sebelum mulai.

## Workflow

1. Tech lead memilih workstream dan acceptance criteria di Docs/TeamWorkstreams.md, lalu menunjuk PIC melalui issue. Nama anggota belum ditetapkan dalam scaffold.
2. Mulai dari `main`, gunakan `feature/<short-name>`, `fix/<short-name>`, atau `chore/<short-name>`.
3. Kerjakan perubahan kecil dalam folder fitur. Gunakan mock untuk pekerjaan yang belum menunggu implementasi layanan asli.
4. Perubahan model/kontrak bersama harus dijelaskan di issue/PR dan dikoordinasikan sebelum integrasi. Jangan mengubah kontrak diam-diam.
5. Build, jalankan test relevan, dan jelaskan keterbatasan. Untuk UI tambahkan screenshot dari aplikasi yang benar-benar dijalankan; jangan mengklaim mock sebagai hasil perangkat.
6. Buat PR ke main dengan template yang disediakan. Tech lead mengoordinasikan file bersama dan review; tidak ada pengaturan branch protection otomatis.

Commit singkat dengan maksud yang jelas: `feat: add reference import preview`, `fix: preserve tutorial position`, `docs: define capture ownership`. Pisahkan refactor besar dari penambahan fitur.

## Menambah fitur

- Simpan View dan ViewModel di `Features/<Feature>`. Subfolder tambahan dibuat saat berisi file nyata.
- Stateless View tidak perlu ViewModel. ViewModel menggunakan `@MainActor ObservableObject` dan `@Published`, konsisten dengan fondasi.
- Inject dependency melalui initializer; AppContainer hanya digunakan di composition root. Hindari EnvironmentObject untuk service dan akses container dari dalam fitur.
- Tambahkan file ke target dan group Xcode sesuai folder disk. Project memakai PBXGroup eksplisit agar dapat dibuka Xcode 15+.
- Model lokal tetap di fitur. Model Core harus benar-benar digunakan lintas fitur.
- Untuk layanan async gunakan kontrak Sendable. Jangan blok main thread untuk file I/O atau pemrosesan gambar.
- Pusatkan style reusable di DesignSystem. Tambahkan string ke Localizable.xcstrings; periksa komentar translator untuk string ambigu.
- Jangan commit user state, data pengguna, private signing, atau build products.

## Koordinasi file bersama

`AppRootView`, `AppRoute`, `AppContainer`, `project.pbxproj`, scheme, design tokens, dan Core contracts dikoordinasikan tech lead. Satu PR integrasi pada satu waktu untuk perubahan konfigurasi proyek. Resolve konflik project file lewat Xcode, lalu build ulang dan pastikan tidak ada file yatim/duplikat.

## Scope honesty

Pertahankan label scaffold/mock sampai fitur asli teruji. Save belum tersedia; mock wajib melempar `notImplemented`. Tidak ada kamera, Photos, ARKit, foto hasil, atau analisis otomatis pada fondasi ini.
