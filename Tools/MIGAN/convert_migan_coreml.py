"""Convert MI-GAN 256 FFHQ (Picsart AI Research, MIT) to Core ML and check it against PyTorch.

Usage: python -I convert.py <repo dir> <checkpoint .pt> <output .mlpackage> <verification image>...
Loads only lib/model_zoo/migan_inference.py from the repository (no package __init__ code).
"""
import importlib.util
import sys

import coremltools as ct
import numpy as np
import torch
from PIL import Image

repo, checkpoint, output, images = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]

spec = importlib.util.spec_from_file_location("migan_inference", f"{repo}/lib/model_zoo/migan_inference.py")
migan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migan)

model = migan.Generator(resolution=256)
model.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True))
model.eval()

example = torch.zeros(1, 4, 256, 256)
with torch.no_grad():
    traced = torch.jit.trace(model, example)

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="input", shape=(1, 4, 256, 256), dtype=np.float32)],
    outputs=[ct.TensorType(name="output", dtype=np.float32)],
    convert_to="mlprogram",
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS17,
)
mlmodel.author = "Picsart AI Research (MI-GAN, MIT licence); converted for SunriseApp"
mlmodel.short_description = "MI-GAN 256 FFHQ inpainting generator. Input [mask-0.5, image*mask], image in -1..1, mask 1 = keep."
mlmodel.save(output)


def preprocess(rgb: np.ndarray, keep: np.ndarray) -> np.ndarray:
    """Same as scripts/demo.py and BrowInpainter.input."""
    img = rgb.astype(np.float32) * 2 / 255 - 1
    img = img.transpose(2, 0, 1)[None]
    mask = keep.astype(np.float32)[None, None]
    return np.concatenate([mask - 0.5, img * mask], axis=1)


def brow_mask() -> np.ndarray:
    """Two brow-shaped holes like the app's, on an FFHQ-like crop (eyes ~40% from the top)."""
    keep = np.ones((256, 256), dtype=np.uint8)
    yy, xx = np.mgrid[0:256, 0:256]
    for cx in (85, 171):
        keep[((xx - cx) / 38.0) ** 2 + ((yy - 78) / 11.0) ** 2 < 1] = 0
    return keep


reloaded = ct.models.MLModel(output)
keep = brow_mask()
worst = 0.0
for path in images:
    img = Image.open(path).convert("RGB")
    side = min(img.size)
    left, top = (img.size[0] - side) // 2, (img.size[1] - side) // 2
    rgb = np.array(img.crop((left, top, left + side, top + side)).resize((256, 256), Image.BICUBIC))
    x = preprocess(rgb, keep)
    with torch.no_grad():
        ref = model(torch.from_numpy(x)).numpy()
    got = reloaded.predict({"input": x})["output"]
    diff = np.abs(ref - got)
    to8 = lambda a: np.clip((a[0].transpose(1, 2, 0) * 0.5 + 0.5) * 255, 0, 255)
    hole = keep == 0
    mse = np.mean((to8(ref)[hole] - to8(got)[hole]) ** 2)
    psnr = 10 * np.log10(255 ** 2 / max(mse, 1e-10))
    worst = max(worst, float(diff.max()))
    print(f"{path.split('/')[-1]}: output range [{ref.min():.2f}, {ref.max():.2f}], max |torch - coreml| = {diff.max():.4f}, "
          f"mean = {diff.mean():.5f}, hole PSNR = {psnr:.1f} dB")
    composed = rgb.copy()
    composed[hole] = to8(got).astype(np.uint8)[hole]
    Image.fromarray(composed).save(f"{output}.{path.split('/')[-1]}.png")
print(f"worst max abs diff: {worst:.4f}")
print("inputs:", [(i.name, i.type.multiArrayType.shape) for i in reloaded.get_spec().description.input])
print("outputs:", [(o.name, o.type.multiArrayType.shape) for o in reloaded.get_spec().description.output])
