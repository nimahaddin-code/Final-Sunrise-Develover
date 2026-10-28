## Tutorial camera handoff and welcome revision — 2026-10-29

Try On deactivates before pushing tutorial. Paused/revoked/dismantled ARSCNViews detach
from the shared ARSession; resume reattaches before acquiring the delegate. This avoids
retained navigation views remaining attached while the new screen owns the camera.
Tutorial split comparison uses the same Metal camera pass, with pigment scissored to
the left half, instead of attaching a second ARSCNView to the shared session. Tutorial
handoff carries brow overlay/hiding settings; Filter Off also disables natural-brow hiding.
Welcome version 2 migrates devices that already dismissed revision 1, without resetting
saved data. Verified device preference was revision 1 before install.

381 Simulator tests executed, 4 skipped, 0 failures, including lease/detachment,
tutorial configuration and welcome migration regressions. Signed Release build and
installation on Nimah New succeeded. Physical tutorial camera/compare acceptance pending.
Logs: /tmp/sunrise-tutorial-camera-tests.log and /tmp/sunrise-tutorial-camera-release.log.
Existing local Xcode project/signing and strings edits preserved. No push or main change.

## Staging merge verification — 2026-10-28

Merged origin/staging eb318b3 with integration ae52cfb, preserving staging’s
scan-free home and latest MediaPipe/ARKit brow pipeline. Hi-fi welcome shows
once then opens Try On; no removed scan routes reintroduced.

- Simulator suite: 378 tests, 4 skipped, 0 failures; production Metal shader fixtures included.
- Generic iOS Release build: succeeded with signing disabled. Signed device build was
  blocked by missing local provisioning profiles; physical-device QA remains pending.
- Logs: /tmp/sunrise-staging-merge-tests.log and /tmp/sunrise-staging-merge-release.log.
- Main unchanged. Existing duplicate model-resource warning remains.

## Mask continuity and welcome upgrade recovery — -Nimah · 28 October 2026

Full suite 340 executed, 4 skipped, zero failures (/tmp/sunrise-mask-welcome-fixed-tests.log); signed Release
build succeeded (/tmp/sunrise-mask-welcome-fixed-build.log). Earlier run correctly caught12 cadence opacity
jumps; no failed assertions were loosened. Current path filters recovery before applying a later smooth expiry
ceiling; exactly zero at250ms default. Same cadence regression now passes. Model nil callbacks retain only the
original timestamped mask until that finite deadline. Plausible native head reprojection is required in grace.
Navigator tests verify new welcome shown once on upgrade and no invalidation of completed scan, while fresh
users still require face+eye scan. Physical flicker/occlusion/onboarding acceptance pending installation.

## Hi-fi onboarding welcome — -Nimah · 28 October 2026

Simulator Debug and signed generic iPhone Release builds succeeded. Fresh disposable iPhone 17 simulator
(0A67E956-C884-449E-A81B-CCDC16CF7C19) shows actual onboarding at launch; screenshot in workspace
output/onboarding-hifi/onboarding-iphone17.png inspected for visible CTA, copy and native branding layout.
Welcome-only presentation change: existing Get Started closure enters .faceScan, followed by .eyeScan and
.preparing. Saved results/Retake navigation untouched. No new automated tests for reversible visual changes.
Physical device welcome, VoiceOver and largest Dynamic Type acceptance not performed.
Logs: /tmp/sunrise-onboarding-hifi-build.log, /tmp/sunrise-onboarding-hifi-release.log.

## Three reference blush looks v0.5.0 — -Nimah · 28 October 2026

Full suite: 337 executed, 4 skipped, no failures (/tmp/sunrise-blush-three-tests.log). Final selected makeup
GPU suite: 48 tests, no failures (/tmp/sunrise-blush-three-final-gpu.log). Signed Release build succeeded
(/tmp/sunrise-blush-three-build.log). Install attempted; CoreDevice could not locate paired iPhone despite
user confirming connection. Device appearance, smoothness and occlusion acceptance pending. Synthetic GPU
checks validate distinct cheek footprints and bridge channel only in Sunkissed. No TikTok equality claim.

## Brow stability revision — -Nimah · 27 October 2026

45 selected makeup tests passed, zero failures (/tmp/sunrise-brow-stability-tests.log). Includes local jitter
attenuation, 3 mm expression step response and gap reset plus actual GPU atlas/pixel/occlusion tests.
Signed Release build succeeded (/tmp/sunrise-brow-stability-build.log). Device jitter acceptance pending;
no measured visual jitter reduction or brow FPS improvement claimed from synthetic results.

