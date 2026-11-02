# Plan 2026-10-31: eyeliner stretch responsiveness + native Liquid Glass UI

Two goals before device testing:

1. **Eyeliner**: the Try On filter and the guide line must keep up with a user who stretches the outer corner of the eye
   (pulls the lid sideways/up) to draw the wing.
2. **UI**: continue yesterday's restyle (semi-similar to the design), but build every button and control with the
   native iOS 26 Liquid Glass API (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) instead of supplying
   an image asset per button.

Facts found while preparing this plan (read from the repo, not assumed):

- Deployment target is iOS 26.6, so the glass API needs no availability fallback.
- Eyeliner pipeline: `LinerOverlayModel.submit` (every ARKit frame) -> MediaPipe landmarks throttled to 30 Hz
  (`landmarkThrottle`), hand mask throttled to 15 Hz (`occlusionThrottle`) -> `LidFollower` (Lucas-Kanade skin tracking
  of upper-lid points and outer corner, only while a hand is within `handNear` = 0.04 of the eye, kept for
  `handLinger` = 0.3 s) -> `LinerTracker.render` (One Euro smoothing, `.responsive` while stretching) -> `LinerPathBuilder`
  and `LinerGuide` (wing limited by `wingElevationLimit` = 24 deg, `extensionSlopeLimit` = 1.2, `wingAnchorReach` = 1.0
  eye width) -> `LinerOverlayRenderer`.
- Likely weak points for a stretched eye (hypotheses to confirm with measurements in Phase 1, not conclusions):
  stretch mode depends entirely on the hand mask (15 Hz, may miss a thin finger or a hand at the temple); the follower is
  consulted only when a detector result arrives (about 30 Hz) so the drawn liner can lag the skin between results;
  `pullPerResult` = 0.02 and `maximumGap` = 0.9 may fight a large real pull; wing limits may clip the guide when the
  corner is pulled far.
- Custom visuals to replace: `GlassChoiceCircle`, `GlassPickerRow`, `trailingButtonBackground` (asset `trailing`),
  `MainBackground` (asset `main-bg`), `CameraBarButton`, the tool strip, `IntensityBar`, the toggles and the Material
  backgrounds in the tutorial and photo screens. Unused after the change: assets `circle-liquidglass`,
  `button-circle-selected`, `button-circle-unselect`, `trailing`.
- `xcrun simctl` currently fails ("not a developer tool"): `xcode-select` points to Command Line Tools. This needs
  the user's sudo password (see Gates).

---

## Working agreement (applies to every phase)

- Work autonomously. Stop and ask only at the **Gates** below.
- Do not commit unless the user says "commit". Never push, never touch `main`/`staging`.
- Follow AGENTS.md: new files go in the matching Xcode group and target in `project.pbxproj`; no hard-coded colors or
  spacing (use `AppColors`/`AppSpacing`/`AppTypography`); user strings in `Localizable.xcstrings`; strict concurrency;
  MediaPipe imported only in the existing wrapper files; no networking, no persisted camera frames.
- Eyeliner math changes are test-first: write the failing test, see it fail, then change code.
- Keep task list current. Log every build/test run to `/tmp/sunrise-<phase>-<n>.log` and quote the real result;
  never claim "works" from a Simulator run for anything camera-related.
- Debug loop (systematic, no guessing): reproduce -> read the first error -> one hypothesis -> smallest change ->
  rerun. Max 3 attempts per failure on one hypothesis family; then write down what was tried, revert the
  experiment, and ask the user (or park the item as "not done" in the final report).
- At the end update AGENTS.md (new dated section at the top), `CHANGELOG.md`, and add an ADR if the design changes
  (`Docs/Decisions/0018-...`).

## Gates (the only planned interruptions)

