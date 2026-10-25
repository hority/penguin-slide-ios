# Reference character additions

Four playable characters are appended to the original roster: rabbit (ウサギ), dolphinchibi (イルカ), rhino (サイ), and orca (シャチ). The scenery `Dolphin.bin` and its maps remain unchanged. The quiz rabbit illustration is preserved; the new rabbit selection icon uses `rabbitchibi.png`. Selection uses four columns and two rows. Fish is reused for dolphin/orca and pumpkin for rabbit/rhino.

The originals were generated privately with Tripo H3.1 from the supplied four-character reference. Full-resolution originals and packed editable Blender masters are retained separately from this source repository.

Runtime assets use Y-up, +Z forward, feet at zero, with heights 0.78 (rabbit, including ears) and 0.70 (others). Each character has 9,139–9,140 triangles, including independent eye meshes. Color maps are 1024px JPEG; OpenGL normal and roughness maps are 512px PNG. Roughness has a 90/255 floor and geometric normals are used for the new characters (normal-map strength zero) for the soft reference appearance. Small UV overshoots from simplification are clamped and output normals normalized.

No purchased skeleton or animation clips are needed. Existing head/arm shader animation uses species-specific neck/shoulder positions and spatial weights. Tripo fused the eyes into the face, so smooth glossy black eye shells and white highlights are rebuilt at the measured pupil positions as `eyeL` and `eyeR`; the original face topology is retained, socket relief is smoothed without collapsing overlapping layers, and eye regions are restored to skin in the atlas underneath them. A shared atlas holds the repaired Tripo skin and eye colors. This uses exactly the existing `PenguinModel` eye-node path: bounding-box center pivot, attachment to the head, and vertical scale `max(0.08, 1 - amount)`. `PenguinGame` retains the same 0.14-second sine blink, randomized 2.2–4.5-second interval, and feeding half-close amount of 0.6. No texture swap or character-specific blink code remains. Mouth targets are placed at the visible mouth surface for feeding.

## Rebuild

Requirements: Blender 4.3, Python with Pillow/numpy, gltfpack 1.3. Keep full-resolution GLBs outside the source checkout, named `rabbit.glb`, `dolphinchibi.glb`, `rhino.glb`, `orca.glb`.

```sh
python3 ci/extract-tripo-textures.py /path/to/originals HelloFlight/Models
for name in rabbit dolphinchibi rhino orca; do
  gltfpack -i /path/to/originals/$name.glb -o /path/to/output/$name-simplified.glb -si 0.0028 -sv -noq -kn -km
  blender -b --threads 4 --python ci/prepare-tripo-character.py -- "$name" /path/to/output/$name-simplified.glb /path/to/output HelloFlight/Models
done
# Preserve the unseparated output once, outside the checkout, then separate eyes:
python3 ci/separate-tripo-eyes.py /path/to/pre-eye-models HelloFlight/Models
blender -b --threads 4 --python ci/render-character-check.py -- HelloFlight/Models /path/to/output --export
python3 ci/validate-character-assets.py
```

The Blender converter enforces the final triangle budget, packs maps into editable `.blend` files, exports portable textured `.glb` files, and writes native STG2 payloads. Selection icons are rendered as transparent 256px images with `ci/render-character-check.py -- MODELS OUTPUT --icons`. GLBs intentionally have no skeleton; gameplay animation is defined in `PenguinWorld.swift`.

## Verification boundary

Asset checks cover binary layout, finite coordinates, normalized normals, UV bounds, valid indices, nondegenerate triangles, triangle budget, ground alignment, texture dimensions, and readable selection illustrations. Blender previews cover front, three-quarter, open, partial and closed eye states and head/arm poses, with the existing penguin as a comparison. These previews are not screenshots from SceneKit.

Local asset verification runs on Linux. Native compilation and signing use the existing TestFlight workflow; consult its run result for build/upload status. SceneKit behavior and selection/feeding/blinking require real-device verification.