## Makeup unavailable recovery — -Nimah · 27 October 2026

Physical metrics identified segmentation_unavailable: CancellationError() with segmenter_available=true and
223 ms mask age; shader error none. Expected cancellation no longer latches unavailable; recovered model/fit
clears prior errors. Face-skin-only conversion uses 256 long side; default eyeliner path unchanged. Freshness
limit remains 150 ms. Selected makeup suite passes (including real model stop/start and canceled preparation
regression), signed Release build succeeds and installs. User recheck and post-change mask latency pending.
Logs: /tmp/sunrise-unavailable-recovery-tests.log, /tmp/sunrise-unavailable-recovery-build.log.

## Personal cheek placement v0.4.0 — -Nimah · 27 October 2026

Full simulator suite: 332 executed, 4 skipped, zero failures; log /tmp/sunrise-personal-blush-full-tests.log.
Tests exercise same style with unilateral cheek-width change (other side unchanged), changed measured
midface spacing, invalid configuration, plus existing GPU, category/navigation and persistence regressions.
Signed Release build succeeded (/tmp/sunrise-personal-blush-release.log). Device aesthetic acceptance pending.
Existing staged/unstaged eyebrow upgrade retained. No staging/main merge or push in this task.

## Blush camera parity correction — -Nimah (27 October 2026)

Removed paired extra horizontal reflections from Metal background and face projection after user reported
a flip on switching to blush. Signed Release build succeeded; git diff --check clean. Physical camera parity
requires user confirmation; the prior visual/FPS acceptance predates this orientation correction.

## Beauty blush ARKit / Metal v0.3.0 — -Nimah (27 October 2026)

Full suite: 327 executed, 4 hardware skips, 0 failures. Log `/tmp/sunrise-beauty-blush-acceptance-tests.log`.
Actual Metal shader tests (not node-existence assertions): camera tint pixels, obstruction restores camera,
sRGB decode round trip, UV atlas independent cheek channels and nose/upper-area exclusion. A synthetic native
boundary test identifies a mouth hole without semantic indices. Config invalid values rejected; both final
JSON schemas validate and six malformed configuration cases are rejected. No physical occlusion quality or
sustained FPS is established by these synthetic tests. Documentation/parameters/dependencies in
`Docs/Decisions/0010-metal-blush.md`. Final exported assets/config/schema in workspace
`output/beauty-blush-v0.3.0`. Signed Release build installed and independently launched on iPhone 17.

Physical iPhone 17 Release acceptance, 27 October 2026: user confirmed blush visible, attached during
still/smile/slow turns, and blended. User answered yes to hiding behind an obstruction; brush-specific
coverage was not independently confirmed. Latest approximately two-second runtime window: completed /
presented 59.98 FPS, mean GPU 1.33 ms, CPU frame arrival-to-GPU-completion p95 54.06 ms (not sensor-to-photon),
projection agreement 0.000037 pixels, segmentation age 101.67 ms, fresh mask, nominal thermal state, no shader
or engine error. Visibility 0.726; 77 pigment frames counted in that window. These are a snapshot, not a sustained
thermal benchmark or an accuracy guarantee. User's “ok” does not establish the requested two-minute duration
or tutorial/category regression completion. Multiple skin tones, lighting changes, fast/extreme poses and thin
brush/hair boundaries remain unverified. Bundled face-skin model initialization preflight also passed after
the full 327-test suite (`/tmp/sunrise-beauty-blush-model-preflight.log`).


## Blush v0.2.1 — feedback perangkat · -Nimah (27 Oktober 2026)

Pengguna mengonfirmasi blush terlihat, tetapi meminta lebih lebar/halus. JSON aktif dan ekspor standalone
`output/blush-reference-v0.2.1/blush-reference.v0.2.1.json` sekarang sinkron untuk enam preset aktif.
Rasio area ellipse desain meningkat sekitar 45–53%; area aktual tetap terkena safe-mask dan bukan diukur
langsung dari foto. Kurva radial memakai smoothstep mix JSON; mask inward tiap batas dikalikan terpisah,
lebar transisi 0.022 W. Grid blush 48x32 tetap dicache; warna/intensitas tidak memicu rebinding.
34 tes makeup lolos, 0 gagal (`/tmp/sunrise-blush-v021-tests.log`), termasuk pembandingan luas/warna off-center
terhadap parameter v0.2.0, kontinuitas tepi, safety mask, actual pixel rendering dan binding reuse.
Revisi ini tetap proposal kalibrasi; penerimaan visual/performa di iPhone pending. Tidak mengubah alis,
eyeliner, hasil scan, atau rute Retake. Tidak memaksa scan ulang.

