# Bakes a character master (P2-<name>-textured-master.blend, 2K texture set packed) into the game's
# model files in HelloFlight/Models: <Name>.bin ("STG2"), <name>_base.jpg, <name>_normal.png, <name>_rough.png.
#   python ci/bake-character.py <name> <master.blend> HelloFlight/Models
# Runs with Blender as a Python module (Python 3.11: pip install bpy==5.0.1 pillow) and gltfpack 0.22
# (npm gltfpack; set GLTFPACK to its path if it is not on PATH). Replaces ci/bake-model.py for the four characters.
#
# 1. Simplification (gltfpack / meshoptimizer) keeps UV seams and normals (-sv) and locks the borders where
#    the eyes, mouth and brows meet the body (-slb), so the parts still meet without gaps. Small parts keep more.
# 2. Textures are padded outside the UV islands before shrinking, so seams do not pick up the empty atlas colour.
#    Base colour has the ORM ambient occlusion softly multiplied in (as before); roughness is ORM green.
# 3. Rig weights for the body (head, arms) are stored per vertex. Arm weight follows the surface distance from
#    the arm tip, so other limbs and the head next to the arm no longer move with it.
import heapq
import json
import os
import struct
import subprocess
import sys
import tempfile

import bpy
import numpy as np
from PIL import Image, ImageDraw

# ratio: simplification target per material (default for the rest). groups: material -> mesh in the game file
# (default "body"; eyes blink, the rest of the face parts ride on the head). rig: head pivot, right arm pivot
# and the head weight, matching PenguinRig in PenguinWorld.swift. armMask (optional) limits the arm weight to
# the region the app used before, for arms that lie along the body; armWeight (optional) replaces the surface
# distance weight altogether.
def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

CHARACTERS = {
    "penguin": {"ratio": {"Penguin_Navy_Cream_Coral_PBR": 0.3, "default": 0.55},
                "groups": {"Penguin_Left_Eye_PBR": "eyeL", "Penguin_Right_Eye_PBR": "eyeR", "Penguin_Brows_PBR": "face",
                           "Penguin_Mouth_Interior_PBR": "face"},
                "head": (0, 0.34, -0.01), "arm": (0.165, 0.28, 0), "headWeight": lambda p: smooth(0.29, 0.35, p[:, 1]),
                # The flippers lie along the body, so the surface distance alone reaches the body side below them.
                "armMask": lambda p: smooth(0.175, 0.22, np.abs(p[:, 0])) * (1 - smooth(0.29, 0.35, p[:, 1]))},
    "octopus": {"ratio": {"Octopus_Pink_Spots_Cheeks_PBR": 0.3, "default": 0.45},
                "groups": {"Octopus_Left_Eye_PBR": "eyeL", "Octopus_Right_Eye_PBR": "eyeR", "Octopus_Dark_Ring_Mouth_PBR": "face"},
                "head": (0, 0.16, 0), "arm": (0.22, 0.18, 0), "headWeight": lambda p: smooth(0.1, 0.2, p[:, 1]),
                "armMask": lambda p: smooth(0.21, 0.28, np.abs(p[:, 0])) * (1 - smooth(0.26, 0.32, p[:, 1]))},
    "ghost": {"ratio": {"Ghost_Body_BlueWhite_PBR": 0.35, "default": 0.45},
              "groups": {"Ghost_LeftEye_Gloss_PBR": "eyeL", "Ghost_RightEye_Gloss_PBR": "eyeR", "Ghost_Mouth_PinkTongue_PBR": "face"},
              "head": (0, 0.22, 0), "arm": (0.29, 0.19, 0), "headWeight": lambda p: smooth(0.16, 0.25, p[:, 1]),
              "armMask": lambda p: smooth(0.29, 0.325, np.abs(p[:, 0])) * smooth(0.09, 0.13, p[:, 1]) * (1 - smooth(0.25, 0.29, p[:, 1]))},
    "unicorn": {"ratio": {"Unicorn | White body and authored pastel features": 0.3, "Unicorn | Five-color rainbow tail": 0.35,
                          "Unicorn | Golden spiral horn": 0.5, "default": 0.7},
                "groups": {"Unicorn | Left glossy eye": "eyeL", "Unicorn | Right glossy eye": "eyeR", "Unicorn | Left soft brow": "face",
                           "Unicorn | Right soft brow": "face"},
                "head": (0, 0.36, 0), "arm": (0.11, 0.31, 0.02), "headWeight": lambda p: smooth(0.33, 0.39, p[:, 1]),
                # The forelegs are joined to the belly along their whole inner side, so a leg that moves on its own
                # pulls the belly out like a web. The side of the body moves with the leg instead (the app's weights).
                "armWeight": lambda p: smooth(0.11, 0.15, np.abs(p[:, 0])) * smooth(0.14, 0.2, p[:, 1]) * (1 - smooth(0.33, 0.39, p[:, 1]))},
}
BASE, MAPS = 1024, 512

