# Blush AR rendering — 27 October 2026 · -Nimah

## Diagnosis

The prior implementation sampled an XY ellipse on a rectangular CPU grid, rebound points to triangle surfaces,
and interpolated vertex alpha. Even after the v0.2.1 expansion, this remained a generic ellipse, with no authored
pigment mask. It recreated geometry/position arrays each displayed frame. Its constant-color alpha overlay did
not evaluate camera skin luminance or pigment absorption. Nose/eye constraints were conservative XY cutoffs.
Disabling native mesh depth reads solved a reproduced self-occlusion bug, but did not solve physical visibility.
No actual hand/hair mask reached the blush material, and performance counters were absent. Repeated radius edits
could not address those limitations. Existing saved fitting and the six assignments were valid and are retained.

## Engine decision

**Primary implementation: ARKit face tracking + custom Metal camera/UV renderer.** No extra face tracker. The
existing Hanum face landmark path remains for eyeliner only; existing MediaPipe image segmentation is reused
for blush visibility, not face tracking. No new third-party SDK or telemetry is introduced.

| Candidate | Verified official capability | Dependency / unresolved control |
| --- | --- | --- |
| Banuba Face AR | iOS Face AR, makeup prefabs; blush supports RGB, coverage and matte/shimmer/cream_shine finishes | Needs client trial/production token and SDK package. Public prefab blush table does not expose per-cheek geometry coordinates. Custom assets/occlusion granularity and semantic-data licensing must be verified with supplied version before adoption. |
| BytePlus Effects | iOS SDK integration with effect/material packages; makeup; face-analysis APIs including 106/280 keypoints | Needs SDK archive/headers and matching bundle-ID license + materials for `com.sunrise.foundation`. Public integration pages are versioned and include OpenGL guidance, not proof of a current Metal package. Occlusion documentation for one platform is not treated as an iOS header contract. |
| ARKit + Metal | Native stable face topology/UV, current camera pose/expression, full shader/mask control | Available now. Face/hand/hair quality requires app-specific device validation; no commercial SDK quality or TikTok-equivalence claim. |

Banuba is the stronger documented commercial makeup candidate, but is **not integrated or emulated**. Its technical
specification lists lab-dependent 30 FPS examples, so a marketing peak FPS is not a device guarantee. BytePlus is
not assumed to be identical to TikTok's internal engine. We do not add fake APIs or license placeholders to builds.

