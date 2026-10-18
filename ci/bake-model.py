# Blender (4.3, headless) step for the characters and sea creatures:
#   blender -b Design/Models/<name>.blend --python ci/bake-model.py -- <name> HelloFlight/Models
# <name> is one of MODELS below (the editable masters as delivered, textures packed).
# 1. Shrinks the packed 2K texture set (already baked onto the mesh) to what the game needs:
#    base colour with the ORM ambient occlusion softly multiplied in, a normal map and the
#    roughness (ORM green).
# 2. Decimates each material part with Blender's collapse decimator (UVs are interpolated)
#    and writes <out_dir>/<Name>.bin ("STG2", as the stage) plus <name>_base.jpg,
#    <name>_normal.png and <name>_rough.png. Blender (Z up, facing -Y) -> game (Y up, facing +Z).
import os
import struct
import sys

import bpy
import numpy as np

# keep: decimation ratio per material (default for the rest); small parts keep more.
# groups: which mesh each material goes to (default "body").
MODELS = {
    "penguin": {"base": 1024, "maps": 512, "keep": {"Penguin_Navy_Cream_Coral_PBR": 0.28, "Penguin_Scarf_Tail_PBR": 0.4, "Penguin_Left_Eye_PBR": 0.5,
                                                    "Penguin_Right_Eye_PBR": 0.5, "Penguin_Mouth_Interior_PBR": 0.5,
                                                    "Penguin_Brows_PBR": 0.6, "default": 0.5},
                "groups": {"Penguin_Left_Eye_PBR": "eyeL", "Penguin_Right_Eye_PBR": "eyeR", "Penguin_Brows_PBR": "face",
                           "Penguin_Mouth_Interior_PBR": "face"}},
    "octopus": {"base": 1024, "maps": 512, "keep": {"Octopus_Pink_Spots_Cheeks_PBR": 0.3, "Octopus_Left_Eye_PBR": 0.4, "Octopus_Right_Eye_PBR": 0.4,
                                                    "Octopus_Dark_Ring_Mouth_PBR": 0.4, "default": 0.5},
                "groups": {"Octopus_Left_Eye_PBR": "eyeL", "Octopus_Right_Eye_PBR": "eyeR", "Octopus_Dark_Ring_Mouth_PBR": "face"}},
    "ghost": {"base": 1024, "maps": 512, "keep": {"Ghost_Body_BlueWhite_PBR": 0.35, "Ghost_LeftEye_Gloss_PBR": 0.4, "Ghost_RightEye_Gloss_PBR": 0.4,
                                                  "Ghost_Mouth_PinkTongue_PBR": 0.5, "default": 0.5},
              "groups": {"Ghost_LeftEye_Gloss_PBR": "eyeL", "Ghost_RightEye_Gloss_PBR": "eyeR", "Ghost_Mouth_PinkTongue_PBR": "face"}},
    "unicorn": {"base": 1024, "maps": 512, "keep": {"Unicorn | White body and authored pastel features": 0.28, "Unicorn | Five-color rainbow tail": 0.35,
                                                    "Unicorn | Golden spiral horn": 0.5, "Unicorn | Left glossy eye": 0.6, "Unicorn | Right glossy eye": 0.6,
                                                    "default": 0.8},
                "groups": {"Unicorn | Left glossy eye": "eyeL", "Unicorn | Right glossy eye": "eyeR", "Unicorn | Left soft brow": "face",
                           "Unicorn | Right soft brow": "face"}},
    "whale": {"base": 512, "maps": 256, "keep": {"default": 0.14}},
    "dolphin": {"base": 512, "maps": 256, "keep": {"default": 0.12}},
    "flyingfish": {"base": 512, "maps": 256, "keep": {"default": 0.1}},
    "star": {"base": 256, "maps": 256, "keep": {"default": 0.3}},
}

args = sys.argv[sys.argv.index("--") + 1:]
name, out_dir = args[0], args[1]
config = MODELS[name]
os.makedirs(out_dir, exist_ok=True)
scene = bpy.context.scene


def pixels(image):
    return np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)


def save(array, path, mode):
    image = bpy.data.images.new(os.path.basename(path), array.shape[1], array.shape[0], alpha=False)
    rgba = np.ones((array.shape[0], array.shape[1], 4), dtype=np.float32)
    rgba[:, :, :3] = array if array.ndim == 3 else array[:, :, None]
    image.pixels = rgba.ravel()
    image.filepath_raw = path
    image.file_format = mode
    if mode == "JPEG":
        scene.render.image_settings.quality = 88
    image.save()


