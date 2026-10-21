# ADR 0002 — Eyeliner dari landmark MediaPipe sebagai overlay 2D

Status: accepted. Tanggal: 21 Oktober 2026. Menggantikan sebagian ADR 0001 (tanpa dependency eksternal) dan aturan "overlay AR mengikuti face mesh".

## Konteks

Eyeliner awalnya digambar ke tekstur face mesh ARKit, dengan titik alis/mata dari Vision dipetakan ke UV mesh (`FaceFeatureLocator`). Di perangkat, hasilnya tidak cukup presisi untuk garis yang tipis:

- Liner jatuh di lipatan kelopak (crease), bukan di garis bulu mata. Titik Vision di dalam lubang mata dipetakan 30-45 px terlalu tinggi; setelah `FilledFaceMesh` dan `localFit` masih 10-15 px terlalu tinggi dengan lengkung yang salah.
- Garis bergoyang karena mata hanya disampel tiap beberapa frame lalu dirata-ratakan.
- Template mesh ARKit hanya menyesuaikan sebagian bentuk mata, sehingga kelopak yang diregangkan atau dikedipkan tidak diikuti.

Spike `EyelinerSpike` (MediaPipe Face Landmarker + overlay 2D + `LinerPathBuilder` + One Euro filter) menempatkan liner tepat di garis bulu mata dan stabil.

## Keputusan

- Eyeliner memakai pendekatan spike: landmark MediaPipe (478 titik, indeks mata yang sudah diverifikasi), `LinerPathBuilder` di bidang gambar, smoothing One Euro dengan gerakan kepala dihilangkan lewat titik jangkar wajah, dan baseline mata terbuka per pengguna (liner memudar saat mata menutup).
- Frame kamera berasal dari ARKit (`ARFrame.capturedImage`, dikonversi ke BGRA); tidak ada sesi kamera kedua. Frame dijatuhkan selama satu frame masih diproses; timestamp naik ketat dari `frame.timestamp`.
- Overlay digambar di SwiftUI `Canvas` di atas `MakeupARView`, dipetakan ke ruang view oleh `ImageToViewMapping`: `ARFrame.displayTransform` (rotasi + aspect-fill), dengan cermin selfie. Pemetaan dicek terhadap proyeksi titik wajah sendiri (ARKit memproyeksikan ke gambar dan ke layar), dicoba dengan cermin, dan sebagai upaya terakhir dihitung (least squares). Foto dari tombol kamera ikut menggambar overlay.
- Bentuk liner = `LinerSpec` (satuan spike, pecahan lebar mata) yang dikonversi dari `LinerStyle`. Gaya dipilih dari bentuk mata hasil face scan (`EyelinerPlanner`, tabel dari `Docs/Research/makeup_placement_rules.json`; riset menang atas angka spike), bukan dari bentuk wajah. `lashOffset` adalah konstanta bernama (`LinerBuildOptions.defaultLashOffset` 0.012; spike 0.006 terasa terlalu dekat ke mata) dan sekarang menggeser seluruh strip, bukan hanya tepi bawah, sehingga ketebalan tidak berkurang.
- Alis dan blush tidak berubah: tetap di tekstur face mesh. Jalur eyeliner lama di mesh dipertahankan di balik flag DEBUG (`-legacyMeshEyeliner YES`, default mati) untuk perbandingan.
- Dependency: xcframework MediaPipeTasksVision, MediaPipeTasksCommon, dan MediaPipeTaskGraphs 1.1.1 (binary dan checksum sama dengan manifest SPM Google). Di-vendor di `Vendor/MediaPipe` tetapi **tidak di-commit** (±370 MB, melebihi batas file GitHub); `Scripts/fetch-mediapipe.sh` mengunduh dan memverifikasi checksum, dan CI menjalankannya. Model `face_landmarker.task` (float16, 3,6 MB) di-commit di Resources.

## Konsekuensi

- Dependency eksternal pertama. Build butuh satu langkah `Scripts/fetch-mediapipe.sh` setelah clone; tanpa CocoaPods atau SPM, sehingga `SunriseApp.xcodeproj` tetap dibuka langsung.
- Ukuran: binary ±2,6 MB menjadi ±46 MB, ditambah model 3,6 MB; app ±2,5 MB menjadi ±47,5 MB tidak terkompres (±16 MB zip, Release perangkat tanpa signing). Link memakai `-all_load` karena registrasi calculator C++ MediaPipe akan dibuang linker jika tidak.
- Slice simulator hanya arm64: `EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64`; Mac Intel tidak didukung untuk simulator.
- Pengecualian aturan "overlay mengikuti face mesh": liner adalah overlay 2D di koordinat layar yang dihitung ulang tiap frame dari landmark (bukan koordinat layar tetap). Ada latensi deteksi (±1-2 frame) antara video AR dan liner.
- Deteksi hanya berjalan saat eyeliner dipilih. Tidak ada foto atau landmark yang disimpan atau dikirim.
- Hanya pengukuran bentuk mata (face scan) yang tetap memakai Vision.

## Tinjau ulang jika

Ukuran app menjadi masalah (opsi: model/graph yang lebih kecil atau on-demand), latensi overlay terlihat di perangkat (opsi: prediksi gerak dari transform ARKit), atau ARKit/Vision cukup presisi di garis bulu mata sehingga dependency dapat dilepas.
