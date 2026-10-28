# Personal cheek placement v0.4.0 — -Nimah · 27 October 2026

## Behavior

Face shape still chooses the authored blush character. It no longer fixes final center/radii solely through
full-face width. Each side independently measures the outer cheek in a horizontal band near the intended
placement, excludes posterior surface points relative to the eye, uses a robust 95th percentile outward edge,
and derives its usable nose-to-contour corridor. Horizontal center/radius scale within bounded calibration.
Vertical spacing uses the observed mouth-opening upper bound where native topology provides it; otherwise it
uses the measured nose ala. If both unavailable, measured interocular width supplies an explicit fallback.
No guessed zygomatic bone, lower eyelid contour or aesthetic-optimality classifier is claimed.

The current reference angle, color, irregular pigment mask, wide-wash gradient and matte blend remain intact.
The two sides need not have equal radii. All geometry is face-local, baked once into the native UV atlas per
anchor/style; live mesh deforms that atlas. Tutorial uses the same adaptive fields. No second camera/tracker,
no new scan, no change to face/eye classifier, eyebrow upgrade or Hanum eyeliner formulas.

## Consumed JSON

Under runtime_fitting_rules.parameters, all units ratio:

| Key | Default | Range | Use |
| --- | --- | --- | --- |
| blush_personalization_strength | 0.85 | 0–1 | Mix identity with anatomical scale |
| blush_personal_scale_min | 0.8 | 0.6–1 | Lower ratio clamp before mixing |
| blush_personal_scale_max | 1.25 | 1–1.5 | Upper ratio clamp before mixing |
| blush_contour_band | 0.035 | 0.015–0.1 | Cheek sampling half-band/full face width |
| blush_nominal_interocular_ratio | 0.4 | 0.25–0.55 | Reference eye spacing/full width for fallback |
| blush_mouth_clearance | 0.025 | 0.01–0.08 | Center clearance above observed mouth bound/full width |

Parameters are finite/range/unit-validated. Old databases missing these keys retain documented defaults.
Other preset geometry stays consumed as the base artistic recipe. Mouth bounds are observed topology bounds,
not semantic lip segmentation. Eye exclusion remains conservative eye-center clearance. Wide masks can still
be clipped by safety boundaries. These constants require multi-face calibration; they are engineering
initial values, not evidence-based universal makeup proportions. Uncertain or unusable corridors fail closed.

## Validation

Synthetic same-style/different-cheek test verifies narrower right cheek changes right center/radius while
left remains unchanged. Same-style/different measured nose-to-eye spacing changes vertical radius. Invalid
personalization configuration is rejected. Full suite and signed Release evidence tracked in Validation.md.
Physical two-user comparison, color/coverage satisfaction, smiling, head turns and prolonged FPS remain pending.

Effect House sample was used as an architectural reference only. No TikTok source/assets/runtime imported.
