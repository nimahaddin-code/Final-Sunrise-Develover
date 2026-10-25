# Changelog

Newest first. Add an entry for every feature, entry point, route or rule change, and update `AGENTS.md` when the
structure or usage changes. Group entries under Added / Changed / Fixed / Removed.

## Unreleased

### Added — Profile page
- `ProfileView` (profile button): face shape, eye shape and signature look, with the face portrait and eye strip taken from the scans.
- `ScanSnapshots` keeps one small JPEG per scan on device (not backed up, never uploaded); privacy copy and `AGENTS.md` updated.
- `AppRoute.fullScan` / `FullScanFlow`: the retake button runs the face scan then the eye scan in one go.