| # | When | Needs from user |
|---|------|-----------------|
| G1 | Phase 0 | Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (password) if `simctl` is still missing. Without it: no Simulator screenshots, only build/tests via `xcodebuild` if Xcode is usable. |
| G2 | Phase 2 start | The design: Figma file/frame link (the Figma plugin needs `/mcp` authorization) or screenshots of Try On, picker rows, tutorial, photo and result screens. Without it, keep yesterday's layout and `AppColors` as the design. |
| G3 | Phase 1 end | Physical iPhone: install the signed Release build ("Nimah New") and report the stretch checklist results (Section QA-D). I cannot do this. |
| G4 | Phase 2 | Decide `main-bg` and logo assets: keep (default) or replace the background with a native gradient/mesh. Only asks if the design differs. |
| G5 | Any time | Permission prompts (file deletes outside the plan, network, device access). |

---

## Phase 0: baseline (about 20 min)

1. `git status`, `git diff --stat`: record the starting state. Resolve the half-staged asset rename
   (`butoon- circle-unselect` deleted / `button-circle-unselect` untracked) without losing the new files; do not commit.
2. Check tooling: `xcodebuild -version`, `xcrun simctl list devices available`. If it fails -> G1.
3. Build + run the full unit tests on an iPhone Simulator; save to `/tmp/sunrise-baseline.log`. Record test count,
   failures, skipped. Any failure that exists before my changes is listed as pre-existing and not "fixed" silently.
4. Read `Docs/EyelinerDeviceTesting.md`, `Docs/Performance.md`, `LidFlowTests`, `LinerGeometryTests`,
   `EyelinerGeometryTests` so new tests match their style.

Exit: baseline numbers written in the final report; build green or failures documented.

---

## Phase 1: eyeliner stretch responsiveness (about 3 to 4 h)

### 1.1 Make it measurable first
- Add an English-only, DEBUG/developer-tools readout (extend `debugStatus` / `EyeDebugView`) with: landmark rate (Hz),
  detector latency (ms), camera-frame-to-published-frame latency (ms), follower state (following count, stretch mode on
  or off and why), liner-vs-skin gap in eye widths when tracking.
- Add a small pure-Swift **stretch simulator** in the tests: generates a synthetic textured luma image plus eye
  landmarks, then moves the outer corner and upper lid outward/upward by 0.1 to 0.6 eye widths over 5 to 30 frames, with
  detector results at 30 Hz and a detector delay of 60 ms. It is the replayable benchmark (no camera needed).
- Run the benchmark on the unchanged code and store the numbers (max liner-to-truth error in eye widths, lag in
  frames, frames where the wing leaves the lid). This is the baseline to beat.

### 1.2 Change set (apply in this order; run the benchmark and the old tests after each)
1. **Per-frame follower output.** Today `fuse` runs per detector result. Apply the follower's latest tracked
   points on every ARKit frame inside `publish` (head-fixed frame, so it is cheap) so the liner is not stuck at 30 Hz
   steps. Keep detector pull-back (`pullPerResult`) and blink/disagree fallbacks.
2. **Stretch detection that does not need the hand mask alone.** Add a geometric trigger: outer corner (and upper
   lid points) displaced from their head-frame rest position by more than a threshold in eye widths, or eye width/aspect
   changing faster than a threshold, turns stretch mode on; the hand mask stays as a second trigger. Hysteresis and
   linger so it does not flicker. Constants named, documented, and covered by tests.
3. **Raise the ceilings that clip a real pull.** Re-evaluate `maximumGap` (0.9), `wingAnchorReach` (1.0),
   `wingElevationLimit` (24 deg), `extensionSlopeLimit` (1.2) against the simulator; widen only as far as the tests
   justify, with the limit relaxed only while stretch mode is on so the rest-state look is unchanged.
4. **Smoother that does not lag a deliberate pull.** In stretch mode use `.responsive`, plus allow the One Euro
   `beta` to rise with speed of the outer corner; add a short-horizon constant-velocity prediction (<= 1 detector
   interval) for the outer corner and wing tip, cancelled on blink/stop so it never overshoots at rest.
5. **Rate.** Check whether `landmarkThrottle` (1/30) and `occlusionThrottle` (1/15) are the bottleneck using the new
   readout; raise the hand-mask rate only while a hand is near an eye, and only if the thermal state is nominal or fair.
