# 0018: Eyeliner follows a stretched eye corner; controls use native Liquid Glass

Date: 2026-10-31. Status: accepted, device check pending.

## Context

1. A user who pulls the outer corner of the eye sideways to draw a wing had a liner that lagged or snapped back.
   MediaPipe's face prior does not follow stretched skin, so only `LidFollower` (Lucas-Kanade skin tracking) saw the pull,
   and only while the hand mask (15 Hz) reported a hand near the eye. Measured on a synthetic benchmark
   (`LinerStretchTests`, detector fixed at rest, skin pulled 0.4 eye widths): with a hand the liner kept about half of the
   pull (the 2% per result pull-back toward the detector undid a held stretch within a second or two); without a hand it
   did not follow at all (error 0.41 eye widths).
2. The restyled Try On screen used an image asset per button (`trailing`, `circle-liquidglass`, `button-circle-*`).
   The deployment target is iOS 26.6, so the native glass API is available.

## Decision

Eyeliner (`Eyeliner/LidFlow.swift`, `LinerOverlayModel.swift`):

- The follower measures the skin's own motion in every camera frame (`skinSpeed` 0.012 eye widths per frame for
  `skinFrames` = 3 frames in a row). That starts a pull without the hand mask. A blink clears it.
- A pull is held (hysteresis) for `stretchLinger` = 0.5 s after the skin last moved fast and until the followed points and
  the detector agree again (gap under `stretchRelease` = 0.04 eye widths): releasing the lid returns to the detector.
- While a pull is held the detector pull-back is `stretchPullPerResult` = 0.002 (was 0.02), so a held stretch stays.
- While the skin is sliding but not yet confirmed, the old points keep riding it (the start of the pull is not lost).
- `LidFollower.refresh` carries the newest result to every camera frame (head motion and the followed lid), and
  `LinerOverlayModel.refollow` draws it again, so the liner moves at 60 Hz, not at the detector's 30 Hz. Results and
  refreshes share one monotonic clock (`stamp`) for the One Euro filters.
- The tracker uses `OneEuroConfig.responsive` while a hand is near or a pull is held.
- Rejected after measuring the code: raising `wingElevationLimit`, `extensionSlopeLimit` or `wingAnchorReach`. The wing's
  pull is added to the tip after the elevation clamp, so a stretch is not clipped (`testWingTipFollowsAStretchedAnchor...`).
- Tutorial and Try On share `LinerOverlayModel`, so the guide dots follow the same followed points.

UI (`DesignSystem/Components/GlassKit.swift`):

- `glassCircle` / `glassCapsule`, `GlassCircleButton`, `GlassChoiceCircle`, `GlassPickerRow` (one
  `GlassEffectContainer`) are built on `glassEffect`. The tool strip slides one selected capsule with `glassEffectID`.
  The intensity thumb and track, toggles, tutorial back/next, photo controls, camera bar and light button use the same
  kit. Tints are `AppColors.glassBase` and `AppColors.glassSelected`.
- Removed assets: `trailing`, `circle-liquidglass`, `button-circle-selected`, `button-circle-unselect`
  (`trailingButtonBackground` is gone). `main-bg` and the logos stay.
- Spec captions (`captionFill`, wine step pills) stay solid: they are not controls.

## Consequences

- Constants are guesses from a synthetic benchmark, not tuned on a face: check on a device (see
  `Docs/Plans/2026-10-31-liner-stretch-and-native-glass.md`, section D).
- Glass legibility over a bright camera picture needs a device check (Reduce Transparency, Increase Contrast).
- `refollow` and the glass screens need ARKit frames or a camera; only the follower and the geometry are unit tested.
