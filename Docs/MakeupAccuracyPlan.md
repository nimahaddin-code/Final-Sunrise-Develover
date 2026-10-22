# Placement eyeliner: implementasi dan acceptance gate — -Nimah

> -Nimah, update eyeshadow: seluruh makeup live kini memakai **vertex colors** untuk area non-eyeliner dan **strip attachments** untuk eyeliner. Atlas lama tidak digunakan pada jalur live. Bentuk mask area non-eyeliner masih estimasi dan belum lolos acceptance wajah nyata.

Dokumen ini menjadi acuan terbaru di atas catatan historis try-on. Proyek tetap **Final-Sunrise-Develover / SunriseApp**. Tidak ada analisis otomatis foto Sculpted Glam.

## Diagnosis berbasis bukti

| Temuan | Bukti | Implikasi |
| --- | --- | --- |
| Full look aktif tanpa pilihan eksplisit | Default `previewFullLook` dan coordinator sebelumnya `true` | Langkah eyeliner masih menampilkan contour, blush, shadow dan lips. Ini sudah diperbaiki menjadi satu layer default. |
| Jalur titik dan warna berbeda | Titik memakai vertex; warna melewati atlas UV/gambar | Keberhasilan titik tidak membuktikan lokasi pigmen. Eyeliner sekarang memakai attachment triangle yang sama untuk keduanya. |
| Uji UV sebelumnya belum memvalidasi renderer native | Regresi lama menggunakan SCNPlane | Pembalikan atlas global sebelumnya tidak cukup menjadi bukti perbaikan iPhone. UV untuk atlas eksperimen kini dibaca dari geometry renderer aktual, dengan offset/stride. |
| Screenshot menunjukkan hidung/pipi berwarna | Laporan pengguna | Tidak cukup untuk membedakan kontribusi full look dan kesalahan UV per layer; tidak menyatakan seluruh warna itu pasti eyeliner. |

Tidak ada bukti bahwa alpha merupakan akar masalah. Alpha premultiplied dipertahankan. Tidak ada klaim semua mismatch selesai hanya karena perubahan UV.

## Jalur eyeliner baru

1. Deteksi hole mata pada topology wajah dan validasi dengan eye transforms dari anchor yang sama.
2. Ambil envelope upper rim, urutkan inner-to-outer berdasarkan sisi face-local.
3. Bentuk strip tipis di kulit di atas rim; wing berawal di ujung luar upper rim. Ketebalan bertambah ke luar dan wing menipis ke ujung.
4. Bind setiap titik strip ke triangle kulit dengan barycentric weights. Target yang jatuh di hole atau di luar mesh tidak diekstrapolasi; segmen itu tidak digambar.
5. Setiap update anchor mengevaluasi attachment terhadap vertex terbaru. Pose root tetap milik ARKit; tidak ada scaling jarak manual, transform kamera tambahan, atau screen offset.
6. Renderer strip tidak memakai atlas UV. Titik panduan diambil dari attachment strip yang sama. Feathering memakai alpha vertex; face depth mesh tetap menghalangi sisi yang tertutup permukaan wajah.
7. Eye blink menyembunyikan efek dan titik pada mata terkait. Regenerasi style memakai rest surface kalibrasi, lalu deformasi saat ini.

Ini **aproksimasi upper rim mesh**, bukan segmentasi garis bulu mata, dan belum dibuktikan presisi untuk semua eyelid. Mesh netral ARKit yang lolos tes hardware bukan hasil pengukuran wajah pengguna. Jangan menyebutnya photorealistic atau akurat 100%.

## Komponen dan tanggung jawab

