#!/usr/bin/env python3
"""Renders one brow of an OBJ eyebrow pair (hair ribbons only) into a transparent PNG for a `BrowOverlay` image set.

Front view (X horizontal, Z up), head on the left. Each ribbon becomes a line along its long axis, 4 px wide at 1200 px so
strands survive being shown at about a quarter of that size. Pillow only:  python3 render_obj_brow.py brows.obj out.png
Made for Brow 3 from eyebrows_3d.obj (group Right_Eyebrow; the left brow is its mirror).
"""
import math
import sys
from PIL import Image, ImageDraw

obj, out = sys.argv[1], sys.argv[2]
group = sys.argv[3] if len(sys.argv) > 3 else "Right_Eyebrow"
vs, ribbons, cur, mat = [], [], None, None
for line in open(obj):
    p = line.split()
    if not p:
        continue
    if p[0] == "v":
        vs.append(tuple(map(float, p[1:4])))
    elif p[0] == "g":
        cur = p[1]
    elif p[0] == "usemtl":
        mat = p[1]
    elif p[0] == "f" and cur == group and mat != "brow_base":
        ribbons.append((mat, [int(x.split("/")[0]) - 1 for x in p[1:]]))

xs = [vs[i][0] for _, f in ribbons for i in f]
zs = [vs[i][2] for _, f in ribbons for i in f]
x0, x1, z0, z1 = min(xs) - 0.0001, max(xs) + 0.0001, min(zs) - 0.0001, max(zs) + 0.0001
width = 4800
scale = width / (x1 - x0)
im = Image.new("RGBA", (width, int((z1 - z0) * scale) + 1), (0, 0, 0, 0))
draw = ImageDraw.Draw(im)
colors = {"hair_dark": (62, 38, 26, 255), "hair_mid": (112, 74, 50, 255), "hair_light": (172, 124, 88, 255)}
point = lambda i: ((vs[i][0] - x0) * scale, (z1 - vs[i][2]) * scale)
lw = 16
for mat, f in sorted(ribbons, key=lambda t: -sum(vs[i][1] for i in t[1]) / len(t[1])):  # far first
    q = [point(i) for i in f]
    e = [math.dist(q[k], q[(k + 1) % 4]) for k in range(4)]
    k = 0 if e[0] + e[2] < e[1] + e[3] else 1  # edges k and k + 2 are the ribbon's short ends
    a = ((q[k][0] + q[(k + 1) % 4][0]) / 2, (q[k][1] + q[(k + 1) % 4][1]) / 2)
    b = ((q[k + 2][0] + q[(k + 3) % 4][0]) / 2, (q[k + 2][1] + q[(k + 3) % 4][1]) / 2)
    draw.line([a, b], fill=colors[mat], width=lw)
    for c in (a, b):
        draw.ellipse([c[0] - lw / 2, c[1] - lw / 2, c[0] + lw / 2, c[1] + lw / 2], fill=colors[mat])
im = im.crop(im.getchannel("A").getbbox())
im.resize((1200, round(im.height * 1200 / im.width)), Image.LANCZOS).save(out, optimize=True)