6. **Guide line (tutorial and Try On).** Make `LinerStepGuide` / `LinerGuide` build from the fused (followed)
   landmarks so the dotted guide and the wing dots stay on the stretched corner; same limits as item 3.
7. **Failure behavior.** If tracking is lost mid-pull (blur, no face, hand covers the eye) the liner fades and
   re-seeds from the detector instead of jumping; reuse the existing turn-away hide logic style.

### 1.3 Exit criteria for Phase 1 (measured on the simulator benchmark)
Proposed targets (adjust only with a written reason): liner-to-truth error <= 0.08 eye widths during a 0.4-eye-width
stretch at 0.3 s duration; lag <= 2 camera frames; zero frames where the wing detaches from the lid; rest-state output
byte-identical to baseline (no stretch -> same geometry). All previous liner tests pass.
Then build the signed Release for the device and hand over -> **G3**. Phase 2 continues in parallel while the user
tests.

---

## Phase 2: native Liquid Glass UI (about 4 to 5 h)

### 2.1 Foundation
- Get the design (G2). Write a one-page mapping: screen -> components -> glass role (control, chip, bar, background).
- Create `DesignSystem/Components/GlassKit.swift` (+ project registration):
  - `GlassCircleButton` (icon, size, selected, tint) using `.glassEffect(.regular.tint(...).interactive(), in: .circle)`.
  - `GlassPill` / `GlassCapsuleButton` for labels and toggles.
  - `GlassChoiceCircle` re-implemented on the same primitives (selected = larger, tinted, ringed) so existing call
    sites keep compiling; `GlassPickerRow` wrapped in `GlassEffectContainer(spacing:)` and the selected item uses
    `glassEffectID` + `@Namespace` for the morph.
  - `GlassBar` for the tool strip and the tutorial bottom bar.
  - Every control: minimum 44 pt target, accessibility label/traits, `.sensoryFeedback`, Reduce Transparency / Reduce
    Motion / Increase Contrast respected (check that text over camera stays readable).
- Tokens: add any missing colors to `AppColors` (no loose RGB literals in views).

### 2.2 Migration, one screen at a time (build + screenshot after each)
1. Try On: tool strip, trailing "next/tutorial" button (replaces `trailingButtonBackground`), look pickers
   (`LinerLookPicker`, `BrowOverlayPicker`, blush row), shade row, palette button, intensity bar, test toggles.
2. Palette sheet (`PaletteColorPicker`): trailing button, close/confirm buttons.
3. Tutorial (`GuidedTutorialView`): back button, bottom bar (`CameraBarButton` -> glass), step caption stays the
   spec's `captionFill` pill (spec 1.1 colors are fixed, not glass), Next/Done capsule.
4. Photo and result (`PhotoCaptureViews`): shutter, theme button, polaroid check/close.
5. Camera guidance caption + zoom chip (`CameraGuidanceCaption`, `ScreenLightButton`).
6. Background: keep `MainBackground` unless G4 says otherwise.
- Do not nest glass in glass; group neighbors in one `GlassEffectContainer`; do not put glass on large areas.

### 2.3 Clean-up
- Delete code paths and assets that nothing references (`trailingButtonBackground`, `trailing`, `circle-liquidglass`,
  `button-circle-selected`, `button-circle-unselect`) after `grep` proves zero references (confirm the deletions list
  with the user only if an asset is referenced elsewhere).
- Update `Localizable.xcstrings` for new accessibility labels (English source).

### 2.4 Make the UI testable without a camera
- DEBUG-only launch argument `-UIFixture` that shows Try On/tutorial with a bundled still image behind the controls
  instead of the unavailable camera, so Simulator screenshots show the real glass over real content. Not shipped in
  Release (`#if DEBUG`).

---

## Phase 3: integration and final QA (about 1 h)

- Full unit test run, Release build (signing as before), warnings review (no new warnings from my files).
- Run the QA matrix below, fix, rerun.
- Update AGENTS.md, CHANGELOG, ADR 0018; list what is verified (Simulator) vs. not (device).
- Final report: what changed per file, test counts before/after, what is not verified, what the user must check.

---

## QA

### A. Unit tests to add (names are proposals)

