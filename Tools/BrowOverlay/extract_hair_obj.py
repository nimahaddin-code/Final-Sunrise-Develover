#!/usr/bin/env python3
"""Keeps only one brow's hair ribbons (no base surface) of an OBJ eyebrow pair, renumbering vertices.

python3 extract_hair_obj.py eyebrows_3d.obj SunriseApp/Resources/brow-hair-3d.obj [Right_Eyebrow]
The app mirrors it for the other brow. Units stay metres; X along the brow (head at the lowest X), Y depth (front is -Y), Z up.
"""
import sys

src, out = sys.argv[1], sys.argv[2]
group = sys.argv[3] if len(sys.argv) > 3 else "Right_Eyebrow"
vertices, faces, current, material = [], [], None, None
for line in open(src):
    p = line.split()
    if not p:
        continue
    if p[0] == "v":
        vertices.append(p[1:4])
    elif p[0] == "g":
        current = p[1]
    elif p[0] == "usemtl":
        material = p[1]
    elif p[0] == "f" and current == group and material != "brow_base":
        faces.append((material, [int(x.split("/")[0]) - 1 for x in p[1:]]))
used = sorted({i for _, f in faces for i in f})
remap = {old: new + 1 for new, old in enumerate(used)}
with open(out, "w") as o:
    o.write(f"# Hair ribbons of {group} from {src.split('/')[-1]} (base surface left out). Metres; X along the brow, Y depth (front -Y), Z up.\n")
    for i in used:
        o.write("v " + " ".join(vertices[i]) + "\n")
    last = None
    for material, f in faces:
        if material != last:
            o.write(f"usemtl {material}\n")
            last = material
        o.write("f " + " ".join(str(remap[i]) for i in f) + "\n")
