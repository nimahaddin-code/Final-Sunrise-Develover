# Navigasi

```text
Onboarding [session-only]
└── Main tabs
    ├── Discover [sample catalog]
    │   ├── Reference Detail
    │   │   └── Face Calibration [placeholder; skip]
    │   │       └── Tutorial [previous/next state works]
    │   │           ├── Live Guide [placeholder]
    │   │           │   └── Comparison [placeholder]
    │   │           └── Comparison [placeholder]
    │   └── Reference Import [placeholder]
    └── My Looks [sample metadata only]
        └── Saved Look Detail [no photo]
```

`AppRoute` mendefinisikan semua destination; `AppRootView.destination` memasangnya untuk kedua NavigationStack. UI hanya menampilkan link yang sesuai diagram. Stack dipisah per tab agar switching tab mempertahankan riwayat masing-masing.

`AppNavigator.completeOnboarding()` membuka tab. `returnToRoot(of: .discover)` mengakhiri eksplorasi comparison tanpa menghapus riwayat My Looks. Tombol sistem Back digunakan pada layar detail; alur import tidak mengembalikan hasil karena belum diimplementasikan.

Onboarding tidak disimpan. Langkah tutorial kembali ke awal jika view dibuat ulang. Tidak ada deep link atau restore app state. Uji dengan unit test navigator dan checklist manual di Testing.md; tidak ada UI automation target dalam fondasi.
