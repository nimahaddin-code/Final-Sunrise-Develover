# 0017 — Skin-preserving blush compositing and the blush lab

29 October 2026 · `staging` · -Nimah, with Claude Code.

An earlier, uncommitted draft of this ADR described a MediaPipe blush renderer, five blend modes and a camera
hand-off manager. None of that code was ever committed on any branch or stash; only two orphan files
(`Features/BeautyBlush/Comparison/*.swift`, not in the Xcode project, calling APIs that do not exist) survived.
This version describes what is actually in the code.

## Diagnosis (blush looks detached from the skin)

Pipeline: `LiveGuideView` → `BeautyBlushEngine.submit` → `render`: the ARFrame's NV12 planes through
`CVMetalTextureCache` (no copy), the same frame's `ARFaceAnchor`, the native `ARFaceGeometry` mesh with its own
texture coordinates, a depth-only prepass, then `blushPigmentFragment` writing an opaque pixel to a
`bgra8Unorm_srgb` drawable. The pigment is **a UV atlas on the deforming native face mesh**, baked once per
anchor/style from `BlushPlacementGenerator`'s per-cheek fields. It is not a flat sticker or a plane. Surface
following was not the defect; style placement and silhouettes are intentional and unchanged.

Causes found in the code:

1. **Camera tone mismatch.** `decodeCamera` used the BT.709 OETF inverse when the buffer was tagged 709 (ARKit
   buffers are), and the drawable re-encoded with sRGB. A pixel without makeup did not round-trip: encoded 0.10 came
   out as 0.16, 0.50 as 0.55. Shadows lifted and the whole Metal picture was flatter than ARSCNView's. Now the
   decode is the exact inverse of the drawable's sRGB encoding, so untouched pixels pass through unchanged.
2. **Skin chroma replaced by flat shade colour.** The old blend set `tint = shade × (skin luminance / shade
   luminance)` per pixel and mixed most of the result towards it. Luminance was kept, but freckles, redness and
   local colour variation inside the blush were replaced by one uniform colour. That reads as paint on top of
   the skin.
3. **Per-channel clamp.** `clamp(target, 0, 1)` clipped bright skin channel by channel, shifting hue and
   flattening highlights to pink.
4. **Hard tutorial contour**: a band where 0.02 < mask < 0.045, with stair-stepped edges.

Not changed, but limits: the face-skin mask comes from a 256-pixel MediaPipe model at 15 Hz, upsampled about 7×
and carried by a similarity transform of three head anchors. It does not deform with expression, and
`smoothstep(.12, .65)` on its non-face confidence can make soft holes on the cheek. Measure this on a device
(Visibility diagnostic, red channel) before retuning.

## Decision: skin-preserving pigment (default)

`blushPigmentFragment`, blend 0:

- `base` = low-frequency skin: centre plus two rings (`detail_radius_px`, then half of it) in camera pixels.
- `target` = pigment over `base`: a Beer–Lambert absorbing layer (`absorption`) mixed with the shade's body at the
  base's luminance (`saturation`, `pigment_mix`). The meaning of each existing JSON field is kept.
- The pixel's own detail goes back on: its luminance ratio to `base` (pores, fine texture, highlights, cheek
  shading) and its chroma residual (freckles, redness).
- Gamut: out-of-range colours are pulled towards their own luminance (`intoGamut`); channels are never clamped
  one by one. Alpha mixes the camera pixel with that result, so alpha 0 is exactly the camera pixel.
- Strong local highlights (luminance ratio 1.15–1.6) take up to 60% less pigment, so the shine stays near white.
- Straight alpha, one opaque write per pixel: no second blend, no double alpha, no premultiplied edges.

Evidence (synthetic only, `MakeupPreferenceTests`): identity at intensity 0 for both transfer tags; luminance
detail 0.153 vs 0.153 without makeup; chroma detail 10.6 vs 11.0 without makeup (previous blend 6.75); mean
luminance within 0.75–1.05× of bare skin; highlight least tinted. `testBlushBlendContactSheet` renders bare
skin and every blend on the identical synthetic frame. Synthetic gradients and noise are **not** real skin
tones, lighting or pores. Device acceptance is still required.

## Blush lab (developer tools on, Blush selected)

`BlushDebugMenu` (ladybug, top left of the camera card) sets UserDefaults keys that the engine reads each frame,
only while developer tools are on:

