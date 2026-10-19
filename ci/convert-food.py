# Converts the favorite-food GLBs (Tripo P2.0 geometry, Blender-made textures) into the game's
# model format in HelloFlight/Models: <Name>.bin ("STG2", same as ci/bake-model.py), <name>_base.jpg
# and <name>_rough.png.
# 1. Simplify each GLB first with gltfpack (meshoptimizer), keeping UV seams and no quantization:
#      npx gltfpack@0.22.0 -i blue-fish.glb -o simplified/blue-fish.glb -si 0.24 -noq   (0.12 for the others)
# 2. python3 ci/convert-food.py <simplified dir> HelloFlight/Models
# The GLBs are Y-up with the front on +X and the origin at the bottom centre. The game wants the front
# on +Z, so each model is turned -90 degrees about Y, centred on its bounding box and scaled so the
# longest side is 1 (the game scales the node to the size it needs).
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

MODELS = {"blue-fish": "bluefish", "jack-o-lantern": "pumpkin", "octopus-sausage": "sausage", "rainbow-lollipop": "lollipop"}
BASE, ROUGH = 512, 128

src, out_dir = sys.argv[1], sys.argv[2]
for source, name in MODELS.items():
    data = open(os.path.join(src, source + ".glb"), "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    blob = data[20 + length + 8:]

    def view(index):
        v = gltf["bufferViews"][index]
        return blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]

    def accessor(index):
        a = gltf["accessors"][index]
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[a["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        raw = view(a["bufferView"])[a.get("byteOffset", 0):]
        return np.frombuffer(raw, dtype, a["count"] * width).reshape(a["count"], width) if width > 1 else np.frombuffer(raw, dtype, a["count"])

    primitive = gltf["meshes"][0]["primitives"][0]
    position = accessor(primitive["attributes"]["POSITION"]).astype(np.float64)
    normal = accessor(primitive["attributes"]["NORMAL"]).astype(np.float64)
    uv = accessor(primitive["attributes"]["TEXCOORD_0"]).astype(np.float32)
    index = accessor(primitive["indices"]).astype("<u4")
    node = gltf["nodes"][0]
    assert "matrix" not in node and "rotation" not in node, "unexpected node transform"
    position = position * node.get("scale", [1, 1, 1]) + node.get("translation", [0, 0, 0])

    # Front +X -> +Z: (x, y, z) -> (-z, y, x).
    turn = lambda v: np.stack([-v[:, 2], v[:, 1], v[:, 0]], 1)
    position, normal = turn(position), turn(normal)
    lo, hi = position.min(0), position.max(0)
    position = (position - (lo + hi) / 2) / (hi - lo).max()
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)

    with open(os.path.join(out_dir, name.capitalize() + ".bin"), "wb") as out:
        header = b"{}"
        out.write(b"STG2" + struct.pack("<I", len(header)) + header + struct.pack("<I", 1))
        out.write(struct.pack("<H", 4) + b"body" + struct.pack("<II", len(position), len(index)))
        out.write(position.astype("<f4").tobytes() + normal.astype("<f4").tobytes() + uv.astype("<f4").tobytes() + index.tobytes())

    # Textures: base colour with the ORM ambient occlusion softly multiplied in, and the roughness (ORM green).
    material = gltf["materials"][primitive.get("material", 0)]["pbrMetallicRoughness"]
    image = lambda texture: Image.open(io.BytesIO(view(gltf["images"][gltf["textures"][texture["index"]]["source"]]["bufferView"])))
    base = np.asarray(image(material["baseColorTexture"]).convert("RGB").resize((BASE, BASE), Image.LANCZOS), np.float32) / 255
    orm = np.asarray(image(material["metallicRoughnessTexture"]).convert("RGB").resize((BASE, BASE), Image.LANCZOS), np.float32) / 255
    shaded = np.clip(base * (0.6 + 0.4 * orm[:, :, :1]), 0, 1)
    Image.fromarray((shaded * 255).round().astype(np.uint8)).save(os.path.join(out_dir, f"{name}_base.jpg"), quality=88)
    rough = Image.fromarray((orm[:, :, 1] * 255).round().astype(np.uint8)).resize((ROUGH, ROUGH), Image.LANCZOS)
    rough.save(os.path.join(out_dir, f"{name}_rough.png"), optimize=True)
    print(f"{name}: {len(position)} vertices, {len(index) // 3} triangles, size {(hi - lo).round(3)}")
