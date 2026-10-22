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