- Blend on the same frame, mask and alpha: skin-preserving pigment (default), previous blend, linear alpha,
  multiply, soft light.
- Diagnostics: neutral geometry (cyan wash at mask strength, shade and intensity ignored), UV checker on the
  native ARKit UVs, pigment mask, mask boundaries (isolines at 0.03, 0.15 and 0.30), visibility (R occluded,
  G stretch fade, B tracking opacity), triangle wireframe (the native mesh as drawn this frame, without a depth test).

Not provided: landmark index labels. ARFaceGeometry has no named landmark indices; the brow's MediaPipe tracking
view shows indices for MediaPipe. There is also no frozen-frame capture yet.

## Technology roles

| Technology | Role now |
| --- | --- |
| ARKit Face Tracking / ARFaceGeometry | Only blush tracker. Native mesh, UVs, expression and same-frame pose; counts read from the API. |
| Core Video | NV12 planes via `CVMetalTextureCache`; retained until GPU completion. No per-frame image copies. |
| Metal | Atlas bake, depth prepass, skin-preserving compositing, lab blends and diagnostics. |
| MediaPipe Face Landmarker | Brow path, and the blush cheek fit (below): one tracker, on the same ARKit frames, `numFaces = 1`. Landmarks only shape the fit; pigment is drawn on the ARKit mesh. |
| MediaPipe image segmenter | Existing six-class selfie model, face-skin confidence, for occlusion only. No lips/eyes/brush classes. |
| Core ML / Vision | Vision fitting on the ARKit path. The only Core ML model is MI-GAN (brow inpainting), not a face parser. |
| Banuba, BytePlus | Not installed. No package, licence, token or adapter code. |

## Update: cheek fit from MediaPipe landmarks (same day)

After the first device check (blush small, not following the face), the user chose: MediaPipe landmarks for shape,
ARKit mesh for drawing; a TikTok-wide wash for all three looks; thin natural strength; a fit measured once from about 10
frames; and the ARKit-only fit as the fallback.

- While blush is selected and the look has no fit for the current anchor, frames go to MediaPipe at up to 15 per second
  (`submitBlushLandmarks`). Each answer's 17 cheek landmarks are lifted onto the same frame's ARKit mesh by ray casting
  (`BrowFaceFrame.faceLocal`), in face-local metres. Only frontal answers count. MediaPipe's normalized depth is never used.
- The median of 10 samples becomes `BlushCheekLandmarks` for that anchor; the atlas is re-baked once. A new anchor starts over.
- `landmarkField`: nasal limit at the nostril wing, outer limit at the face edge minus `face_edge_margin`, eye limit below
  the lower lid (`landmark_eye_clearance`), center and radii from `landmark_center_*` / `landmark_radius_*` as fractions
  of that corridor, `landmark_edge_feather` across. Angle and curvature keep each look's identity (Lifted 28°, curved).
  The profile is flat-topped with zero slope at its rim; tests require at most 10% of the peak per millimetre.
- Rejected fits (corridor under 2.5 cm or over 12 cm, sides not on opposite sides of the nose) fall back per side.

Open: the jump from the fallback to the fitted wash is not crossfaded; lifting uses the mesh at that frame, so a fit taken
mid-smile shifts slightly (frontal gating does not check expression); MediaPipe keeps running while blush has no fit
(for example, no face in view).

## Not done, and what it needs

- **Pure MediaPipe renderer** (pigment on Google's canonical mesh instead of ARKit's): not built; the user chose the
  ARKit mesh for drawing. It would need its own topology/UVs (untracked `Resources/mediapipe-canonical-face.json`).
- **Banuba Face AR SDK**: the iOS package, a client token covering the makeup features, and effect assets that can
  carry this app's per-cheek silhouettes. **BytePlus Effects SDK**: the iOS SDK, its model/material bundles, and a
  licence issued for this bundle ID that covers TestFlight and App Store. Vendor API details were not re-checked in
  this pass; verify them against the supplied package. Each would be a separate, exclusive renderer, never chained.
- **Face parser** (lips/eyes/brows/hair as separate classes): a licensed Core ML model with known classes,
  preprocessing and output alignment, measured on device.
- **Device evidence**: neutral, smiling and turned faces, several skin tones, daylight and low light, intensity
  extremes, hands and brushes, two-minute thermal runs. 60 FPS is a target, not a measurement.
