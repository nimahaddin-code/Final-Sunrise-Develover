# Eye & Brow Scan — -Nimah, 20 October 2026

Menggantikan live guide yang hanya memakai bounds alis dan posisi arch tetap. Tetap dalam proyek SunriseApp existing dan satu shared ARSession.

## Alur pengguna

Discover → Brow & Forehead Guides → posisikan wajah → Eye & brow scan. Kedua mata harus terbuka, alis dan hidung terlihat, pandangan lurus ke kamera. Tiga pembacaan stabil diperlukan sebelum Choose region aktif. Lalu pilih Eyebrows/style, periksa garis pemetaan, lihat Before/After atau mulai tutorial. Refit membuang kalibrasi dan mengulang scan.

"Scan" adalah deteksi landmark visual Vision dari kamera ARKit. Bukan pemindai iris untuk identitas, pemeriksaan kesehatan mata, atau alat yang menjamin akurasi milimeter.

## Patokan dan rumus

Untuk setiap sisi secara terpisah:

- N: perkiraan sisi hidung dari titik ekstrem contour nose Vision yang diproyeksikan ke mesh. Ini estimasi alar edge, bukan landmark nostril khusus yang dijamin Apple.
- P: pupil Vision. Karena pupil terletak pada lubang mata mesh, ray sensor diinterseksikan dengan bidang kedalaman median vertex mesh kelopak terdekat pada citra. Ini pendekatan kedalaman, bukan pengukuran pupil 3D.
- O: sudut luar mata, dipilih dari contour eye pada sisi yang sama.
- A (awal): garis vertikal X = N.x, pada level awal brow hasil deteksi.
- C (puncak): perpotongan ray N → P dengan level arch.
- B (ekor): perpotongan ray N → O dengan level tail brow hasil deteksi.

Rumus perpotongan pada bidang lokal wajah:

`t = (Y - N.y) / (E.y - N.y)`

`X = N.x + t * (E.x - N.x)`

E adalah P untuk arch atau O untuk tail. Tolak nilai nonfinite, penyebut hampir nol, ray terbalik, urutan start/arch/tail salah dan hasil di luar permukaan. Jangan clamp pemetaan yang salah supaya seolah valid.

Tinggi arch live mengikuti puncak alis terdeteksi. Soft Arch memakai tinggi tersebut; Straight menurunkan maksimal 1,5 mm dalam model, High Arch menambah maksimal 1 mm, Feathered maksimal 0,4 mm. Posisi X dihitung ulang pada ray pupil untuk tinggi itu; bukan selalu 64% lebar alis. Batas milimeter ini adalah delta model, bukan klaim akurasi hasil. Curve diinterpolasi melalui start, arch dan tail personal. Outline dan patch preview menggunakan attachment yang sama. Thumbnail style tetap ilustrasi, bukan hasil scan user.

Ini konvensi placement makeup sesuai referensi pengguna, bukan aturan kecantikan universal. Asimetri alami dipertahankan; kedua sisi dihitung sendiri. Tidak mengklaim satu bentuk tepat bagi semua wajah.

## Gate dan lifecycle

- Vision harus menyediakan dua eyebrow, dua eye contour, dua pupil dan nose. Tidak ada fallback diam-diam ke template live saat eye scan hilang.
- Eye side dihubungkan ke eye transforms, bukan mengandalkan label kiri/kanan pada kamera mirror.
- Eye aspect ratio menolak mata tertutup; pupil harus berada di dalam batas mata dan cukup dekat tengah. AR blink blendshape juga menahan scan ketika berkedip.
- Kalibrasi dibatasi pose mendekati frontal (normal wajah dalam sekitar 20° dari arah kamera). Ini membatasi pendekatan bidang kedalaman pupil; setelah kalibrasi ARKit tetap menggerakkan attachment.
- Brow mapping harus lolos gate anatomi relatif wajah dan surface binding.
- Default tiga observasi pada timestamp berbeda, maksimal selisih dua detik antarsampel. Perubahan titik melebihi 4,5% lebar brow mengulang hitungan. Threshold prototipe ini bukan confidence akurasi.
- Setelah scan diterima, freeze calibration dan gunakan mesh baru tiap frame. Tidak mengubah brow mengikuti gerakan pupil setelah kalibrasi.
- Tracking loss/refit/anchor change menghapus scan dan guide. Worker epoch guard menolak hasil lama. Tidak menyimpan frame mata atau biometric template ke disk.

## Batas dan uji perangkat

Eye contour, nose extreme dan pupil Vision tetap estimasi. Pose miring, mata berkedip, kacamata/refleksi, gaze ke samping, hijab/rambut yang menutupi brow dan lighting dapat gagal. Rumus menambah patokan terukur; tidak membuktikan placement sudah tepat di wajah nyata. Jangan menyebutnya pixel-perfect sebelum acceptance iPhone.

Periksa: pandangan lurus dan kedip; scan tidak selesai dari satu frame; tutup satu mata atau hidung; putar kepala saat scan; kedua sisi tidak tertukar; A tegak dari sisi hidung, C lewat pupil, B lewat sudut luar mata; style berbeda memindahkan curve sesuai rumus; Before menyembunyikan warna/garis; Refit dan loss membuang hasil lama; maju/mundur 25/35/50 cm setelah kalibrasi tidak mengubah proporsi. Ukur error landmark dan jitter dari rekaman perangkat sebelum menyatakan lebih presisi.

