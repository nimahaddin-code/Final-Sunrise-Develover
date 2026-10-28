# Eyebrow native-UV strand renderer — 27 October 2026 · -Nimah

## Choice

Extend the installed ARKit + Metal engine, preserving one camera and one face tracker. Apple's native face
geometry follows expressions and supplies stable UV topology:
https://developer.apple.com/documentation/arkit/arfaceanchor/geometry
https://developer.apple.com/documentation/arkit/arfacegeometry/texturecoordinates-8ahq1
This is a concrete GPU implementation, not a claim of a newer ARKit release or TikTok equivalence.

## Supplied reference

Readable rows: oval standard -> natural; square crescent -> rounded; round European -> high arch;
heart willow -> low arch. Preserve current assignments matching those directions. Diamond stays soft arch
from the earlier complete reference. Bottom cropped labels cannot establish a new face-shape assignment;
rectangle/pear remain unsupported. These aesthetic labels are not anatomical classification facts.

## Implementation

BeautyBlushEngine is shared by the two categories. EyebrowGuideGenerator already fits observed scan points,
then consumes arch/head/tail/thickness parameters from makeup-reference.database.json. The new renderer packs
40 centerline segments per side with measured local XY, half thickness from the upper boundary and progress t.
Native face triangles rasterize these into a UV atlas. The dedicated browAtlasFragment creates an envelope,
head fade, tail taper and irregular deterministic directional strand coverage; it is not frame-random noise.
The brow branch of blushPigmentFragment shades pigment separately from blush, retaining source detail and
responding gently to luminance. It does not remove hairs, brighten/bleach natural dark brows, or reshape eyes.

Existing consumed JSON controls: max_alpha, head_fade_extent, edge_feather, half_thickness_design,
thickness_scale, head_taper, tail_taper, arch_t, arch_delta, tail_delta, max_displacement and cubic handles.
No disconnected JSON knobs. Strand spacing/direction are renderer constants, not user-specific measurements.
Both cheeks/brows use the same frame camera projection; no new horizontal flip. Native UV deformation,
local One Euro filter, stretch/pose gate, native depth and existing face-skin segmentation are reused.
Atlas cache includes category and brow style. Shade/intensity reuse atlas; category changes epoch-invalidate
old GPU visibility callbacks. Existing SceneKit makeup hides when Metal owns the selected category.

## Limits / QA

Procedural strands augment existing brows; they are not individual hairs detected by a model. Face-skin
segmentation may reject eyebrow hair or confuse hair/skin boundaries; this needs device QA, and cannot be
claimed to be specialized brow matting. Small half-width tails may reach the atlas sampling limit. No paid
SDK or new model added. No new scan. Verify device: natural/high arch, color extremes, intensity, smile,
turns, raised brows, hand/hair occlusion, category switching and tutorial/back. Do not merge to staging yet.

## Jitter response

After the user reported brow vibration, added a dedicated local residual stabilizer (min cutoff 2 Hz, beta
80 Hz per metre/second, 1 Hz derivative cutoff, 0.12 mm Euclidean output hold). Gaps above 150 ms reset rather
than interpolate old fitting. This never filters rigid ARKit head transform, so head-motion camera alignment
uses the current frame. Synthetic alternating 0.3 mm noise attenuation, real 3 mm step response and recovery
are tested. Brow-only atlas mip pyramid is generated after bake, sampled trilinearly with 4x anisotropy.
This targets local mesh jitter and high-frequency strand shimmer; source of perceived motion cannot be fully
proven without recorded device comparison. Device visual acceptance remains pending.

## Overlay only, anti-blink, debug views (27 October 2026, Khalish)

An erase-and-inpaint attempt (designed/observed brow region refilled by blending skin above and below) produced horizontal
bands and a visible soft rectangle and was removed, following eyebrow_filter_rendering_fix.md (Option B, overlay only).
The brow composites with straight alpha over the unchanged camera pixel; alpha is zero outside the baked brow. Strands keep
a .35 density floor between them. The atlas alpha channel now carries debug marks only (landmarks, observed centerline).
Blink causes addressed: the brow pass was skipped whenever the face-skin mask aged past 150 ms (device showed 223 ms) — brow
now holds the last mask up to 0.3 s; and the segmenter rejecting brow hair flickered occlusion on the brow itself — brow
pixels are occluded only when skin 9 mm above or below is too. Trade-off: a hand entering can lag up to 0.3 s on the brow.
Developer views (original, landmarks, fit contours, alpha mask, texture only, final) separate texture/alpha from placement.
