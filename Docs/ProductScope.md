# Scope produk dan milestone

Repository: **Final-Sunrise-Develover**. Produk sementara: **SunriseApp**.

## Fondasi saat ini

Dua tab, onboarding session-only, katalog empat sample reference, layar detail/import/kalibrasi/live guide/comparison/saved detail, navigasi langkah tutorial, DI, mock services, design tokens, unit test, dan workflow CI.

UI menunjukkan label scaffold. Onboarding tampil lagi saat app diluncurkan ulang. My Looks berisi satu metadata contoh yang diberi label, tanpa foto. Tombol Save dinonaktifkan dan kontrak mock menolak save.

## Milestone selanjutnya

| Area | Target berikutnya | Belum termasuk |
| --- | --- | --- |
| Katalog | Konten nyata dan detail look | Rekomendasi otomatis |
| Import | System PhotosPicker, preview, hapus, error/cancel | Analisis makeup atau transfer reference otomatis |
| Kalibrasi | Status dukungan perangkat, permission, tracking stability | Bentuk wajah, analisis kulit, identifikasi pengguna |
| AR | Blush mengikuti face mesh/anchor | AR contour/eyeshadow/eyeliner/lips, photorealistic filter |
| Tutorial | Instruksi manual per look, navigasi, integrasi sesi | Penilaian otomatis hasil makeup |
| Comparison | Dua capture pengguna yang jelas asalnya | Scoring, penyelarasan otomatis, capture palsu |
| Saved Looks | Penyimpanan lokal dan penghapusan metadata+foto | Cloud, akun pengguna, social sharing |

## Aturan kejujuran produk

Jangan menamai tombol import sebagai Analyze. Jangan mengubah availability menjadi klaim tracking aktif. Jangan menamai metadata contoh sebagai hasil pengguna. Jangan menghapus label placeholder sebelum fitur asli dan acceptance criteria-nya selesai.

Belum ada permission strings kamera/foto karena tidak ada akses hardware/library. Tambahkan penggunaan kamera beserta deskripsi permission pada PR implementasi kamera. System PhotosPicker cukup memberi akses pilihan pengguna; broad library access memerlukan keputusan implementasi dan permission yang sesuai.