Eyeliner (`LidFlowTests`, `LinerGeometryTests`, new `LinerStretchTests`):
| ID | Test | Expectation |
|----|------|-------------|
| L1 | `testRestStateGeometryUnchangedByStretchChanges` | with no motion, guide/outlines equal the baseline snapshot |
| L2 | `testOuterCornerPullOutwardIsFollowedWithinTolerance` | 0.4 eye-width pull over 12 frames: error <= 0.08 eye widths at every frame after frame 3 |
| L3 | `testUpwardLidPullFollowedWithoutHand` | geometric trigger turns stretch mode on with the hand mask absent |
| L4 | `testStretchModeHysteresisDoesNotFlicker` | noisy displacement around the threshold toggles mode at most once |
| L5 | `testFollowerAppliedEveryFrameBetweenDetectorResults` | published points move on frames with no detector result |
| L6 | `testLargePullBeyondOldMaximumGapStillFollowed` | 0.6 eye-width pull is followed, not snapped back to the detector |
| L7 | `testDetectorWinsDuringBlink` | existing behavior preserved with the new per-frame path |
| L8 | `testTrackingLostFadesAndReseedsWithoutJump` | no frame-to-frame jump above a set distance |
| L9 | `testPredictionDoesNotOvershootWhenPullStops` | overshoot <= 0.02 eye widths, settles within 3 frames |
| L10 | `testWingStaysOnLidWhenCornerPulledHard` | wing root within lash-line tolerance; no polygon self-intersection; winding unchanged |
| L11 | `testGuideFollowsFusedLandmarks` | tutorial guide dots track the stretched corner |
| L12 | `testWideLimitsOnlyAppliedInStretchMode` | rest-state wing elevation still clamped at 24 deg |
| L13 | `testTurnAwayStillHidesLiner` | existing 32/25 deg behavior preserved |
| L14 | `testBenchmarkLatencyBudget` | simulated frame-to-draw lag <= 2 frames |

UI (`SunriseAppTests`, plus Simulator checks):
| ID | Check | Expectation |
|----|-------|-------------|
| U1 | GlassKit components build and render (ImageRenderer smoke test) | non-empty image, correct size >= 44 pt hit target |
| U2 | `GlassChoiceCircle` selected vs unselected | selected frame larger; accessibility trait `.isSelected` present |
| U3 | No remaining references to removed assets | `grep` finds none; app builds |
| U4 | Localization | every new label is in `Localizable.xcstrings` |

### B. Simulator visual matrix (screenshots saved to the scratchpad, referenced in the report)
Screens: Try On (each of eyebrow/blush/eyeliner), palette sheet, tutorial (each tab, first and last step), photo,
result. Variants: iPhone small (SE-size) and Pro Max; light and dark; Dynamic Type default and largest accessibility
size; Reduce Transparency on; Increase Contrast on; Reduce Motion on. Pass = no clipped text, no overlap with the camera
caption, controls >= 44 pt, glass readable over the fixture image, no layout jump when the selected item changes.

### C. Regression
Full `xcodebuild test`; compare against Phase 0 baseline. Brow and blush render tests must be untouched (they load the
shader library; a shader compile failure fails every engine test).

### D. Device checklist for the user (G3), eyeliner stretch
1. Fair light, face straight, liner "Arabian" and "Foxy": pull the outer corner outward with a finger slowly, then fast:
   the wing stays on the lid, lag not visible.
2. Pull up and out (typical wing pose), hold 3 s, release: liner returns without jumping or overshoot.
3. Pull with the hand covering part of the eye / thin finger / thumb: liner still follows.
4. Pull then blink: liner follows the blink, no ghost line.
5. Turn the head past about 30 deg while stretched: liner hides, returns when straight.
6. Tutorial eyeliner steps 2 and 3 while stretching: guide dots stay on the corner.
7. Note the debug readout: landmark Hz, latency, stretch mode on/off; send a screenshot if anything feels late.
8. Thermal: 5 min of use, check the frame rate does not collapse.

---

## Self-debugging playbook