## Blush v0.2.0 consumed by app — 27 October 2026 · -Nimah

Resource SHA-256: `45fa1c9a4e755a2522a0c019f184187286075e2038ce5d0bb48cdc5701f3db11`.
Six active preset parameters match `output/blush-reference-v0.2.0/blush-reference.v0.2.0.json`; original brow
half-thickness remains 0.065. Full suite: 322 executed, 4 hardware skips, 0 failures; log
`/tmp/sunrise-blush-v2-tests.log`. Checks include large field radii, broad off-center color, inward-safe mask
feather with zero leakage, default intensity 0.72, depth-occluder pixel rendering, cached shade updates,
category selection, stored-fit recovery and navigation. SceneKit owns linear color conversion/compositing;
no extra manual sRGB decode was added (would double-convert existing UIColor inputs).
No recorded image similarity to the generated target or device calibration is claimed. Existing conservative
eye-center mask and lack of brow/blush hand/hair segmentation are documented limits. Device visual check pending.

## Brow size revision v0.1.1 — -Nimah

Bundled JSON is now an integration calibration revision, not byte-identical to the original v0.1.0 artifact.
SHA-256: `85529d700d0d97fb92518f10247121c9d9cbc8538f3c26edf1eee50f780d37b7`.
Change: half-thickness design 0.035 → 0.065 of observed brow width, within the declared 0.01...0.08 range.
Head/tail length and arch displacement cap unchanged. Regression measures body thickness and preservation
of observed span. 53 selected eyebrow/makeup tests passed, 0 failures (`/tmp/sunrise-brow-size-tests.log`).
Device visual acceptance remains pending; covered eyebrows cannot establish full anatomical alignment.

## Depth occluder control — 26 October 2026 · -Nimah

30 MakeupPreferenceTests passed with cosmetic depth reads disabled (`/tmp/sunrise-pigment-depth-tests.log`).
The visible-color pixel test includes a colorless, depth-writing surface in front of pigment. Re-enabling
old pigment depth reads for the control makes that same test fail: 0 visible pixels, expected >40;
`/tmp/sunrise-pigment-depth-control.log`. Source restored to the passing policy afterwards.
This establishes a reproduced self-occlusion failure mode; confirmation on the user's AR camera is pending.

## Partial surface rendering regression — -Nimah

After device report of absent pigment, saved analysis/fit and enabled recommendations were present.
Added local render-state flags (no image/mesh/coordinates) to distinguish absent guides, config-hidden output,
missing outline samples and rendered patch counts. Device visual confirmation is still required.
Renderer now splits brow strips around invalid boundary samples rather than rejecting the entire curve.
Blush field eligibility is independent of peripheral tutorial boundary binding. Exact JSON radii remain intact.
Targeted MakeupPreferenceTests passed, including missing-outline regression and actual pigment pixel rendering:
`/tmp/sunrise-pigment-gap-tests.log`. These are robustness fixes, not proof of the reported device cause.

## JSON database integration — 2026-10-26 · -Nimah

Branch `integration/latest-hanum-khalish`. Bundled JSON SHA-256:
`a515dc4e4b6e55f6e8c8c1451340124160311840d0cf37ae8e60c812114b597b` (identical to authored artifact).
Full simulator suite: 318 executed, 4 hardware skips, 0 failures; log `/tmp/sunrise-database-full-tests.log`.
Signed Release iPhone build passed; log `/tmp/sunrise-database-release.log`.
Tests cover six JSON assignments, uncovered shapes, required-parameter corruption, full-width ellipse radii,
rotation, nose exclusion, actual SceneKit color pixels, binding reuse on shade changes, fit persistence,
exclusive category, and navigation regression. No physical-device visual result is claimed by these tests.
First visual check should reuse saved fit (no compulsory Retake). Check each category, shade/intensity,
tutorial return, picker cancel, and force-close/reopen. Publication to staging remains pending device acceptance.
Known adapter limits: conservative eye-center exclusion instead of measured lower-lid mask; brow/blush have
no hand/hair segmentation. Natural cosmetic accuracy and tracking error require device calibration.

# Saved scan flow verification — 26 October 2026 -Nimah