name, master, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
config = CHARACTERS[name]
gltfpack = os.environ.get("GLTFPACK", "gltfpack")
work = tempfile.mkdtemp()

# --- Export the native mesh (Y up, facing +Z like the game) ---
bpy.ops.wm.open_mainfile(filepath=master)
mesh_object = next(o for o in bpy.data.objects if o.type == "MESH")
for o in bpy.data.objects:
    o.select_set(o == mesh_object)
bpy.context.view_layer.objects.active = mesh_object
source = os.path.join(work, "source.glb")
bpy.ops.export_scene.gltf(filepath=source, export_format="GLB", use_selection=True, export_image_format="NONE",
                          export_materials="EXPORT", export_normals=True, export_texcoords=True, export_apply=True,
                          export_yup=True, export_animations=False)


def read_glb(path):
    """Primitives as (material name, positions, normals, uvs, indices) with node transforms applied."""
    data = open(path, "rb").read()
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + length])
    blob = data[20 + length + 8:]

    def accessor(index):
        a = gltf["accessors"][index]
        v = gltf["bufferViews"][a["bufferView"]]
        dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[a["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
        raw = blob[v.get("byteOffset", 0) + a.get("byteOffset", 0):]
        stride = v.get("byteStride", 0)
        itemsize = np.dtype(dtype).itemsize * width
        if stride and stride != itemsize:
            rows = np.frombuffer(raw, np.uint8, (a["count"] - 1) * stride + itemsize)
            rows = np.lib.stride_tricks.as_strided(rows, (a["count"], itemsize), (stride, 1))
            return rows.copy().view(dtype).reshape(a["count"], width).astype(np.float64)
        arr = np.frombuffer(raw, dtype, a["count"] * width)
        return arr.reshape(a["count"], width).astype(np.float64) if width > 1 else arr

    def node_matrix(node):
        if "matrix" in node:
            return np.array(node["matrix"]).reshape(4, 4).T
        m = np.eye(4)
        x, y, z, w = node.get("rotation", [0, 0, 0, 1])
        r = np.array([[1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)],
                      [2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)],
                      [2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)]])
        m[:3, :3] = r * np.array(node.get("scale", [1, 1, 1]))
        m[:3, 3] = node.get("translation", [0, 0, 0])
        return m

    result = []
    def visit(index, parent):
        node = gltf["nodes"][index]
        m = parent @ node_matrix(node)
        if "mesh" in node:
            normal_matrix = np.linalg.inv(m[:3, :3]).T
            for prim in gltf["meshes"][node["mesh"]]["primitives"]:
                attrs = prim["attributes"]
                p = accessor(attrs["POSITION"]) @ m[:3, :3].T + m[:3, 3]
                n = accessor(attrs["NORMAL"]) @ normal_matrix.T
                n /= np.linalg.norm(n, axis=1, keepdims=True)
                material = gltf["materials"][prim["material"]]["name"]
                result.append((material, p, n, accessor(attrs["TEXCOORD_0"]), accessor(prim["indices"]).astype(np.uint32).reshape(-1, 3)))
        for child in node.get("children", []):
            visit(child, m)
    for root in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
        visit(root, np.eye(4))
    return result


# --- Simplify (one gltfpack run per ratio; locked borders keep the runs consistent where parts meet) ---
ratios = config["ratio"]
source_prims = read_glb(source)
groups = {}
for material in dict.fromkeys(m for m, *_ in source_prims):   # a material can come as several primitives
    ratio = ratios.get(material, ratios["default"])
    simplified = os.path.join(work, f"simplified-{ratio}.glb")
    if not os.path.exists(simplified):
        subprocess.run([gltfpack, "-i", source, "-o", simplified, "-si", str(ratio), "-sv", "-slb", "-noq", "-km", "-kn", "-kv"],
                       check=True, capture_output=True)
    group = groups.setdefault(config["groups"].get(material, "body"), [[], [], [], [], 0])
    before = sum(len(t) for m, *_, t in source_prims if m == material)
    after = 0
    for _, p, n, uv, idx in (prim for prim in read_glb(simplified) if prim[0] == material):
        group[0].append(p); group[1].append(n); group[2].append(uv); group[3].append(idx + group[4]); group[4] += len(p)
        after += len(idx)
    print(f"{material:55s} {before:6d} -> {after:6d} triangles")
meshes = {k: (np.concatenate(v[0]), np.concatenate(v[1]), np.concatenate(v[2]), np.concatenate(v[3])) for k, v in groups.items()}


