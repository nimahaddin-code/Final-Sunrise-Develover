# Hiding the natural brow: brow-space fill and MI-GAN — 28 October 2026 · Khalish

## Context

The "Natural brow" test toggle hides the user's own eyebrow (MediaPipe brow path, ADR 0013). Single-pass shader
fills built from a few skin samples read as a grey smudge or a light patch next to TikTok's eraser: MediaPipe's brow
rows sit inside the hair, so nearby samples catch hair, and a fill that only matches two sample points leaves seams.

## Decision

Two layers, both on device, both in `Features/BeautyBlush`.

1. **Brow-space push-pull fill (always on, no dependency).** `BrowEraser` unwraps each brow into its own 256 x 128
   brow-space texture (u along the brow, w -0.5...0.75 brow widths across it, one array slice per brow), with each
   pixel premultiplied by how much it is known skin (0 inside the hidden area, `browHide`). Mipmap generation is the
   push step; `browFillFragment` pulls from the coarsest level down, so the hole is filled smoothly from the skin on
   every side, not from sample points. Fine texture is borrowed from a forehead band 0.45...0.63 above the brow
   (±6%). The fill is blended frame to frame (τ ≈ 0.12 s) in two ping-pong textures. Because it lives in brow space,
   it stays attached to the brow as the head moves; the brow strip samples it where `browHide` hides the brow.

2. **MI-GAN inpainting (optional, Core ML).** `BrowInpainter` runs MI-GAN's 256 generator on an upright, FFHQ-like
   face crop (`BrowEraser.faceCrop`: eyes level at 40% from the top, width twice the outer-eye span) with the hidden
   area as its mask, at most every 0.12 s, on its own queue. Input is MI-GAN's `[mask - 0.5, image * mask]`
   (image in -1...1, mask 1 = keep); the output is composited back over known pixels, mapped into brow space with the
   geometry of the frame it was asked about (`browModelFragment`), and faded in over the push-pull fill
   (weight τ ≈ 0.2 s, dropped after 1.5 s without a result). Without the model the push-pull fill is used alone.

## Model provenance

- Source: Picsart AI Research, MI-GAN (ICCV 2023), github.com/Picsart-AI-Research/MI-GAN.
- Licence: code MIT; weights under `LICENSE-WEIGHTS`, also MIT-style ("use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell"), so commercial use is allowed. The copyright and permission notice must ship
  with the app (add it to the app's acknowledgements when the model is bundled).
- Chosen checkpoint: `migan_256_ffhq.pt` (faces). Bundle as `MIGANFace256.mlpackage` (Xcode compiles it to
  `MIGANFace256.mlmodelc`); one 1 x 4 x 256 x 256 float input, one 1 x 3 x 256 x 256 output (names read at load).
- Converted 28 October 2026 with `Tools/MIGAN/convert_migan_coreml.py` (coremltools 9.0, torch 2.5.1, Python 3.11):
  loads only `lib/model_zoo/migan_inference.py` from the repository, traces the generator on 1 x 4 x 256 x 256,
  converts to an ML program (FP16, iOS 17). Checkpoint sha256
  3cab897cfcc3fcbe224510cedad06a634ae8bf5bd7120428a32fd7224f4237f4. The repository's `scripts/demo.py` confirms the
  input layout (`img*2/255-1`, mask 1 = keep, `cat([mask-0.5, img*mask])`) and output (`*0.5+0.5`).
- Check against PyTorch on three face crops with brow-shaped holes: worst max |difference| 0.0072 on the -1...1
  scale (under one 8-bit level), PSNR 68-73 dB inside the holes. 12 MB `.mlpackage`.
- Bundled as `SunriseApp/Resources/MIGANFace256.mlpackage` (compiled to `MIGANFace256.mlmodelc`); the MIT notices
  for code and weights ship as `SunriseApp/Resources/MI-GAN-LICENSE.txt`.

## Privacy and limits

No network, nothing stored: crops and masks live in memory for one request. Not measured on a device: push-pull
cost (expected around a millisecond), model latency on the Neural Engine, and visual quality. In the Simulator (Mac
CPU) the first inpainting call, model load included, took 0.34 s. MI-GAN was trained on
whole FFHQ faces; small brow holes are in distribution, but results need device QA. A brow-pixel segmentation model
was rejected for now: the available face-parsing weights are trained on CelebAMask-HQ (non-commercial only).