## Sumber teknis

[Apple VNFaceLandmarks2D](https://developer.apple.com/documentation/vision/vnfacelandmarks2d) menyediakan eye/eyebrow/nose/pupil regions. [Apple leftPupil](https://developer.apple.com/documentation/vision/vnfacelandmarks2d/leftpupil) menyatakan pupil bisa tidak akurat saat berkedip. Rumus makeup di atas mengikuti konvensi pada referensi pengguna, bukan klaim dari API Apple.

## Verifikasi — -Nimah, 20 October 2026

Simulator: 68 tes, 65 lulus, 3 hardware skip, 0 gagal. Meliputi intersection formula, kebutuhan eye/pupil/nose, penolakan mata tertutup, titik kedua sisi, gate tiga timestamp berbeda, frame berulang/perubahan mapping, loss dan Before/After. Test runner sempat gagal launch karena simulator Busy; pengulangan tanpa parallel runner selesai sukses.

Signed iPhone build berhasil. Percobaan install ditolak CoreDevice karena iPhone terkunci saat developer disk image dipasang (kAMDMobileImageMounterDeviceLocked). Versi Eye & Brow Scan ini belum terpasang dan belum diuji pada wajah nyata. UI controls diperiksa di Simulator; scan live tidak disimulasikan. Source/ZIP lokal diperbarui; belum dipush ke GitHub.

## Koreksi alis terlalu tinggi — -Nimah, 20 October 2026

Penyebab source yang ditemukan: curve live menambah `span * archRatio` di atas level start/tail, sehingga High Arch dapat naik sekitar 10 mm pada span 4 cm. Kini memakai `mapping.arch.y` hasil scan sebagai baseline. Batas delta style kecil dipakai bersama rumus ray yang sama untuk curve dan keypoints; tidak menggeser seluruh overlay ke bawah dengan screen offset.

Kedalaman bidang mata tidak lagi memakai pusat bola mata (`eyeTransform.z`). Vertex mesh nyata di sekitar kelopak diproyeksikan ke sensor dan dicocokkan dengan contour eye; median kedalamannya menentukan bidang pupil. Jika coverage/proximity tidak cukup, scan ditolak. Pusat eye transform hanya membantu identitas sisi dan pencarian area. Ini tetap pendekatan permukaan kelopak berbasis mesh 3D + landmark 2D, **bukan pemindaian 3D pupil/iris secara langsung**.

Verifikasi terbaru: 70 tes, 67 lulus, 3 skip hardware, 0 gagal; signed iPhone build berhasil. Regresi menguji seluruh centerline/arch tidak melewati batas tinggi scan dan kedalaman mesh berbeda dari pusat mata. Batas delta 1 mm bukan hasil pengukuran error di wajah. Perangkat terdeteksi namun masih terkunci (`passcodeRequired: true`); versi koreksi belum dipasang atau diuji live. Setelah memasang build baru, lakukan Refit agar attachment lama tidak dipakai.

## Koreksi berdasarkan screenshot 09.09 — -Nimah, 20 October 2026

Screenshot pengguna menunjukkan kepala outline di atas rambut alis dan formula ray melintasi mata. Versi sebelumnya masih menghubungkan start/arch/tail hasil formula sebagai shape dan memakai brow maksimum sebagai baseline. Hal itu tidak sama dengan mengikuti garis tengah jejak alis.

Kini `ObservedBrowFit` melakukan quadratic least-squares pada **seluruh** titik eyebrow yang dipetakan ke mesh, dalam koordinat X brow ternormalisasi. Shape memakai span deteksi aktual, tanpa memperpanjangnya ke tail formula. Kontribusi sisi atas/bawah contour masuk fit; titik tertinggi tidak dijadikan centerline keseluruhan. Soft Arch mengikuti fit, perubahan style lain dibatasi kecil. Ketebalan adalah estimasi residual yang dibatasi, bukan hasil segmentasi rambut. Warna preview dan outline memakai shape yang sama.

Tiga titik tutorial kini head/arch/tail dari shape yang di-fit. Titik dan garis formula disimpan terpisah sebagai referensi opsional, default off. Label status menjadi "Check brow alignment" agar pemetaan selesai tidak disamakan dengan alignment yang sudah terbukti tepat. Tidak ada screen-space offset turun seragam untuk menyamarkan error.

Deteksi Vision tetap dapat salah dan koordinat kamera live perlu acceptance perangkat. Fit ini tidak membuktikan pixel-level eyebrow segmentation atau 3D iris scanning. Jika raw landmark sendiri salah, curve juga bisa salah; gunakan debug landmark/refit untuk diagnosis, bukan menganggap rumus otomatis benar.

-Nimah, final verification 20 October 2026: 72 tests, 69 passed, 3 hardware skipped, 0 failures. Signed iPhone build succeeds. Final observed-brow outline/tutorial build installed successfully on iPhone 17 at 09:13 Asia/Makassar. On-face alignment after installation has not been measured or accepted. Reopen module and Refit to clear previous calibration. Source remains local, not pushed.