# --- Rig weights for the body ---
def arm_weights(p, idx, pivot, side):
    """Arm weight from the surface distance to the arm tip: 1 out to the shoulder, blending to 0 just past it."""
    key = np.round(p / 1e-5).astype(np.int64)
    _, weld, = np.unique(key, axis=0, return_inverse=True)[0:2]
    weld = weld.reshape(-1)
    count = weld.max() + 1
    position = np.zeros((count, 3)); position[weld] = p
    edges = {}
    for a, b, c in weld[idx]:
        for u, v in ((a, b), (b, c), (c, a)):
            if u != v:
                d = float(np.linalg.norm(position[u] - position[v]))
                edges.setdefault(u, []).append((v, d)); edges.setdefault(v, []).append((u, d))
    pivot = np.array(pivot) * np.array([side, 1, 1])
    # Tip: the vertex farthest out to the side among those near the arm's height.
    near = np.abs(position[:, 1] - pivot[1]) < 0.12
    tip = int(np.argmax(np.where(near, position[:, 0] * side, -np.inf)))
    distance = np.full(count, np.inf); distance[tip] = 0
    heap = [(0.0, tip)]
    while heap:
        d, u = heapq.heappop(heap)
        if d > distance[u]: continue
        for v, w in edges.get(u, []):
            if d + w < distance[v]:
                distance[v] = d + w; heapq.heappush(heap, (d + w, v))
    # The shoulder: surface points closest to the pivot.
    closest = np.argsort(np.linalg.norm(position - pivot, axis=1))[:12]
    shoulder = float(np.median(distance[closest]))
    weight = 1 - smooth(shoulder - 0.03, shoulder + 0.04, distance)
    weight[position[:, 0] * side < 0] = 0
    return weight[weld], position[tip], shoulder

p, n, uv, idx = meshes["body"]
arm = np.zeros(len(p))
for side in (-1, 1) if "armWeight" not in config else ():
    w, tip, shoulder = arm_weights(p, idx, config["arm"], side)
    arm = np.maximum(arm, w)
    print(f"arm {side:+d}: tip {tip.round(3)}, shoulder at {shoulder:.3f} m along the surface")
if "armWeight" in config:
    arm = config["armWeight"](p)
if "armMask" in config:
    arm *= config["armMask"](p)
head = config["headWeight"](p) * (1 - arm)
weights = {"body": np.stack([head, arm], 1)}


# --- Textures ---
def image_array(suffix):
    image = next(i for i in bpy.data.images if i.name.endswith(suffix))
    w, h = image.size
    return np.array(image.pixels[:], np.float32).reshape(h, w, 4)[::-1, :, :3]   # top row first

def coverage(size):
    """Pixels covered by the master's UV islands."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for _, _, _, uvs, tri in source_prims:
        for t in tri:
            draw.polygon([(float(uvs[i, 0] * size), float(uvs[i, 1] * size)) for i in t], fill=255)
    return np.asarray(mask) > 0

def pad(array, mask):
    """Push-pull fill: pixels outside the islands take the average colour of the nearby islands."""
    if mask.all() or array.shape[0] <= 1:
        return array
    weight = mask.astype(np.float32)[..., None]
    h, w = mask.shape
    small = (array * weight).reshape(h // 2, 2, w // 2, 2, -1).sum((1, 3))
    small_w = weight.reshape(h // 2, 2, w // 2, 2, 1).sum((1, 3))
    filled = pad(small / np.maximum(small_w, 1e-6), small_w[..., 0] > 0)
    up = filled.repeat(2, 0).repeat(2, 1)
    return np.where(mask[..., None], array, up)

def save(array, size, path):
    image = Image.fromarray((np.clip(array, 0, 1) * 255).round().astype(np.uint8))
    image = image.resize((size, size), Image.LANCZOS)
    image.save(path, quality=88) if path.endswith(".jpg") else image.save(path, optimize=True)

mask = coverage(2048)
orm = pad(image_array("_ORM_2K"), mask)
base = pad(image_array("_BaseColor_2K"), mask)
save(base * (0.6 + 0.4 * orm[:, :, :1]), BASE, os.path.join(out_dir, f"{name}_base.jpg"))
save(pad(image_array("_Normal_OpenGL_2K"), mask), MAPS, os.path.join(out_dir, f"{name}_normal.png"))
save(np.repeat(orm[:, :, 1:2], 3, 2), MAPS, os.path.join(out_dir, f"{name}_rough.png"))   # RGB, like the other maps


# --- Write "STG2": header JSON, then meshes (positions, normals, uvs, indices, and weights for listed meshes) ---
with open(os.path.join(out_dir, f"{name.capitalize()}.bin"), "wb") as out:
    header = json.dumps({"weights": sorted(weights)}).encode()
    out.write(b"STG2" + struct.pack("<I", len(header)) + header + struct.pack("<I", len(meshes)))
    for group_name, (p, n, uv, idx) in sorted(meshes.items()):
        out.write(struct.pack("<H", len(group_name)) + group_name.encode() + struct.pack("<II", len(p), idx.size))
        out.write(p.astype("<f4").tobytes() + n.astype("<f4").tobytes() + uv.astype("<f4").tobytes() + idx.astype("<u4").tobytes())
        if group_name in weights:
            out.write(weights[group_name].astype("<f4").tobytes())
        print(f"{group_name:5s} vertices {len(p):5d} triangles {len(idx):5d}")
