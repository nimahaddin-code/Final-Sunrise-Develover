# Validasi MVP — 15 Oktober 2026

Implementasi diberi komentar `-Nimah`. Produk sementara: SunriseApp. Branch lokal: feature/nimah-mvp.

| Pemeriksaan | Hasil | Batas |
| --- | --- | --- |
| Xcode | 26.6 (17F113), SDK iOS 26.5 | Toolchain tersedia |
| Generic iPhone unsigned Debug | BUILD SUCCEEDED | Compile/link, tanpa instalasi perangkat |
| iPhone 17 Simulator iOS 26.5 | 17 unit tests passed, 0 failures, TEST SUCCEEDED | Tidak membuktikan AR hardware |
| Onboarding / katalog / detail | Dibuka dan diinspeksi lewat UI | Pemeriksaan default text/light mode |
| Unsupported fallback | Pesan eksplisit Simulator; tidak meminta kamera | iPhone unsupported masih perlu uji |
| Manual tutorial | Blush → contour → eyeshadow → eyeliner → lips → finish kembali ke Discover | Kamera mati, tanpa capture/save palsu |
| Photos import | System picker, gambar stock bunga Simulator, preview, ganti style ke Latte, masuk sesi Latte, remove image | Belum uji iCloud/large/error asset |
| Storage | Unit save/reopen/delete sepasang Data, incomplete rejection, invalid ID rejection, corrupt metadata error | End-to-end capture lalu UI save belum uji physical |
| Calibration/mask logic | Continuous readiness, reset loss/gap/motion; mask center exclusion/back exclusion/symmetry | Placement/render deformasi perlu iPhone |
| Physical AR / capture | Belum diuji | Tidak ada klaim keberhasilan live tracking, alignment, mirroring, capture orientation |
| Remote GitHub / CI | MVP belum diunggah | Branch main masih scaffold; hasil lokal ini bukan hasil CI remote |

17 test terdiri dari 3 navigation, 2 tutorial, 5 service/state, 3 tracking/mask, 4 local storage. Log dan xcresult disimpan di /tmp saat pengujian, tidak dimasukkan ke repository atau paket source.

Screenshot MVP aktual: [detail look](Validation/MVP-Look.jpg). `Validation/Onboarding.png` adalah artefak historis scaffold 14 Oktober, bukan tampilan MVP terbaru.

Belum diverifikasi: izin allow/deny dan Settings pada iPhone, live mesh placement, tracking loss pada hardware, hand/hair occlusion, capture orientation/mirroring, full save/load/delete dari kamera melalui UI, My Looks empty UI, onboard persistence lewat relaunch UI, small phone, seluruh Dynamic Type, VoiceOver, dark mode, memory pada koleksi besar. Checklist lanjut di Testing.md.

Build memakai akses layanan sistem di luar sandbox untuk compiler asset/Simulator. Warnings yang muncul adalah metadata AppIntents tanpa dependency dan library XCTest signed bawaan; tidak ada error Swift pada build yang berhasil.
