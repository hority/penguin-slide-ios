# Blender (4.3, headless) step for the editable stage:
#   blender -b P2-light-editable-2K.blend --python ci/bake-stage.py -- <out_dir>
# 1. Bakes the procedural + image materials of the stage mesh into one 1024 px atlas
#    (base colour with the ORM ambient occlusion multiplied in, tangent-space normal) and a
#    512 px roughness map from the ORM green channel.
# 2. Decimates each material with Blender's collapse decimator (UVs are interpolated) and
#    exports stage_decimated.glb (geometry only) for ci/convert-stage.py.
import os
import sys

import bpy
import numpy as np

out_dir = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out_dir, exist_ok=True)
KEEP = {"P2_Snow_White": 0.35, "P2_Thick_Cyan_Ice": 0.8, "P2_Warm_Wood_Grain": 0.5, "P2_Coral_Pink": 0.15, "P2_Slate_Stone": 0.7,
        "P2_Blank_Sign_Cream": 0.8, "P2_Rope_Natural": 0.25, "P2_Deck_Planks": 0.4, "P2_Slide_Polished_Ice": 1.0}
SIZE = 1024

stage = next(o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("tripo_node"))
for o in bpy.data.objects:
    o.select_set(False)
stage.select_set(True)
bpy.context.view_layer.objects.active = stage

# --- Bake -------------------------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
scene.render.bake.margin = 8


def bake(name, kind, colorspace, **settings):
    image = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    image.colorspace_settings.name = colorspace
    for material in stage.data.materials:
        nodes = material.node_tree.nodes
        node = nodes.new("ShaderNodeTexImage")
        node.image = image
        node.name = "BAKE_TARGET"
        nodes.active = node
    bpy.ops.object.bake(type=kind, **settings)
    for material in stage.data.materials:
        material.node_tree.nodes.remove(material.node_tree.nodes["BAKE_TARGET"])
    return image


def pixels(image):
    return np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)


def save(array, path, mode):
    from_array = bpy.data.images.new(os.path.basename(path), array.shape[1], array.shape[0], alpha=False)
    rgba = np.ones((array.shape[0], array.shape[1], 4), dtype=np.float32)
    rgba[:, :, :3] = array if array.ndim == 3 else array[:, :, None]
    from_array.pixels = rgba.ravel()
    from_array.filepath_raw = path
    from_array.file_format = mode
    if mode == "JPEG":
        scene.render.image_settings.quality = 88
    from_array.save()


base = bake("bake_base", "DIFFUSE", "sRGB", pass_filter={"COLOR"})
normal = bake("bake_normal", "NORMAL", "Non-Color", normal_space="TANGENT")
orm_image = next(i for i in bpy.data.images if "ORM" in i.name)
orm_image.scale(SIZE, SIZE)
orm = pixels(orm_image)
# Soft contact shading only: the game adds its own lighting, shadows and contact AO.
ao = 0.6 + 0.4 * orm[:, :, :1]
base_rgb = np.clip(pixels(base)[:, :, :3] * ao, 0, 1)
save(base_rgb, os.path.join(out_dir, "stage_base.jpg"), "JPEG")
save(pixels(normal)[:, :, :3], os.path.join(out_dir, "stage_normal.png"), "PNG")
orm_image.scale(512, 512)
save(pixels(orm_image)[:, :, 1], os.path.join(out_dir, "stage_rough.png"), "PNG")

# --- Decimate per material ----------------------------------------------------------------
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="MATERIAL")
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("tripo_node")]
before = after = 0
for part in parts:
    material = part.data.materials[part.data.polygons[0].material_index].name
    part.name = material
    before += sum(len(p.vertices) - 2 for p in part.data.polygons)
    bpy.context.view_layer.objects.active = part
    if KEEP[material] < 1.0:
        modifier = part.modifiers.new("decimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = KEEP[material]
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    modifier = part.modifiers.new("triangulate", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    tris = len(part.data.polygons)
    after += tris
    print(f"{material:24s} -> {tris:6d}")
print(f"triangles {before} -> {after}")

for o in bpy.data.objects:
    o.select_set(o in parts)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "stage_decimated.glb"), use_selection=True, export_format="GLB",
                          export_image_format="NONE", export_materials="EXPORT", export_normals=True, export_texcoords=True,
                          export_yup=True, export_apply=True)
