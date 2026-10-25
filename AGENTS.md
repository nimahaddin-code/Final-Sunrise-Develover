# AGENTS.md — read this first

## Profile — scan stills

`AppRoute.profile` opens `ProfileView` (face + eye analysis, signature look). Its retake button opens `AppRoute.fullScan`
(`FullScanFlow`: face scan then eye scan in one flow). Portraits are the stills saved by `ScanSnapshots` at scan completion
(face: ARKit frame, oriented via the Vision orientation; eyes: MediaPipe frame cropped around the eyes). Not yet checked on a real device.
