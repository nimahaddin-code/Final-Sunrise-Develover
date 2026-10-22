# GlowGuide Eyebrow Guide — -Nimah

> -Nimah, 20 October 2026: live eyebrow mapping sekarang wajib Eye & Brow Scan dan rumus nose–pupil–outer eye; baca [EyeBrowMapping](EyeBrowMapping.md). Catatan bounds/fixed arch sebelumnya di bawah adalah riwayat implementasi.

> -Nimah, 19 October 2026: scope terbaru mencakup closed eyebrow outline, lima forehead style dan tutorial manual. Baca [BrowForeheadGuide](BrowForeheadGuide.md) untuk status terbaru, batas hairline dan testing; catatan sebelumnya di bawah adalah riwayat.

Modul baru di proyek existing **Final-Sunrise-Develover**, target/bundle **SunriseApp / com.sunrise.foundation**. Tidak membuat proyek GlowGuide duplikat. Nama GlowGuide dipakai pada header modul; nama aplikasi existing dipertahankan. Lampiran instruksi tidak memuat mockup gambar baru, sehingga UI mengikuti design system pink/rounded existing.

## Implementasi

- Entri **Discover → Eyebrow Guide** terpisah dari tutorial warna lama.
- SwiftUI camera-first view, tracking status, empat style, dots/dashed/both, Show guide, Refit, Back dan Debug mesh/points pada build Debug.
- ARKit front-camera face tracking dan native face mesh memakai ARSession bersama.
- Apple Vision `VNDetectFaceLandmarksRequest` untuk region `leftEyebrow` / `rightEyebrow`. Tidak ada indeks vertex alis hardcoded atau deteksi tiruan.
- Vision hanya untuk kalibrasi region; setelah berhasil, guide mengevaluasi attachment terhadap mesh ARKit terbaru setiap frame. Tidak perlu mengulang inference pada tiap frame.
- Straight Brow adalah baseline. Soft Arch, High Arch dan Feathered membentuk geometry berbeda; Feathered menambah arah sapuan pendek. Ini panduan aplikasi makeup, bukan filter pewarnaan atau penilaian hasil.
- Tracking lost / pause / refit / pergantian anchor membuang hasil kalibrasi, menyembunyikan guide, lalu meminta pemetaan ulang. Hasil worker lama tidak diterapkan setelah epoch/anchor berubah.

## Alur data dan koordinat

1. Frame dan ARFaceAnchor diambil dari callback ARSession yang sama. Salin vertices, triangles, eye transforms, camera transform/intrinsics dan timestamp. Worker hanya menahan satu capturedImage per pipeline; tidak ada penyimpanan foto/mesh.
2. Kamera UI dikunci portrait lewat Info.plist. Input Vision memakai EXIF `leftMirrored` untuk sensor depan portrait. Ini hipotesis integrasi kamera yang masih harus dibuktikan pada perangkat; API dan semua inverse orientation diuji secara matematis.
3. Landmark Vision berada dalam boundingBox wajah dengan origin lower-left. Konversi ke normalized oriented-image coordinates, ubah origin menjadi top-left, lalu terapkan inverse EXIF orientation kembali ke sensor raw.
4. Bentuk ray kamera dari intrinsics sensor: `[(u-cx)/fx, -(v-cy)/fy, -1]`. Transform ray ke koordinat lokal face memakai inverse cameraFromFace dari frame yang sama.
5. Ray–triangle intersection memilih permukaan terdekat. Simpan triangle indices + barycentric weights. Tidak memakai screen offset, SceneKit hit-test terhadap bidang lingkungan, atau pembalikan UV.
6. Validasi dua region terhadap eye transforms ARKit: berada di atas mata, ukuran masuk akal relatif wajah, side berbeda, minimal 80% landmark masuk permukaan. Kandidat wajah lain tidak diterima hanya karena confidence lebih tinggi.
7. Tentukan inner/tail dari bounds alis personal. Curve style dibentuk relatif lebar dan tinggi region tersebut. Sample curve di-bind lagi ke permukaan kulit; bagian di luar mesh tidak diekstrapolasi.
8. Renderer membaca vertex anchor terbaru untuk dot dan setiap segmen capsule. Rounded caps memberi garis putus-putus. Pose root tetap dikelola ARKit; jarak tidak digunakan untuk scaling manual.

Tidak ada smoothing pose tambahan agar guide tidak tertinggal kepala. Binding kalibrasi dibekukan sampai loss/refit untuk menghindari jitter akibat inference berulang. Ini bukan bukti jitter mesh sudah memenuhi toleransi tertentu.

## Confidence dan batas anatomis