- **Build error**: read the first error only, fix that file, rebuild. New file "not found": it is missing from
  `project.pbxproj` (PBXFileReference, group, build file, sources phase).
- **All engine tests fail at once**: the shader library did not compile; revert the last `.metal.txt` edit.
- **Liner test flaky**: make the simulator deterministic (fixed seed, fixed timestamps) before touching constants.
- **Glass looks flat or wrong over the camera**: confirm it is not inside another glass view or a `Material` and that
  the container wraps siblings; check Reduce Transparency before changing the design.
- **Layout breaks at large Dynamic Type**: use `ViewThatFits` / scroll fallback (as `shadeRow` already does), not fixed
  frames.
- **Stuck after 3 attempts**: stop, write what was tried, revert the experiment, report.

---

# MASTER PROMPT (paste into a new Claude Code session in this repo)

```text
You are working in /Users/azhanum/Documents/GitHub/Final-Sunrise-Develover (iOS app SunriseApp, SwiftUI, iOS 26.6
target, branch Eyeliner-Hanum). Read CLAUDE.md/AGENTS.md first, then
Docs/Plans/2026-10-31-liner-stretch-and-native-glass.md and execute that plan end to end: Phase 0 -> Phase 1 ->
Phase 2 -> Phase 3, in that order. The plan is the source of truth for scope, order, tests and exit criteria.

GOALS
1. Eyeliner: the Try On filter and the guide line must keep up with a user who stretches the outer eye corner to draw a
   wing. Improve responsiveness (per-frame follower output, geometric stretch detection, relaxed limits only in stretch
   mode, smoothing/prediction that does not lag a deliberate pull, guide built from fused landmarks).
2. UI: finish yesterday's restyle (semi-similar to the design) using the NATIVE Liquid Glass API (glassEffect,
   GlassEffectContainer, glassEffectID, .buttonStyle(.glass)) instead of image assets per button. Replace
   GlassChoiceCircle/GlassPickerRow/trailingButtonBackground/CameraBarButton and the other custom controls listed in the
   plan. Remove assets and code that become unreferenced.

AUTONOMY RULES
- Do not ask me anything except at the Gates in the plan (G1 xcode-select password, G2 design link/screenshots,
  G3 device test, G4 background/logo decision, G5 permission prompts). At a gate: say exactly what you need, then
  continue with every task that does not depend on it.
- Keep a task list with the plan's phases and update it as you go. Do not commit, do not push, do not switch branches.
  I will say "commit" when I want it.
- Eyeliner changes are test-first: write the failing test, watch it fail, then change code. Build a deterministic
  stretch simulator in the tests and record baseline vs. final numbers.
- Follow AGENTS.md rules: register every new file in project.pbxproj (reference, group, build file, sources phase);
  use AppColors/AppSpacing/AppTypography; add strings to Localizable.xcstrings; strict concurrency; MediaPipe only in
  the existing wrapper files; no networking; never persist camera frames.
- Log every xcodebuild run to /tmp/sunrise-<phase>-<n>.log and report real numbers. Never claim camera behavior works
  from a Simulator run; say what is verified on Simulator and what needs the device.
- Debug on your own with the playbook: reproduce, read the first error, one hypothesis, smallest change, rerun. After 3
  failed attempts on the same hypothesis family, revert the experiment, record it, and either ask me (if it blocks) or
  list it as not done.
- Use the iOS Simulator tool to screenshot the QA matrix (plan section B) with a DEBUG-only -UIFixture launch argument
  so the glass sits over a still image instead of the missing camera. Save screenshots in the scratchpad.
- Build a signed Release for the device after Phase 1 and tell me when it is ready (G3); keep working on Phase 2 while I
  test.

DEFINITION OF DONE
- All plan exit criteria met or explicitly listed as not met with the reason.
- Full unit test suite green except documented pre-existing failures; test counts before/after reported.
- AGENTS.md has a new dated section at the top, CHANGELOG.md has an entry, ADR 0018 documents the glass decision and the
  stretch design.
- Final report: files changed and why, numbers (benchmark baseline vs. final, tests), screenshots list, what is NOT
  verified, and the device checklist (plan section D) for me.
```
