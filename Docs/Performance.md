# Feature transition performance — -Nimah

User explicitly approved lifecycle/model-loading optimization in Hanum modules, preserving eyeliner geometry and formulas.

## Changes

- MediaPipe construction runs on the existing serial detector worker rather than MainActor. Leaving the screen cancels pending startup and invalidates its generation. Native detector release is also queued off the UI thread.
- A stale detector callback cannot restore an overlay or clear a newer in-flight frame. Timestamps remain monotonic across restarts.
- Camera permission completion cannot start a session after the user leaves. Backgrounding pauses the camera and model; foregrounding resumes through the guarded lifecycle. Pending texture work is cancelled on exit; completed layers remain cached.
- Nimah preview reuses immutable color buffers and triangle elements. Only current mesh positions are rebuilt per frame; intensity updates the material instead of reallocating all vertex colors. Placement and anatomy remain unchanged.

## Validation

Signed iPhone build succeeded. Simulator: 197 tests, 193 passed, 4 skipped, 0 failed. New regression verifies detector construction is off the main thread and render color/topology buffers are reused while vertices still follow mesh deformation. Existing eyeliner geometry/shape tests pass unchanged. No device FPS, transition latency, memory peak or thermal benchmark has been collected; smoother performance is not yet an on-device acceptance claim.

## Device testing

Use the same iPhone and lighting for before/after. Open Try On → eyeliner → back → Brow & Blush Studio → back, five times. Check delayed model startup does not activate an abandoned screen. Test quick back during startup, Before/After, background/foreground, and camera access denied/granted. Use Instruments Hangs/Time Profiler and Core Animation to measure main-thread stalls and frame pacing. Compare first-open vs later opens; an attached Debug build is not a release-performance benchmark.

## Scope

Geometry, makeup recommendation rules, detector thresholds and tracker smoothing are untouched. Full multi-session unification and persistent cross-screen model caching are not implemented in this patch. Model creation happens again when entering a fresh try-on screen, but off the UI thread; the camera view may appear before eyeliner is ready.
