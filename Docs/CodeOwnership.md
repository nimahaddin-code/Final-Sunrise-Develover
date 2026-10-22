# Code attribution

-Nimah · integration 22 October 2026

| Label | Original work | Source |
| --- | --- | --- |
| -Khalish | Face-shape scan, classifier and original makeup try-on foundation | feat/face-shape, aee8264 |
| -Hanum | Eyeliner/eye scan and subsequent try-on improvements | Eyeliner-Hanum, latest 0493a87 |
| -Nimah | MVP session/catalog/storage, eyebrow/blush studio, live guide and scan recovery | feature/nimah-mvp, 053cc73 and 3c963e5 |

A file can have multiple authors. Use GitHub History or git blame for the original author of a line. Existing author history is preserved with merge commits, not squash. Attribution comments were not inserted into teammate source files. Lips-Hanum has no commits beyond the old main.

All 43 FaceShape, MakeupTryOn and Onboarding source files are byte-for-byte identical to Eyeliner-Hanum at 0493a87 after integration. See TeamSourcePreservation.json for blob identifiers. Hanum's branch already contains Khalish's commit and later changes; preserving this branch preserves both histories, without reverting Hanum's later modifications.

Shared integration edits by -Nimah: AppRootView destinations retain Try On/scan and connect Nimah session/import/saved-look signatures; AppRoute keeps all three tabs and both feature routes; Xcode source groups/build phases include both sets of files; localization merges keys; README/architecture document combined scope. Team onboarding is retained unchanged. These shared edits were explicitly approved by Nimah after reviewing the eight merge conflicts.

Two implementations coexist: Try On uses the existing Khalish/Hanum recommendation and MediaPipe eyeliner flow. Discover → Brow & Blush Studio uses Nimah's ARKit/Vision guide. They are separate screens, not one unified rendering pipeline; face-shape handoff into the studio remains a separate integration task. Native camera acceptance is pending.

Integration validation: simulator build succeeded; 196 tests executed, 192 passed, 4 skipped, 0 failed. Existing compiler warnings were not refactored in teammate modules. Live face/device accuracy has not been validated by these tests.

## Approved lifecycle optimization — -Nimah

After the preservation baseline above, Nimah explicitly approved lifecycle changes in four Hanum files: LinerOverlayModel.swift, MediaPipeEyeLandmarkProvider.swift, MakeupTryOnView.swift and MakeupTryOnViewModel.swift. These changes are marked -Nimah, leave eyeliner geometry/formulas intact, and are described in Performance.md. The other 39 teammate source files remain identical to the recorded baseline. TeamSourcePreservation.json remains the original merge baseline, not a claim that the four approved files are still identical.

## Current feature ownership — explicit tech-lead decision

-Nimah: This supersedes the earlier side-by-side merge scope and byte-for-byte baseline claims. User explicitly requested removal of Khalish eyebrow/blush implementations.

| Active feature | Owner | Entry |
| --- | --- | --- |
| Face-shape scan/classification/result | -Khalish | Try On → Face scan; onboarding |
| Eyebrow placement/preview/tutorial | -Nimah | Try On → Eyebrow; Discover studio |
| Blush placement/preview/tutorial | -Nimah | Try On → Blush; Discover studio |
| Eyeliner preview/eye-shape planning | -Hanum | Try On → Eyeliner |

Khalish eyebrow/blush catalogs, shape-blending personalizer, texture-drawing functions and MakeupFitter rules were removed. The old result-card blush tip was removed. The Hanum try-on rejects eyebrow/blush payloads, offers no category switch to them and creates no eyebrow/blush mesh layers. Its eyeliner geometry and eye-shape planner remain unchanged. Shared data types, palettes and eye/feature measurement helpers remain where needed for compatibility or eyeliner; they do not activate an alternate eyebrow/blush filter.

Nimah studio receives the Khalish result as FaceShapeAssessment(origin: .analysis). Triangle maps to Pear; unavailable source recommendations still permit manual exploration. This is a classifier estimate, not identity recognition. Independent eye/brow placement calibration remains required. Before/After and manual overrides are retained. Old catalog/import session routes now open the Nimah studio rather than the superseded mixed tutorial renderer, so they cannot activate the old eyeliner path. Reference images remain inspiration, not automatic makeup transfer.

Tests for deleted legacy brow/blush behavior were removed/replaced with owner-routing regressions. Simulator: 188 tests, 184 pass, 4 skip, 0 fail. Native face alignment remains unverified.

## Latest integration — -Nimah

Hanum source through 9c8aaf4 and Khalish eye-scan source through efdd168 merged. Scan-only EyeLandmarks renamed EyeScanLandmarks to avoid a same-module type and filename collision; no landmark math altered. Nimah integrates saved outputs into preset selection and removes the repeated scan gate. Optional hand model startup keeps the approved asynchronous lifecycle. See IntegrationContracts.md for input conversion and Validation.md for checks.
