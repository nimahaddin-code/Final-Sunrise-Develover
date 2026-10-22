# Navigasi MVP

```text
Onboarding (persistent)
└── Main Tabs
    ├── Discover
    │   ├── Reference Detail → Makeup Session
    │   └── Reference Import → choose photo + style → Makeup Session
    │       Makeup Session:
    │       ├── supported + permission → stable calibration → Capture Before
    │       │   → Blush AR → Contour → Eyeshadow → Eyeliner → Lips
    │       │   → Capture After → Comparison sheet → Save / finish
    │       └── unsupported / denied / user choice → manual five steps → finish
    └── My Looks → Saved Detail → delete confirmation
```

AppRoute memuat detail, import, session, saved detail. Phase kalibrasi/tutorial/comparison dikelola di dalam session agar camera/captures tidak berpindah via global state. Snapshot sementara hilang saat session keluar; photo inspiration juga session-only.

Return to Discover dari sesi katalog mereset stack Discover. Selesai sesi hasil import kembali ke layar import. My Looks reload saat tampil. Tidak ada deep link atau restore session lintas relaunch; onboarding tersimpan, koleksi tersimpan.