- Sources: Khalish scan-overlay-lines `b2d8ae0`, Hanum Eyeliner-Hanum `071d2a0`, Hanum Profile `502e423`.
- Full iOS simulator suite: 314 executed, 4 skipped, zero failures (`/tmp/sunrise-persist-team-final-tests.log`).
- Regression covers saved fitting recreation, no extra Vision scan on attachment restoration, and Retake clearing fit.
- iPhone Release build passed (`/tmp/sunrise-persist-team-release.log`).
- Installation pending: CoreDevice could not locate Nimah New. Previous installed build does not include saved-scan flow.
- Device reopen/retake acceptance is pending. Earlier lifecycle build was confirmed smooth by the user.
- Older installations have saved classifications but no fitting descriptors: enter home using saved results, with a Profile Retake action if pigment is unavailable. One explicit Retake saves the new fitting format; later launches reuse it.

# Latest team integration — 26 October 2026 -Nimah

- Sources: Hanum eyeliner/tutorial `071d2a0`, Hanum profile `502e423`, Khalish scan/debug `99791b3`.
- iOS simulator suite: 308 executed, 4 skipped, 0 failures (`/tmp/sunrise-team-latest-tests.log`).
- Signed iPhone Release build: passed (`/tmp/sunrise-team-latest-release.log`).
- Mac scan editor build: passed (`/tmp/sunrise-team-mac-build.log`).
- Installation: succeeded on Nimah New, bundle `com.sunrise.foundation`.
- Pending: user verification of cold launch, initial face/eye scan, exclusive makeup categories, tutorial return, profile and camera recovery.
- Blush appearance remains awaiting visual acceptance; no physical-device FPS measurement or zero-bug guarantee.
- Original local changes are backed up in stash `backup local pigment and category before team merge` and `/tmp/sunrise-pre-team-merge.patch`.

# Validasi MVP — 15 Oktober 2026

> -Nimah · team integration: simulator build succeeded; 196 tests, 192 passed, 4 skipped, 0 failed. All 43 FaceShape/MakeupTryOn/Onboarding source files match Eyeliner-Hanum 0493a87 byte-for-byte. Native face alignment remains unverified. See CodeOwnership.md for attribution.

> -Nimah · follow-up overlay kedua: signed build berhasil dan terpasang di iPhone 17 Nimah New pada 08:32. Simulator 81 tes: 78 pass, 3 hardware skip, 0 fail. Percobaan baru mengaktifkan After/guide lagi; dropout singkat pada anchor sama melanjutkan mapping. Acceptance gejala perangkat tetap belum dikonfirmasi pengguna. Rincian: Docs/BrowBlushPreferences.md.

> -Nimah · 22 October 2026, scan recovery: reset/loss now invalidates old worker ownership, failed area generation retries after a cooldown, and scan UI explains positioning (near/far, movement, eyes and pose) with Scan ulang. Distance 25–60 cm is a starting suggestion, not an enforced hardware limit. Signed iPhone build succeeded and installed on Nimah New at 06:27. Simulator: 80 tests, 77 passed, 3 hardware skipped, 0 failures. Real-face repeat-use acceptance remains pending. Previous installation/test notes below are historical.

> -Nimah · 22 October 2026: Build signed iPhone berhasil; 78 tes simulator: 75 pass, 3 hardware skip, 0 fail. UI pilihan shape/blush/tutorial diperiksa. Instalasi iPhone terbaru gagal karena koneksi terputus; alignment belum tervalidasi. [Rincian](BrowBlushPreferences.md).

> -Nimah, 20 October 2026: live eyebrow mapping sekarang wajib Eye & Brow Scan dan rumus nose–pupil–outer eye; baca [EyeBrowMapping](EyeBrowMapping.md). Catatan bounds/fixed arch sebelumnya di bawah adalah riwayat implementasi.

> -Nimah, 19 October 2026: scope terbaru mencakup closed eyebrow outline, lima forehead style dan tutorial manual. Baca [BrowForeheadGuide](BrowForeheadGuide.md) untuk status terbaru, batas hairline dan testing; catatan sebelumnya di bawah adalah riwayat.

> -Nimah, update eyeshadow: seluruh makeup live kini memakai **vertex colors** untuk area non-eyeliner dan **strip attachments** untuk eyeliner. Atlas lama tidak digunakan pada jalur live. Bentuk mask area non-eyeliner masih estimasi dan belum lolos acceptance wajah nyata.

> -Nimah: Hasil terbaru ada pada bagian **Surface-attached eyeliner — 15 Oktober 2026** di akhir dokumen. Catatan sebelumnya adalah riwayat, bukan bukti acceptance wajah saat ini.

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

