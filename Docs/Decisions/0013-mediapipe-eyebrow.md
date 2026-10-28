# Eyebrow tracking on MediaPipe — 27 October 2026 · Khalish

## Choice

The eyebrow try-on no longer uses the ARKit face mesh or the Vision brow fit. MediaPipe Face Landmarker
(the bundled `face_landmarker.task`, live-stream mode, `outputFacialTransformationMatrixes`) runs on the shared
ARKit camera frames and supplies, per frame: both brow contours (upper and lower rows, 5 points each, the index
rows already verified by the eyeliner spike), eye corners, iris centres, alar points, the nose bridge and the
head pose. ARKit stays only as the camera (and for blush, which still follows the ARKit mesh). No new dependency,
no second camera session, nothing persisted.

Why: MediaPipe gives dense, per-frame brow points from the same image the user sees, with no one-off Vision fit
and no barycentric re-attachment to a mesh that is coarse around the brows. It is the approach the eyeliner
already uses, and it is the same family of technique as TikTok/Effect House brow effects (landmarks + face
mesh + texture), without their brow eraser.

## Pipeline

1. `BeautyBlushEngine.submitBrow` hands one ARFrame at a time to `MediaPipeBrowTracker` (frames are dropped
   while one is in flight). The detector's rotation and landmark space come from the frame's display transform,
   not from an ARKit face anchor.
2. On the result, `renderBrow` draws that same frame with its landmarks, so pigment and camera never drift apart.
   Display rate is the landmark rate; latency is one inference.
3. `BrowObservationSmoother`: the nose bridge gets a quick One Euro filter (head motion), each point's offset
   from it, in eye spans, a steadier one (brow shape). A gap over 0.25 s restarts it.
4. `BrowGeometry` builds a brow-local frame per side: a cubic Hermite centerline through the contour midpoints
   (u = 0 head, 1 tail), with the across axis pointing to the upper contour. Across distances use the longer
   brow's width, so a turned head does not thin the far brow; a brow under 35–60 % of the other's width fades.
5. Head pose (`BrowHeadPose`, from the transformation matrix) gates the brow beyond `max_yaw_degrees`.
6. `BrowDesign` turns the selected style's rule fields (arch_t, arch_delta, tail_delta, max_displacement,
   half_thickness_design, thickness_scale, head/tail taper, head_fade_extent, edge_feather, max_alpha, cubic
   handles) into a brow-space curve. `max_displacement` is in metres on the ARKit mesh; it is converted with a
   nominal 5 cm brow width because MediaPipe landmarks have no metric scale.
7. The style is baked once into a 1024×512 mipmapped brow-space texture (`browTextureFragment`: coverage,
   deterministic strands, design outline). A 48×10 strip per brow (`browStripFragment`) samples it every frame.
8. Composite stays overlay only (`mix(camera, hair, alpha)`), with the existing face-skin mask for hand/fringe
   occlusion (brow hair rejected by the segmenter only counts when skin above or below is covered too).
9. Original brow pixels are segmented in the shader (inside the observed contour and darker than forehead skin
   sampled above it). It is shown in the "Original brow mask" debug view and not used to erase anything.
10. Tutorial guide: the design outline from the texture, plus nose–eye mapping lines (ala through inner corner,
    iris and outer corner to the brow) drawn by `browMarkFragment`. The SceneKit mesh guide is only the fallback
    when Metal is unavailable.

## Limits / QA

Not checked on a device: landmark latency, display rate, stability and whether the landmark space choice and
mirroring are right on a Face ID iPhone all need QA. The 5 cm nominal width only bounds style displacement.
MediaPipe's brow rows are sparse (5 per edge), so very thin or unusual brows follow a smoothed centerline.
The brow is drawn one inference behind the live ARSCNView camera underneath it.

## Hiding the natural brow (test toggle, 28 October 2026)

Compared with TikTok's eraser, which keeps skin texture and faint strands, a flat blurred fill read as a smudge and
two-point sampling left a darker band. Now: low frequency from a skin reference pass (32 samples per brow above and
below, brightness-weighted 13-tap discs, EMA τ≈0.15 s, forehead-weighted), detail = pixel / 13-tap camera blur
(~0.05 brow widths) with dark detail ×0.4 and light ×0.7, clamped 0.85–1.12. Area: core/end above from the observed
half thickness; below bounded to 55% of the distance to the upper-eyelid row (MediaPipe lid indices). A learned
inpainting model or UV-space push-pull fill would go further; neither is added. Device acceptance pending.

Revision after device feedback (same day): the eyelid bound left a ~1.5 mm fade, a visible line, and an 85%
forehead fill stepped against darker brow-bone skin. Now the lower end is ≤70% of the eyelid distance with the core at
≤45% of it, fades use smootherstep, the reference is sampled at the area's top/bottom edges and blended between them
(pow 1.4 towards the forehead), and dark detail is ×0.2, light ×0.6, clamped 0.93–1.08.

Second revision: the fill was brighter than the skin (sampler favoured the brightest taps; asymmetric detail kept
light gaps between hairs) and the head/tail samples landed on the nose bridge and background, giving bright slabs with
hard ends. Now: samples just outside the brow rows, u clamped to 0.08–0.92, two-step mean-shift average, 20% of the
camera's blurred low frequency kept, detail ±25% clamped 0.95–1.05, head fade -0.10…0.08 and tail 0.92…1.10.
