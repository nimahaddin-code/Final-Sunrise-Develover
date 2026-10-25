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

## Try-on stalls and feature switches — -Nimah

The home subscribed to saved scan publishers and could apply the same analysis again on SwiftUI updates.
The model now ignores identical face/eye/fit values before publishing anything. Replayed data cannot turn a tool
back on after the user switched it off. Hidden guides previously still built/updated sphere/capsule nodes;
they now return before doing that work in pigment-only try-on.

Pigment colour was part of the binding key, so each swatch/slider interaction could rebuild a grid of skin
attachments, scanning the full triangle list for each point. Tint now lives in the material: the existing
attachments, alpha source and triangle element are reused. Initial binding looks up only nearby triangles
through a 6 mm XY grid and still uses the original barycentric/depth rules. Live updates use one position array.
The common attachment lookup no longer allocates a temporary index array for every vertex.

The eyeliner relay drops excess frames above 30 Hz and keeps at most one main-thread delivery pending;
ARKit camera tracking is unchanged. Brow/blush changes no longer synchronize unchanged liner settings.
No Hanum/Khalish placement formulas were changed.

Validation: **270 simulator tests / 266 passed / 4 skipped / 0 failures**; signed **Release iPhone build succeeded**.
Regression checks include 30 colour updates with one binding build, preserved positions/topology/alpha sources,
zero home publications for repeated scan data, no hidden guide node construction, 30 overlay deliveries from
120 timestamp inputs, clock reset recovery, and actual SceneKit coloured-pixel rendering.

No real-device FPS, thermal or transition-time measurements were collected. Test Release without the debugger:
complete initial scan, toggle all tools, drag intensity, change colours repeatedly, open/close tutorial and palette,
then run try-on for several minutes. Use Instruments Time Profiler / Animation Hitches if any freeze remains.
Debug uses unoptimized Swift and is not the performance acceptance build. Existing unrelated Xcode project/string
catalog edits were left outside the performance commit.