## Update Sculpted Glam dan dotted guide — 15 Oktober 2026, -Nimah

- Foto referensi pengguna tersimpan sebagai asset lokal GlamReference. Tidak diunggah ke GitHub/server.
- Template titik manual untuk lima langkah; dipetakan ke vertex terdekat, dedup, mengikuti mesh. Face-depth mesh menutup marker sisi jauh; hand/hair occlusion tidak diimplementasikan.
- Blush dapat beralih Dots/Soft area; empat tahap lain pada look glam memakai titik saja. Sketsa edukasi tersedia untuk Simulator/manual mode.
- Capture memakai raw camera buffer sehingga marker tidak ikut foto; orientasi portrait/mirroring baru memerlukan validasi perangkat fisik.
- Generic iOS device build berhasil. Final Simulator tests: **19 passed, 0 failures, TEST SUCCEEDED**. Dua test baru memeriksa empty mesh/dedup/index validity serta distinct targets semua langkah.
- Katalog versi baru terbaca lewat UI Simulator dengan Sculpted Glam dan asset yang benar. Pemeriksaan detail/sketsa lanjutan terhenti karena user mengubah Simulator lalu layanan ScreenCapture gagal. Tidak ada klaim seluruh UI glam sudah diverifikasi visual.
- Semua titik masih placement perkiraan; belum diuji iPhone fisik, terutama eyelid/wing/lip alignment, ekspresi dan self-occlusion. Tidak ada analisis otomatis atau janji hasil wajah identik.
- Perubahan project.pbxproj dan string catalog yang sudah ada saat tugas dimulai dipertahankan. Versi ini lokal pada proyek/branch yang sama, tanpa push GitHub.

## Update try-on + face fitting — -Nimah

- Pengguna menyebut iPhone 17 sebagai perangkat uji. Tidak ada akses ke kamera fisik iPhone tersebut dalam sesi ini.
- Preview warna full look dan titik terpisah dengan empat mode; native geometry dan UV texture dipakai ulang per anchor. Rendering profile menggantikan live fixed-template placement.
- Unit test pertama menemukan sensitivitas pembulatan pada batas upper-eye rim saat mesh diperbesar. Toleransi relatif ukuran mesh diperbaiki; test skala yang sama kemudian lulus tanpa melonggarkan assertion.
- Final Simulator regression: **26 tests passed, 0 failures, TEST SUCCEEDED**. Tambahan memeriksa scale consistency, topology/partial fit, texture transparency, mode flags dan readiness fit.
- Generic iPhone build final: **BUILD SUCCEEDED** setelah penyelesaian UI, memakai SDK iOS 26.5 dan tanpa code signing.
- Tidak ada pengukuran physical jitter/latency/FPS, akurasi pada jarak tertentu, eye/lip pixel segmentation, atau capture effect. Tidak mengklaim 100% presisi maupun keberhasilan semua area dari build/unit test.
- Source tetap di Final-Sunrise-Develover/feature/nimah-mvp lokal; paket MVP yang sama diperbarui. Tidak ada upload GitHub atau penyimpanan mesh/face telemetry.

## Perbaikan makeup tidak terlihat — 15 Oktober 2026 — -Nimah

- Screenshot iPhone 17 pengguna menunjukkan titik aktif pada mode Points + makeup, tetapi bukan bukti lapisan warna berhasil. Tes sebelumnya hanya memeriksa isi atlas.
- Regresi render GPU dengan SCNRenderer, bidang depth-only dan atlas asimetris menemukan urutan baris atlas terbalik terhadap UV SceneKit. Raster sekarang membalik baris saat menulis CGImage. Premultiplied alpha tetap dipertahankan; tidak mengklaim alpha sebagai akar masalah yang telah terbukti.
- Pigmen Sculpted Glam diperkuat (blush, contour, eyeshadow, lips), dan mode alpha material dibuat eksplisit. Ini simulasi warna, bukan transfer otomatis foto referensi.
- **27 tes lulus, 0 gagal**, termasuk pemeriksaan piksel warna pada sisi mesh yang benar dan intensitas nol yang mengembalikan latar. Uji render memakai geometri sintetis, bukan ARFaceGeometry dari iPhone.
- Belum ada verifikasi kamera fisik setelah perbaikan. Perlu membandingkan Original camera vs Makeup only pada wajah iPhone 17; jangan menyimpulkan presisi, semua area, atau realisme dari simulator.
- Build generic iPhone menggunakan SDK iOS 26.5 tanpa signing: **BUILD SUCCEEDED**. Paket ZIP lokal diperbarui; belum dipush ke GitHub.

