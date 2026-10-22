# ADR 0002 — Implementasi MVP lokal

Tanggal: 15 Oktober 2026. Menggantikan batas scaffold pada ADR 0001 untuk paket MVP.

Memakai service live di composition root, onboarding AppStorage, session-local camera/captures, PhotosPicker inspirasi manual, dan persistence actor dengan satu folder UUID per hasil. Blush saja yang dirender AR; empat langkah lain manual. Face mesh weights diikat pada anchor dan deformed geometry; belum divalidasi physical.

Model media bersama hanya Data/metadata; UIImage tetap di UI/session. Kontrak save(metadata) lama dipertahankan untuk mock regression tetapi live menolak tanpa capture. Perubahan berikutnya dapat menghapus overload legacy setelah konsumen tim sepakat.

Komentar -Nimah menandai implementasi fase ini; Khalish dan Hanum dicatat sebagai rekan coder dengan usulan area handoff, bukan author palsu. Tidak ada nama produk final atau deployment.

Pertimbangkan layer media khusus dan migrasi schema jika koleksi membesar. Pertimbangkan export, backup opt-in, thumbnail cache, quota dan delete recovery hanya melalui keputusan produk terpisah.
