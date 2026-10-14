# Hasil validasi fondasi

Tanggal pemeriksaan: 14 Oktober 2026, WITA. Produk: SunriseApp; repository lokal: Final-Sunrise-Develover.

| Pemeriksaan | Hasil | Batas bukti |
| --- | --- | --- |
| Xcode toolchain | Xcode 26.6, build 17F113, SDK iOS 26.5 | GUI Xcode tidak diuji dibuka dalam sesi ini |
| Unsigned generic iPhone Debug build | **BUILD SUCCEEDED** | Compile/link saja, tanpa signing atau instalasi iPhone fisik |
| Unit tests | **10 passed, 0 failures — TEST SUCCEEDED** | iPhone 17 Simulator, iOS 26.5; bukan validasi AR |
| App launch | Berhasil di Simulator | Halaman onboarding diinspeksi secara visual |
| Penelusuran UI | Onboarding → Discover → detail Douyin → calibration → tutorial → live guide → comparison → Discover; import; My Looks → detail sample | Smoke check manual lewat UI automation, bukan XCTest UI target; semua jenis layar terbuka |
| Placeholder honesty | Calibration belum cek device, live guide tanpa preview palsu, Save disabled, saved metadata jelas sample | Tidak ada kemampuan kamera/Photos/AR/persistensi di scaffold |
| Tutorial interaction | Next mengubah Blush ke Contour di UI | Batas dan empty tutorial dicakup unit test |
| Permissions | Tidak ada prompt kamera/foto selama penelusuran; tidak ada permission key/call hardware | Izin fitur asli baru ditambahkan saat implementasi |
| File configuration | project.pbxproj dan Info.plist lolos plutil; shared scheme XML valid; semua Swift source masuk project | Tidak ada subfolder source kosong; direktori internal yang dibuat Xcode tidak masuk ZIP |
| CI configuration | YAML templates/workflow valid dan pemilihan Simulator diperiksa secara lokal | Belum dijalankan di GitHub remote |
| Physical device / AR | **Belum diuji, belum diimplementasikan** | Tidak boleh mengklaim keberhasilan face tracking |

Build pertama dalam sandbox gagal mengakses runtime layanan Simulator yang diperlukan asset compiler. Build dan unit test berikutnya berhasil setelah akses layanan sistem diberikan. Karena itu environment ini akhirnya mendukung build/test Simulator; kegagalan awal tidak berarti runtime tidak terpasang.

Screenshot onboarding aktual: [lihat gambar](Validation/Onboarding.png).

Belum diverifikasi: small iPhone layout, seluruh Dynamic Type size, VoiceOver menyeluruh, dark mode visual, setiap konten reference selain sampel Douyin, test CI remote, serta perangkat fisik. Checklist lanjut ada di Testing.md.

10 unit test: 3 navigasi, 2 tutorial, 5 service/state. Test tidak bergantung pada akses kamera atau Photos. Peringatan build yang terlihat berasal dari metadata AppIntents tanpa dependency dan binary XCTest bawaan yang sudah signed; tidak ada error kompilasi Swift pada build yang berhasil.

Pada saat validasi lokal awal, repository Git baru diinisialisasi tanpa commit atau remote. Setelah owner dan visibility dikonfirmasi, repository publik dibuat di [nimahaddin-code/Final-Sunrise-Develover](https://github.com/nimahaddin-code/Final-Sunrise-Develover). Laporan validasi ini mendeskripsikan hasil lokal; hasil CI remote dapat dilihat di tab Actions.