## Surface-attached eyeliner — 15 Oktober 2026 — -Nimah

- Diagnosis source: full look sebelumnya aktif default; kini OFF dan scope reset ketika langkah berganti. Eyeliner tidak masuk atlas sama sekali. Titik dan strip memakai SurfaceAttachment yang sama.
- Implementasi: upper-rim strip + barycentric binding; style dihitung di worker; blink per mata; native face depth occlusion; current generation + active anchor + session guards; stale frame timeout. Tidak ada smoothing pose atau sizing berbasis distance manual.
- Debug tersedia pada Debug build: mesh wireframe, eye region IDs/kiri-kanan, label face-local, atlas asimetris U/V, active anchor/step/scope. Tidak merekam wajah/mesh secara default.
- Lingkungan final: Xcode 26.6 / SDK iOS 26.5. Perangkat terhubung: **iPhone 17, iOS 26.5.2 (23F84)**. Build ditandatangani dengan Team yang sudah dikonfigurasi di proyek; tidak ada penggantian bundle identifier atau penghapusan data aplikasi.
- **Final iPhone suite: 35 tests, 0 failures, TEST SUCCEEDED.** Meliputi scope default, hole rejection, triangle deformation, area mata vs hidung/pipi, guide membership, style bounds, UV reader stride, actual strip render + depth occluder dan mesh netral ARKit.
- **Simulator suite: 35 discovered, 1 hardware test skipped, 0 failures, TEST SUCCEEDED** pada revisi sebelum penambahan guard session terakhir; final guard kemudian dibuild dan diuji penuh pada iPhone di atas.
- Bukti diagnostik mesh netral hardware: UV renderer cocok dengan raw UV pada 1220/1220 vertex; flipped-V cocok pada 0/1220. Ini mengoreksi asumsi bahwa dua buffer mesti berbeda; pengambilan UV renderer tetap dipakai untuk eksplisitnya kontrak. Eyeliner sendiri tidak memakai UV.
- Uji render pertama gagal karena near clip kamera fixture tidak sesuai skala meter wajah; fixture diperbaiki dengan zNear 0.001 dan depth surface ditambahkan. Assertion lokasi mata/hidung/pipi tidak dihapus.
- Build terbaru terpasang melalui Xcode testing dan berhasil dibuka pada iPhone 17 dengan bundle yang sama. Tidak memulai atau merekam sesi wajah secara otomatis.
- **Belum diuji pada wajah pengguna:** ketepatan upper lash line/wing, jitter/latency/FPS live, expression accuracy, mirroring label, lighting/eyelid diversity, hand/hair occlusion. Kelulusan tes hardware netral bukan acceptance untuk kondisi ini. Tidak ada angka error yang diklaim.
- Gate ekspansi attachment/fine adjustment ke shadow/lips/blush/contour masih menunggu uji wajah nyata. Full look yang tersisa adalah komposisi eksperimen lama dengan eyeliner baru, bukan fitur yang telah divalidasi.
- Source dan paket ZIP proyek sama diperbarui lokal. Belum dipush ke GitHub. Rencana pemetaan, usulan toleransi dan handoff: MakeupAccuracyPlan.md / EyelinerDeviceTesting.md / TeamWorkstreams.md.

## Kasus eyeshadow di pipi bawah — 15 Oktober 2026 — -Nimah

- Screenshot terbaru menunjukkan langkah Eyeshadow aktif, titik di mata, dan warna gelap di bawah. Ini bukti mismatch lapisan live lama dengan panduan; transform UV/image spesifik yang salah belum diisolasi melalui pengukuran wajah pengguna.
- Jalur live atlas dihapus dari seluruh makeup non-eyeliner. SurfaceRenderProfile menggantikan baked texture profile pada runtime; SurfaceMakeupRenderer menggabungkan mask ke straight RGBA per vertex dan membangun geometry dari vertex frame yang sama. Tidak ada texcoord pada geometry pigmen produksi. Eyeliner mempertahankan strip attachment.
- Fitting tidak lagi menunggu pembacaan UV atau pembuatan atlas. Utilitas atlas tetap ada untuk tes historis/diagnostik dan palet, tidak digunakan pada makeup live.
- **Final iPhone 17 / iOS 26.5.2: 38 tests, 0 failures, TEST SUCCEEDED.** Tiga regresi baru mengecek batas vertex eyeshadow, pixel render produksi pada fixture sintetis, serta pixel render produksi pada mesh netral native ARKit. Keduanya memeriksa kelopak berwarna, hidung/pipi bawah bersih, intensity nol kembali putih, serta tidak adanya UV pada geometry pigmen.
- Build perbaikan terpasang lewat testing; aplikasi dibuka kembali pada iPhone yang sama. Tidak mengambil/merekam wajah secara otomatis. Lokasi pada wajah pengguna, bentuk eyeshadow dan jitter live masih perlu retest; tidak menyatakan acceptance wajah telah lolos.
- Perubahan ini memperbaiki pengikatan render, bukan merancang ulang mask blush/contour/lips atau membuktikan ketepatan anatomi seluruh fitur. Pilih satu layer saat retest. Paket ZIP yang sama diperbarui; belum dipush ke GitHub.