Official sources checked on 2026-10-27:
- [Banuba Makeup Prefabs](https://docs.banuba.com/far-sdk/effects/prefabs/makeup/)
- [Banuba iOS samples / token requirement](https://github.com/Banuba/banuba-sdk-ios-samples)
- [Banuba technical specification](https://docs.banuba.com/far-sdk/tutorials/capabilities/technical_specification/)
- [BytePlus iOS integration](https://docs.byteplus.com/en/docs/effects/docs-ios-v4101-access-guide)
- [BytePlus license guide](https://docs.byteplus.com/en/docs/effects/docs-ios-license-guide)
- [BytePlus face detection](https://docs.byteplus.com/en/docs/effects/docs-portrait-sdk)
- [Apple native face UV](https://developer.apple.com/documentation/arkit/arfacegeometry/texturecoordinates-8ahq1)
- [Apple face geometry](https://developer.apple.com/documentation/arkit/arfaceanchor/geometry)
- [Google image segmentation](https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter)

## Implemented architecture

`LiveGuideView` still owns the single ARSession/lease and receives ARFrame. `BeautyBlushARView` adds a CAMetalLayer
for selected blush. It is hidden for other categories/Before. `BeautyBlushEngine` creates GPU pipelines off-main;
the shader source is bundled as `BeautyBlush.metal.txt` and compiled once by iOS's runtime Metal compiler. The
host's optional Xcode Metal Toolchain is absent; runtime compilation removes that build-machine dependency.
GPU test compiles the same source, creates the production pipelines, and tests real shader output.

The serial queue has one CPU frame job, a three-command GPU semaphore, and triple shared vertex buffers. It
imports camera Y/CbCr using CVMetalTextureCache, retains CV buffers until completion, handles YCbCr matrix/full
range/transfer metadata, and outputs to an sRGB render target. Camera background, projection and face mesh all
come from the **same ARFrame**. Both use ARFrame transforms directly, matching ARSCNView; no extra category-specific reflection is applied. A runtime scalar projection-error metric compares raw-to-view and projected coordinates (no positions
are recorded). Mirroring must still be accepted visually on device.

Native ARKit topology and UV are bound once per face/style. A GPU UV-atlas pass paints two independent cheek
channels by projecting observed rest mesh coordinates through the assigned recipe. The authored 1024-pixel
`blush-wash-mask.png` has an irregular rounded paint silhouette and continuous feather; it is not an ellipse
image. JSON ellipse coordinates remain a placement/support transform, not the pigment silhouette. Existing
radial power/smoothstep controls modulate the mask density and are actually consumed. No screen-positioned
face sticker is used. Existing native mesh holes and safe eye/nose/outer-face masks restrict the bake. Eye
clearance still uses the declared conservative center proxy, not a newly detected lower-lid contour.

Current face-local vertices deform the UV pigment with expressions. ARKit rigid head pose is not filtered a
second time. One Euro applies only to local vertex residuals (6 Hz minimum, velocity-sensitive cutoff). The
fragment shader measures current/rest surface-area Jacobian and fades pathological stretch. Pose beyond the
configured angle is gated. Loss/recovery has an exponential visibility envelope; stale masks fail closed.

A native current-mesh depth prepass and a matching pigment pass resolve visible surfaces. The old interpolated
patch no longer competes with another coarse depth surface. No winding assumption is required after mirroring.
The matte shader mixes luminance-normalized tint and absorption in linear light, preserving source detail and
lighting. It adds no skin smoothing, mesh morph, specular shine or face reshape. Coverage, pigment mix,
absorption, saturation, per-recipe maximum alpha and user intensity are distinct controls.

## Occlusion contract

`HandOcclusionSegmenter(faceSkinOnly: true)` uses the bundled Google multiclass selfie model. Class identities
come from `ImageSegmenter.labels`; exactly one face-skin label is required. Non-face categories (body-skin,
hair, clothes/background/others as supplied by that model) suppress pigment. This does **not** guarantee a
finger touching skin or a thin brush is correctly segmented. Raw-image orientation transforms are retained;
masks are not warped with the head (hands move independently). Results older than 150 ms are not used for
pigment. One inference at a time, up to 15 Hz, with model work off-main. No model download or second face tracker.
Actual model cost, hand/hair edge accuracy and thin-object coverage remain device measurements to perform.

## Performance / failure reporting

Target 60 rendered frames/s, dropping scheduled work to configured 30 at serious/critical thermal state. Styles
and UV atlas do not change with thermal policy. GPU resources/topology are reused; shade/intensity never rebake.
Local aggregated metrics every two seconds: completed/presented FPS, pigment-enabled frames, GPU mean time,
frame-age-to-GPU-completion p95, projection error, mask freshness, thermal state and errors. They contain no
image/mesh/landmark coordinates. GPU completion age is **not** an optical sensor-to-photon measurement.
No 60 FPS or sustained thermal result is asserted before reading these counters during real pigment rendering.
Setup errors are surfaced; a missing shader or invalid JSON cannot crash the app. Existing legacy renderer is a
fallback if the Metal engine cannot initialize, with an unavailable message, never described as Metal success.

## Device acceptance still required

At matching light/pose compare reference target vs actual: neutral, smile, yaw/pitch, fast motion, side-face
self-occlusion, hand/brush/hair, dim/bright transitions, several skin tones; repeat category switching, tutorial,
Before, palette cancel and reopen. Record projection error and visible-pigment frame counts with FPS; run at
least several minutes for thermal evidence. No single synthetic GPU fixture validates those real-world cases.

## Runtime configuration (all decoded and used)

| Parameter | Unit / allowed range | Default | Consumer |
| --- | --- | --- | --- |
| mask_asset | Bundle filename, currently `blush-wash-mask.png` | same | MTKTextureLoader / UV bake |
| atlas_size | UV pixels, 512 or 1024 | 1024 | Reused atlas texture |
| paint_feather | Normalized authored-mask density transition width, 0.2–1 | 0.90 | UV bake smoothstep |
| coverage | Pigment coverage ratio, 0–1 | 0.90 | Fragment alpha, separate from user intensity |
| absorption | Optical-density coefficient, 0–2 | 0.65 | Linear absorption term |
| saturation | Chroma mixing ratio, 0–1 | 0.85 | Luminance-preserving tint |
| pigment_mix | Absorption-to-tint ratio, 0–1 | 0.68 | Linear hybrid mix |
| min_cutoff_hz | Local mesh filter Hz, 2–30 | 6 | One Euro, never rigid camera pose |
| velocity_beta | Cutoff Hz per metre/second, 0–200 | 80 | Local vertex velocity response |
| visibility_tau_seconds | Seconds, 0.01–0.2 | 0.055 | Exponential tracking recovery |
| mask_max_age_seconds | Sensor timestamp age, seconds, 0.03–0.3 | 0.15 | Stale segmentation rejection |
| max_yaw_degrees | Legacy name: **combined face-normal angle**, degrees, 30–85 | 72 | Pose gate (also limits pitch) |
| stretch_fade | Four increasing current/rest area ratios, each >0 and ≤3 | 0.45, 0.70, 1.45, 1.85 | Jacobian fade-in/out |
| target_fps | Scheduled render cap, 30–60 | 60 | Backpressure scheduling |
| thermal_fps | Serious/critical thermal cap, 15–30 | 30 | Reduce workload without changing pigment placement |

Placement, radius, angle, eye/nose/face clearance, max_alpha, radial_power and falloff_smoothstep_mix remain in
the six existing JSON recipes; native UV bake consumes them. Color remains selected palette/custom sRGB and
intensity remains the user's per-category control. Compatibility metadata/source observations are not shader
parameters. Standalone JSON schemas validate structure; Swift additionally validates finite values, sorted
stretch thresholds, resource names and numerical bounds. Unknown renderer keys are rejected, not ignored.

The opt-in blush segmenter requests confidence masks using the actual bundled `MPPImageSegmenterResult` /
`MPPMask.float32Data` API, and copies non-face opacity before the callback releases its memory. Default Hanum
body-skin behavior is retained. The UV bake optionally identifies the native inner lower mesh boundary as a
mouth-opening bound and expands it to protect lips; absence is represented by a zero mask, not invented points.
Eyes/mouth openings still follow native geometry. This is not a verified semantic lip-segmentation model.

Occlusion and vertex textures have a three-frame resource ring guarded by a nonblocking GPU semaphore. New
camera frames drop instead of queueing when busy. Presentation counters are device-only (this Simulator SDK
omits drawable presentation callbacks). Reference comparison must distinguish completed from presented FPS.

## Physical device evidence

Physical iPhone 17 Release acceptance, 27 October 2026: user confirmed blush visible, attached during
still/smile/slow turns, and blended. User answered yes to hiding behind an obstruction; brush-specific
coverage was not independently confirmed. Latest approximately two-second runtime window: completed /
presented 59.98 FPS, mean GPU 1.33 ms, CPU frame arrival-to-GPU-completion p95 54.06 ms (not sensor-to-photon),
projection agreement 0.000037 pixels, segmentation age 101.67 ms, fresh mask, nominal thermal state, no shader
or engine error. Visibility 0.726; 77 pigment frames counted in that window. These are a snapshot, not a sustained
thermal benchmark or an accuracy guarantee. User's “ok” does not establish the requested two-minute duration
or tutorial/category regression completion. Multiple skin tones, lighting changes, fast/extreme poses and thin
brush/hair boundaries remain unverified. Bundled face-skin model initialization preflight also passed after
the full 327-test suite (`/tmp/sunrise-beauty-blush-model-preflight.log`).
