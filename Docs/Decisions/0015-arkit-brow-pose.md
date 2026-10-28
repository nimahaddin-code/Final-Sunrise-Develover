# Brow steadied by ARKit's face pose, and a 3D hair brow — 28 October 2026 · Khalish

## Choice

MediaPipe still finds the brow (ADR 0013), but two things now use ARKit's face anchor from the same frame
(`frame.anchors`, `ARFaceAnchor.isTracked`). No new dependency, nothing persisted.

1. **Stabilizer** (`BrowFaceStabilizer`, `BrowFaceFrame`). Every brow landmark (pixels) is lifted onto ARKit's face
   mesh by casting the camera ray through it (face-local metres), smoothed there with One Euro (1.5 Hz, beta 60, 0.12 mm
   hold) and projected back with the same frame's camera. Head motion is removed by the pose, so a still face gives a still
   brow and a turning head adds no lag; real brow movement (a few millimetres) still passes. If ARKit has no tracked face,
   a ray misses the mesh, or the result sits more than 0.15 eye spans from what MediaPipe saw (the two disagree), the old
   image-space `BrowObservationSmoother` is used. `beautyBrow.metrics` reports `brow_stabilized`.
2. **3D hair brow** ("Brow 3D", `BrowOverlay.is3D`). `Resources/brow-hair-3d.obj` (1850 hair ribbons, from the supplied
   `eyebrows_3d.obj`; `Tools/BrowOverlay/extract_hair_obj.py`) is laid on each brow: the stabilized head and tail
   (lifted onto the mesh) fix length and scale, the mesh normal and the direction to the forehead fix the stand
   (`BrowHairPlacement`; the other brow is the mirror image). It is drawn in Metal with ARKit's projection: the face mesh is
   drawn first into the depth buffer only, so hairs behind the nose or brow ridge hide; hairs are 0.1 mm wide, so each is
   widened to 1.5 px with its coverage lowered by the same ratio (no flicker); lighting comes from ARKit's ambient estimate,
   not the camera pixel (no shimmer); a hand over the brow hides it through the face-skin mask. Without a tracked face (or
   until the mesh has loaded) the same brow is drawn as its picture. The natural brow is hidden by the same strip as for the
   picture brows.

## Why

The wobble came from MediaPipe's 2D points being noisy while ARKit's pose is steady (a frame-rate cap, the first thing tried,
cannot fix per-frame noise). A 3D brow gives parallax on a turned head and real depth testing, which the flat strip cannot.

## Limits

- ARKit's mesh is coarse around the brow: hairs float 2.2 mm above the surface so it does not cut them off. A hair brow is
  placed from head, tail and one normal, so it does not follow the brow's own curve beyond the mesh's shape.
- The hands/fringe check is still the 2D face-skin mask, so a hand is hidden by 2D coverage, not by depth.
- Simulator tests cover the maths and the GPU pipeline on synthetic data (a moving head with noisy landmarks, placement,
  depth hiding, hand mask). Whether ARKit's and MediaPipe's frames line up on a real face, and how it looks, needs a device.