## Eyebrow Guide — 18 Oktober 2026 — -Nimah

Source baru menggunakan Vision eyebrow landmarks dari ARFrame yang sama, raw-image ray intersection dan barycentric guide attachment. Shared manager/lease menjaga satu configured ARSession untuk semua layar region. Straight, Soft Arch, High Arch, Feathered, dots/dashes, show/hide/refit dan debug diimplementasikan. Tidak ada vertex alis hardcoded atau fake live camera.

Final Simulator: **50 tests discovered / 48 passed / 2 hardware skips / 0 failed**. Final generic signed iOS Debug build: **BUILD SUCCEEDED**, instalasi akhir di iPhone 17 sukses. Run/test fisik alis tertahan iPhone locked; final UI recheck tertahan Mac locked. Tidak mengklaim live eyebrow detection/accuracy sudah lolos di iPhone. Rincian verifikasi dan langkah acceptance: [EyebrowTesting](EyebrowTesting.md); mapping/kontrak: [EyebrowModule](EyebrowModule.md).

-Nimah, preview verification: Simulator 62 tests — 59 passed, 3 hardware skips, 0 failures. Tests cover concave mask/feather, Before isolation and patch movement with mesh deformation. Build iPhone succeeds; live on-face preview and performance remain unverified.

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

## Xcode local registration repair — -Nimah

User reported build errors after merge. Reproduction found the local project file had 132 objects instead of the merged 322; missing compile membership produced cannot-find-type errors for FaceShapeStore, MakeupPlan and the live guide modules. Closed the open Xcode workspace before repairing, restored the complete graph from main, saved in native OpenStep format and retained local Nimah signing team WP97CT3PT7. Semantic comparison against main confirms all merged object IDs remain; only app development-team values change. Signed generic iPhone build then succeeded. All 43 teammate module files remain identical. No native camera acceptance is implied. Reopen the repaired project to refresh Xcode's in-memory graph.

## Feature transition lifecycle optimization — -Nimah

User approved lifecycle-only edits in Hanum modules. Simulator: 197 tests / 193 pass / 4 skip / 0 fail; signed iPhone build succeeded. See Performance.md. No measured device FPS or transition-latency improvement is claimed. Unrelated local localization changes were left untouched.

## Single implementation per feature — -Nimah

Tech lead requested Khalish eyebrow/blush takeout. Scan/result remain Khalish; eyebrow/blush route to Nimah with scan handoff; eyeliner routes to Hanum only. Simulator 188 tests: 184 pass, 4 skip, 0 fail. Deleted-feature assertions were replaced with checks that the old catalogs are empty, stale requests cannot activate removed filters, and Nimah receives scan/region input. See CodeOwnership.md for the current scope.

## Latest team merge + scan-once flow — -Nimah

Merged Eyeliner-Hanum through 9c8aaf4 (hand occlusion/lid flow) and chore/mediapipe through efdd168 (separate Khalish eye scan and onboarding). Preserved Nimah-only eyebrow/blush. Resolved two independent EyeLandmarks types and duplicate output filenames using EyeScanLandmarks for the scan model; mathematics retained. MediaPipe pinned to revision 50505c8312c7eacb1bd411cecdc4cc9fd08d53cb.

Simulator: 241 tests, 237 pass, 4 skip, 0 fail. Signed iPhone build succeeded. Regressions cover immediate preview/tutorial from saved face shape, eye measurement/lid handoff, eye-plan independence from face shape and neutral fallback for unclear eyes. Live alignment and actual makeup accuracy still need physical acceptance. Saved classification does not remove the camera's need to track current pose; no repeat classification or Continue-scan action is required.

## Staging: one scan-assigned result — -Nimah