`faceObservationConfidence` adalah confidence **observasi wajah Vision**, bukan skor akurasi eyebrow landmark. Threshold 0.5, gate ukuran/posisi dan coverage 80% merupakan validasi prototipe; tidak terkalibrasi sebagai probabilitas keberhasilan.

Vision membaca bentuk alis pada gambar; mesh ARKit menentukan permukaan skin tempat attachment. Kerapatan mesh, alis tertutup hijab/rambut/kacamata, makeup sangat tebal, cahaya buruk, dan pose ekstrem dapat menggagalkan mapping. Tidak ada hand/hair segmentation, evaluasi kecocokan style, feedback benar/salah, ekstraksi style dari foto atau AI makeup analysis (P2 belum dikerjakan).

Guide dimaksudkan sebagai placement makeup yang dapat berbeda dari rambut alis asli. Style memakai pola arch yang sama secara proporsional pada kedua sisi, tetapi tetap mempertahankan anchor/bounds personal; tidak memaksakan wajah menjadi simetris identik.

## Struktur dan kontrak integrasi

```text
Core/AR/
  ARFaceTrackingManager.swift       satu configured session + lease ownership, tracking state
  FaceLandmarkProvider.swift        snapshot frame, protocol provider, implementasi Vision
  FaceLandmarkProjection.swift      normalized image ↔ raw ray ↔ face triangle
Features/Eyebrow/
  EyebrowRegionMapper.swift         region/side/confidence + anatomy gates
  EyebrowStyle.swift                style, dots/dashed/both, configuration
  EyebrowGuideGenerator.swift       intended curves + attachment/strokes
  EyebrowTrackingPipeline.swift     bounded worker, epoch/anchor mailbox, retries
  EyebrowSceneRenderer.swift        pooled SceneKit spheres/capsules
  EyebrowViewModel.swift            UI configuration + support/tracking state
  EyebrowOverlayView.swift          screen/fallback/controls
Features/LiveGuide/
  LiveGuideView.swift               existing shared UIView bridge/coordinator
  SurfaceAttachment.swift          shared triangle attachment primitive
SunriseAppTests/Features/
  EyebrowTests.swift                projection, mapping, style, loss, worker failure, actual Vision
```

MVVM dipakai pada UI. Detektor, mapper dan generator tidak bergantung SwiftUI. SceneKit dipertahankan karena aplikasi existing sudah memakai ARSCNView dan native face geometry; tidak mencampur renderer RealityKit kedua. Migrasi renderer merupakan pekerjaan terpisah, bukan syarat menjalankan modul ini.

### Satu sesi AR

Semua FaceCameraState memakai `ARFaceTrackingManager.shared`. LiveGuideView menghubungkan preview ke sesi itu. Coordinator aktif memegang lease UUID; owner baru merevoke owner lama. Release/dismantle dari layar lama tidak boleh pause atau menghapus delegate milik owner baru. Sesi di-reset saat berpindah fitur agar data mapping tidak melintasi modul/pengguna.

Modul Lips/Nose/Cheeks berikutnya harus menggunakan manager, snapshot/projection, attachment dan lifecycle yang sama. Tambahkan renderer/region/config sendiri; jangan membuat AVCaptureSession atau menjalankan ARSession baru untuk tiap region. Saat ini fitur berada pada layar terpisah, bukan komposisi semua region secara bersamaan.

### Pembagian kerja

- **Nimah / tech lead:** Eyes & Eyebrows; review koordinat, mapping, style dan acceptance perangkat.
- **Pemilik Lips & Nose:** gunakan shared session + geometry attachment; nama PIC belum ditentukan di instruksi terbaru.
- **Pemilik Cheeks/Forehead/Jaw/Chin:** region/guide tersendiri; gunakan kontrak frame/renderer yang sama.
- Khalish/Hanum tetap anggota tim; dokumen ini tidak mengarang penugasan region atau atribusi kode untuk mereka. Kode iterasi ini ditandai -Nimah.

## References

- [Apple VNFaceLandmarks2D](https://developer.apple.com/documentation/vision/vnfacelandmarks2d): region eyebrow dan koordinat boundingBox lower-left.
- [Apple ARFaceAnchor.geometry](https://developer.apple.com/documentation/arkit/arfaceanchor/geometry): mesh disesuaikan bentuk/ekspresi wajah.
- [Apple ARSCNView](https://developer.apple.com/documentation/arkit/arscnview): camera/world alignment dan rendering AR existing.

Status build, hasil tes, dan acceptance yang belum terpenuhi dicatat terpisah di EyebrowTesting.md. Jangan menyamakan implementasi source dengan kelulusan tracking pada wajah nyata.