def scaled(suffix, size):
    image = next(i for i in bpy.data.images if i.name.endswith(suffix)).copy()
    image.scale(size, size)
    return pixels(image)


orm = scaled("_ORM_2K", config["base"])
base = scaled("_BaseColor_2K", config["base"])
# Soft contact shading only: the game adds its own lighting and shadows.
save(np.clip(base[:, :, :3] * (0.6 + 0.4 * orm[:, :, :1]), 0, 1), os.path.join(out_dir, f"{name}_base.jpg"), "JPEG")
save(scaled("_Normal_OpenGL_2K", config["maps"])[:, :, :3], os.path.join(out_dir, f"{name}_normal.png"), "PNG")
save(scaled("_ORM_2K", config["maps"])[:, :, 1], os.path.join(out_dir, f"{name}_rough.png"), "PNG")

model = next(o for o in bpy.data.objects if o.type == "MESH")
for o in bpy.data.objects:
    o.select_set(False)
model.select_set(True)
bpy.context.view_layer.objects.active = model
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.data.objects if o.type == "MESH"]
before = after = 0
for part in parts:
    material = part.data.materials[part.data.polygons[0].material_index].name
    tris = sum(len(p.vertices) - 2 for p in part.data.polygons)
    before += tris
    keep = config["keep"].get(material, config["keep"]["default"])
    if material not in config["keep"] and tris < 2000:
        keep = min(1.0, keep * 4)
    bpy.context.view_layer.objects.active = part
    if keep < 1.0:
        modifier = part.modifiers.new("decimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = keep
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    modifier = part.modifiers.new("triangulate", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    after += len(part.data.polygons)
    print(f"{material:40s} -> {len(part.data.polygons):6d}")
print(f"{name}: triangles {before} -> {after}")

# Same "STG2" layout as the stage: header JSON, then meshes with position, normal, uv, indices.
groups = {}
for part in parts:
    mesh = part.data
    mesh.transform(part.matrix_world)
    loops = len(mesh.loops)
    co = np.empty(len(mesh.vertices) * 3, np.float32)
    mesh.vertices.foreach_get("co", co)
    corner = np.empty(loops, np.int32)
    mesh.loops.foreach_get("vertex_index", corner)
    normal = np.empty(loops * 3, np.float32)
    mesh.corner_normals.foreach_get("vector", normal)
    uv = np.empty(loops * 2, np.float32)
    mesh.uv_layers.active.data.foreach_get("uv", uv)
    co, normal, uv = co.reshape(-1, 3)[corner], normal.reshape(-1, 3), uv.reshape(-1, 2)
    position = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)
    normal = np.stack([normal[:, 0], normal[:, 2], -normal[:, 1]], 1)
    uv = np.stack([uv[:, 0], 1 - uv[:, 1]], 1)
    vertices, inverse = np.unique(np.concatenate([position, normal, uv], 1).round(5), axis=0, return_inverse=True)
    group = groups.setdefault(config.get("groups", {}).get(part.data.materials[0].name, "body"), [[], [], 0])
    group[0].append(vertices)
    group[1].append(inverse.reshape(-1) + group[2])
    group[2] += len(vertices)

with open(os.path.join(out_dir, f"{name.capitalize()}.bin"), "wb") as out:
    blob = b"{}"
    out.write(b"STG2" + struct.pack("<I", len(blob)) + blob + struct.pack("<I", len(groups)))
    for group_name, (vertex_lists, index_lists, _) in sorted(groups.items()):
        v, i = np.concatenate(vertex_lists).astype("<f4"), np.concatenate(index_lists).astype("<u4")
        out.write(struct.pack("<H", len(group_name)) + group_name.encode() + struct.pack("<II", len(v), len(i)))
        out.write(v[:, 0:3].tobytes() + v[:, 3:6].tobytes() + v[:, 6:8].tobytes() + i.tobytes())
        print(f"{group_name:5s} vertices {len(v):5d} triangles {len(i) // 3:5d} bounds {v[:, 0:3].min(0).round(3)} {v[:, 0:3].max(0).round(3)}")
