# Three reference blush looks v0.5.0 — -Nimah · 28 October 2026

## Supplied visual references

User screenshot 1 shows current blush concentrated near lower eyes. Still images establish placement/color,
not tracking latency. Screenshots 2–4 explicitly label Youthful, Sunkissed and Lifted; dashed boundaries are
tutorial annotations, not pigment shapes. Screenshots 5–9 show five color/finish inspirations, not five
independently established placements. No branded image or TikTok runtime is bundled in the app.

| Look | Interpreted reference | Personalization |
| --- | --- | --- |
| Youthful | Compact soft middle-cheek lobes, below the lower-eye area | Per-side width and midface spacing |
| Sunkissed | Horizontal cheek wash connected gently over upper nose bridge | Independent cheek lobes plus separate bridge field |
| Lifted | Longer outer-cheek sweep curving toward temple | Per-side corridor, authored 28° direction and curved mask |

Primary additional references (design guidance, not accuracy proof):
- TikTok face-mask texture/blending: https://effecthouse.tiktok.com/learn/guides/workspace/components/face-effects/face-mask
- TikTok makeup effects workflow: https://effecthouse.tiktok.com/learn/guides/getting-started/make-your-first-effect
- TikTok Japan custom makeup textures: https://note.com/tiktok/n/n07559379cc36
- Charlotte Tilbury apple vs upper-cheek draping: https://www.charlottetilbury.com/uk/secrets/summer-blush-looks
- Charlotte Tilbury application: https://www.charlottetilbury.com/au/secrets/how-to-apply-blush-for-a-gorgeous-glow
- YSL application/placement: https://www.yslbeauty.com.au/beauty-guides/makeup-guide/how-to-apply-blush.html

## Implementation

User explicitly requested three alternative placements, superseding the prior no-style-picker requirement
for blush only. Home initially maps its saved recommendation to a look, then remembers explicit look selection
in dandan.blush.look. Geometry always uses saved fitted facial anatomy; category still shows one makeup type.
TutorialHandoff carries blushStyle. Shade/intensity are independent; palette capture remains supported.

Three consumed JSON presets blush.look.youthful / sunkissed / lifted keep existing required geometry keys.
Youthful center -0.22 W below eye, radii 0.13 / 0.115 W; Sunkissed -0.19 W, 0.165 / 0.085 W; Lifted -0.16 W,
0.20 / 0.085 W at 28 degrees. Per-side v0.4 fitting then adapts these. No universal suitability is claimed.
New ratio parameter curvature=0/0/0.28, allowed0...0.6, warps field local y by curvature*(local x²-0.25).
Sunkissed bridge radius_x=0.145 W (0.05...0.2), radius_y=0.045 W (0.02...0.08),
vertical_offset=-0.19 W (-0.3...-0.12), strength=0.55 (0...0.8), relative to cheek max_alpha.
All decoded and consumed; invalid or missing required new-look parameters reject the database.
Bridge is upper-nose only, finite footprint, eye clearance and native mouth exclusion. Model segmentation
helps avoid nostrils/objects but is not perfect semantic nostril segmentation; verify on device.

Atlas adds a third pigment channel only for Sunkissed (brow still uses that channel for strand coverage in
its dedicated branch). Final blush uses max of channels, avoiding doubled opacity at overlapping lobes.
New look falloff: (1-r²)^power * exp(-0.8r²) inside the warped footprint, no repeated smoothstep plateau.
Legacy styles retain their existing authored-mask falloff. All cosmetic atlases now use mip pyramids and
trilinear/aniso sampling. Blush confidence opacity soft-threshold .12...65 reduces low-confidence noise
on clear skin; the brow branch and stale-mask 150 ms protection are retained.

The local filtered blush mesh residual is capped at 0.25 mm from current expression geometry; camera/head
pose uses the same current ARFrame without extra pose filtering. This bounds local surface lag, not full
sensor-to-display latency. It does not establish zero jitter or a pixel match with TikTok from screenshots.

## Palette references

Four existing swatches are preserved. Five additional encoded-sRGB design swatches are consumed by the
existing palette loader: Baby pink #EF9BBB, Cool pink #DA4C87, Berry #AF3E62, Soft nude #C98C83,
Terracotta #C57158. Nine total. Inspired by the supplied filter colors; not measured/verified product matches.
No face slimming, eye enlargement, whitening or broad skin blur added to imitate unrelated TikTok retouch.

## Validation

Full suite 337 executed, 4 hardware skips, no failures before brow-only preservation guard; actual GPU
new-look test uses production atlas shader, verifies bridge channel only in Sunkissed and visible cheek
coverage. Geometry distinguishes compact/lifted centers and curve; tests preserve category, shade/intensity,
tutorial handoff and cap local residual. Signed Release and device acceptance recorded in Validation.md.
Physical motion/occlusion/thermal and perceived fit remain pending for this revision.

## Mask-delivery flicker correction

The old path set shader alpha to zero and skipped the face draw whenever age exceeded150ms, bypassing its
existing smoother. Native head anchors now permit current-raw to mask-raw similarity reprojection. The
fresh limit remains150ms; new JSON mask_fade_seconds=0.10 (range0.03...0.15seconds) adds a finite fade window.
Only plausible reprojection permits use after fresh time. A cubic age weight and temporal recovery replace
binary gating, capped so opacity is exactly zero after250ms at current defaults. This is a deliberate bounded
stale-mask tradeoff: a newly introduced hand may be missed during the short fade, so physical occlusion QA is
required. No claim that smooth fading predicts previously unseen objects. No old-mask unlimited hold.

Recovery correction: opacity no longer bypasses temporal recovery via min(new mask weight, filtered).
The expiry ceiling stays1 through the first half of the grace interval then smoothly drops to0 at the same
250ms deadline. This prevents normal delivery-cadence jumps while respecting finite expiry. Twelve observed
synthetic jump failures were fixed in implementation without relaxing their threshold; full340-test suite passes.