| Komponen | Tanggung jawab |
| --- | --- |
| `FaceCameraState` | Permission, state UI, scope, capture raw, status |
| `LiveGuideView.Coordinator` | Session/anchor lifecycle, handoff worker, node AR dan expression gates |
| `FaceSurfaceProfile` | Topology/hole mata dan mask eksperimen area lain; mask eyeliner atlas kosong |
| `SurfaceAttachment` | Binding serta evaluasi barycentric pada triangle |
| `EyelinerRegion` | Upper-rim path, batas area, wing/thickness, attachment/guide/validity |
| `EyelinerRenderer` | Strip geometry, alpha vertex, material/depth |
| `LiveGuideDiagnostics` | UV renderer, atlas asimetris, label face-local dan debug mode |
| `SurfaceRenderProfile` / `SurfaceMakeupRenderer` | Rest geometry + mask, warna per vertex, mesh tanpa UV; active/previous/full memakai selection yang sama |
| `MakeupTextureBaker` | Utilitas atlas historis + palet bersama; bukan renderer live |
| `MakeupLayerSelection` | Single step, previous steps atau explicit full look |

## UX nyata

- Tutorial default hanya layer aktif. Previous/next mereset full look dan previous layers.
- `Show previous steps` dan `Full look preview · experimental` adalah pilihan eksplisit yang saling eksklusif.
- Empat mode original/points/makeup/both tidak mengubah attachment.
- Eyeliner: wing length, wing angle, thickness, reset, serta intensity.
- Status menunjukkan estimasi/partial fit dan kebutuhan validasi, bukan klaim semua area sudah tepat.
- Debug hanya di build Debug: wireframe, attachment/region IDs, atlas TOP/BOTTOM dan U/V, anchor ID, step dan scope. Face ±X berarti koordinat lokal wajah; pastikan mirroring secara visual di iPhone. Debug tidak merekam kamera atau menyimpan mesh pengguna.
- Capture before/after tetap buffer kamera asli tanpa efek virtual.

## Fitur yang belum diterapkan / gate berikutnya

Tahap 1–3 berupa audit, debug dan eyeliner telah dikerjakan untuk diuji. Tahap 4 **pengukuran dan penilaian pada wajah nyata masih menunggu**. Karena urutan yang diminta, perluasan arsitektur attachment ke shadow/lips/blush/contour serta fine adjustment area tersebut belum dilakukan. Preview area lain tetap eksperimen lama yang diberi label, bukan hasil validasi baru. Full look adalah komposisi eksperimen, bukan look final terverifikasi.

Belum ada detektor landmark kedua, AI transfer, penilaian makeup otomatis, hand/hair segmentation, koreksi eyelid khusus hooded eyes, pengukuran live FPS/jitter/latency, atau ekspor foto dengan efek. Status bukan placeholder yang berpura-pura berjalan; fitur yang belum ada tidak diklaim.

## Usulan toleransi untuk disepakati tech lead

Target berikut **usulan**, belum merupakan batas yang telah disepakati atau hasil pengukuran:

- Eyeliner statis: P95 jarak garis terhadap anotasi upper lash line ≤3% lebar mata pada frame berlabel.
- Blush (fase berikut): centroid mask berjarak ≤10% lebar mata dari area placement yang ditinjau makeup artist; overlap dan batas juga harus dinilai, bukan centroid saja.
- Jitter statis: P95 pergeseran relatif setelah kompensasi pose ≤1% lebar mata untuk eyeliner.
- Latency tambahan aplikasi: target ≤100 ms; metode ukur dan titik waktu harus ditentukan sebelum melaporkan angka.
- Tidak boleh ada pigmen eyeliner di hidung/pipi pada seluruh frame acceptance yang dinilai.

Ambang harus dievaluasi pada resolusi, ukuran wajah dalam frame, pose dan kondisi cahaya yang ditulis dalam laporan. Ukur beberapa wajah/bentuk eyelid dengan persetujuan. Sampel sintetis atau lolos build tidak memenuhi gate ini.

## Referensi implementasi

- [Apple: ARFaceAnchor.geometry](https://developer.apple.com/documentation/arkit/arfaceanchor/geometry) menjelaskan mesh yang disesuaikan ke bentuk dan ekspresi wajah.
- [Apple: SCNGeometrySource](https://developer.apple.com/documentation/scenekit/scngeometrysource) menjelaskan sumber vertex, normal, UV dan atribut geometry.
- [Apple: ARFaceGeometry.init(blendShapes:)](https://developer.apple.com/documentation/arkit/arfacegeometry/init(blendshapes:)) dipakai hanya untuk tes mesh netral hardware; tidak mengambil wajah pengguna.