- Merge latest published Eyeliner-Hanum 431a9e5. Remote chore/mediapipe efdd168, feat/face-shape aee8264,
  feature/nimah-mvp 3c963e5 and main 7cb99c4 are ancestors of the integrated staging history.
- Simulator iPhone 17: **257 tests, 253 pass, 4 skipped, 0 failures**. Includes scan assignment enforcement,
  missing coverage, clearing stale makeup and updating home after rescan, plus latest Hanum geometry/ink tests.
- Signed generic iPhone Debug build: **BUILD SUCCEEDED**, restoring Nimah's existing WP97CT3PT7 team after merge.
- No live device accuracy/performance acceptance was performed in this change.
- Manual iPhone check: scan face/eyes once; tap each tool; confirm its single assigned reference (see
  BrowBlushPreferences.md), adjust shade/intensity, compare Before/After, open tutorial; rescan with a different
  result and confirm labels and overlays refresh. Missing scan/unsupported catalog shape must leave that layer off.
- References are an on-device catalog. Pear/rectangle lack an assignment and are explicitly unavailable.

## Reference shades and palette picker — -Nimah

- Simulator suite: **259 tests, 255 passed, 4 skipped, 0 failures**. Follow-up palette/preference suite:
  **11 tests, 0 failures**, including EXIF rotation, letterbox rejection, pixel sampling and shade/intensity transfer.
- Signed generic iPhone build: **BUILD SUCCEEDED**. No physical camera capture or live colour/overlay acceptance
  was performed. Use the manual checklist in BrowBlushPreferences.md on iPhone 17.
- Photos stay in memory, processing is off the UI thread, maximum raster dimension 1024 pixels. The existing
  camera usage description now covers rear-camera palette capture. System PhotosPicker requires no full-library read grant.
- Preset colours are approximate sRGB interpretations of the supplied product images; no calibrated match is claimed.

## Visible pigment fix — -Nimah

- Fixed layered render snapshot dropping the eyebrow input whenever blush was requested.
- Stronger brow/blush alpha and 0.85 initial intensity, narrower feather and 1 mm surface lift reduce fading/clipping.
- Simulator: **261 tests, 257 pass, 4 skips, 0 failures**. Includes combined brow/blush inputs and actual
  offscreen SceneKit rendering with an assertion that the image contains visible coloured blush pixels.
- Signed generic iPhone build: **BUILD SUCCEEDED**. No live iPhone visual acceptance was performed.
- On device: rebuild/run staging, select After, try Pink/Muted Mauve and Brown/Soft black, then turn both tools on;
  check that both stay visible and intensity/Before still remove or soften them as expected.

## Launch-only analysis and fitting — -Nimah

- Simulator: **263 tests, 259 passed, 4 skipped, 0 failures**. Signed generic iPhone build: **BUILD SUCCEEDED**.
- Regression test prepares fitting once from initial-scan input, then reuses it after AR session/anchor recreation.
  Its live pipeline has a provider that fails the test if Vision scanning is invoked; brow and blush remain available.
- Additional checks: all assigned tools are enabled on home entry, launch fitting is selected, welcome persistence
  does not bypass the new-launch scan gate, and cache reset/topology mismatch cannot reuse stale fitting.
- Cold-launch scan/eye flow and live transfer have not been validated on a physical face in this change.
- Device checklist: complete launch scan once, confirm all supported overlays; switch tools/tutorial/palette picker
  and return, with no scan/hold-still prompts; briefly lose tracking and return; terminate/reopen and verify the
  startup scan is required again. Unsupported devices/denied permissions remain in startup with clear fallback.

## Startup preparation recovery — -Nimah

- Simulator: **266 tests, 262 passed, 4 skipped, 0 failures**. Signed generic iPhone build: **BUILD SUCCEEDED**.
- Regression coverage: retry early rejected frames in the same launch scan; preserve the first valid fit; use
  measured brow contours when optional pupil/nose points are absent; disable only unfitted pigment.
- The screenshot's combined startup guard has been split: neutral eyeliner no longer invalidates otherwise
  successful face fitting; failed fitting can continue with available categories while retaining scan results.
- Installation attempted but the iPhone 17 is currently unavailable to CoreDevice. This build has not been
  installed or validated on a real face in this change. Reconnect the device and run the staging build.

## Smooth try-on — -Nimah

270 tests: 266 passed, 4 skipped, no failures. Signed Release iPhone build succeeded. See Performance.md for
work-elimination regressions and required device checks. No measured live FPS or hitch reduction is claimed.
