# Lays out the editable stage for the game (second step after ci/bake-stage.py):
#   blender -b P2-light-editable-2K.blend --python ci/bake-stage.py -- build/stage
#   python3 ci/convert-stage.py build/stage HelloFlight/Stage
# Input: build/stage/stage_decimated.glb (per-material meshes, already decimated in Blender)
#        and the baked stage_base.jpg / stage_normal.png / stage_rough.png.
# Output: HelloFlight/Stage/IcyStage.bin (meshes + layout metadata, "STG2") and the textures.
#
# The mesh is split into connected parts and sorted into the island (with the slide and
# platform), three answer floes and their signs; one floe (without its rocks) and its sign
# are kept and shared by all three answers. The island is rotated so the slide runs
# diagonally towards the camera, and dropped so its ice sits at the waterline. The floe is
# shrunk to fit the play layout; the sign is turned square and enlarged for readability. The slide centreline
# becomes the gameplay sliding path.
import json
import shutil
import math
import struct
import sys

import numpy as np
import trimesh
from scipy import ndimage

MATERIAL_KINDS = {"P2_Snow_White": "snow", "P2_Thick_Cyan_Ice": "ice", "P2_Warm_Wood_Grain": "wood", "P2_Coral_Pink": "coral",
                  "P2_Slate_Stone": "stone", "P2_Blank_Sign_Cream": "sign", "P2_Rope_Natural": "rope", "P2_Deck_Planks": "deck",
                  "P2_Slide_Polished_Ice": "slide"}
HEADING = math.radians(25)      # slide direction: from +z, turned towards +x
FLOE_SCALE = 0.62               # model floes are ~1.45 m wide; the play layout wants ~0.9 m
BOARD_SCALE = 1.8               # signs (incl. posts) relative to the model, for readable letters
BOARD_BACK = -0.24              # sign position on the floe (z), behind where the character lands
FLOE_TOP = 0.11                 # floe snow top above the floe root, as the game expects
LIP = np.array([0.0, -0.9])     # where the slide ends (x, z) in the game


def gltf_uv_top_left(mesh):
    # trimesh converts glTF UVs to a bottom-left origin; SceneKit uses glTF's top-left origin.
    uv = np.array(mesh.visual.uv, dtype=np.float64)
    uv[:, 1] = 1.0 - uv[:, 1]
    return uv


def components(mesh):
    welded = trimesh.Trimesh(mesh.vertices, mesh.faces, process=True)
    return trimesh.graph.connected_component_labels(welded.face_adjacency, node_count=len(mesh.faces))


def submesh(mesh, uv, faces):
    used, inverse = np.unique(mesh.faces[faces], return_inverse=True)
    return mesh.vertices[used], mesh.vertex_normals[used], uv[used], inverse.reshape(-1, 3)


def rotation_y(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def main(source_dir, out_dir):
    scene = trimesh.load(f"{source_dir}/stage_decimated.glb", force="scene")
    parts = {}
    for node in scene.graph.nodes_geometry:
        world, geometry = scene.graph[node]
        mesh = scene.geometry[geometry].copy()
        mesh.apply_transform(world)
        parts[MATERIAL_KINDS[mesh.visual.material.name]] = (mesh, gltf_uv_top_left(mesh), components(mesh))

    # Floes: the three ice slabs below the island.
    ice_mesh, _, ice_labels = parts["ice"]
    slabs = []
    for label in np.unique(ice_labels):
        bounds = trimesh.Trimesh(ice_mesh.vertices, ice_mesh.faces[ice_labels == label]).bounds
        if (bounds[1] - bounds[0])[0] < 2.0:
            slabs.append(((bounds[0] + bounds[1]) / 2))
    slabs.sort(key=lambda c: c[0])
    assert len(slabs) == 3, slabs

    # Sort every connected part into island / floe k / board k.
    buckets = {}
    floe_info = [{"center": c, "top": -1.0} for c in slabs]
    pending = []
    for kind, (mesh, uv, labels) in parts.items():
        for label in np.unique(labels):
            faces = np.nonzero(labels == label)[0]
            b = trimesh.Trimesh(mesh.vertices, mesh.faces[faces]).bounds
            center, size = (b[0] + b[1]) / 2, b[1] - b[0]
            owner = None
            if kind != "slide" and max(size[0], size[2]) < 1.7 and center[1] < 1.5:
                distances = [np.hypot(*(center - f["center"])[[0, 2]]) for f in floe_info]
                if min(distances) < 0.85:
                    owner = int(np.argmin(distances))
            pending.append((kind, faces, center, b, owner))
            if owner is not None and kind == "snow" and size[0] > 1.0:
                floe_info[owner]["top"] = b[1][1]
    signs = {}
    for kind, faces, center, b, owner in pending:
        if owner is not None and kind == "sign":
            signs[owner] = (b[0] + b[1]) / 2
    for kind, faces, center, b, owner in pending:
        to_sign = None if owner is None else np.hypot(*(center - signs[owner])[[0, 2]])
        if owner is None:
            key = "island"
        elif kind in ("sign", "wood") and center[1] > floe_info[owner]["top"] + 0.04 and to_sign < 0.4 \
                or kind == "snow" and center[1] > signs[owner][1] and to_sign < 0.25:
            # The sign, its posts and the snow caps on the posts move together (bounce, sink).
            key = f"board{owner}"
        elif center[1] > floe_info[owner]["top"] + 0.3:
            # A big snow lump behind the sign, on the back post: left out so the face stays clear.
            continue
        elif kind == "stone" or kind == "snow" and max(b[1] - b[0]) < 0.35 and center[1] > floe_info[owner]["top"] + 0.03:
            # No rocks (and their snow caps) on the answer floes: the floe stays a clean stage.
            continue
        else:
            key = f"floe{owner}"
        buckets.setdefault((key, kind), []).append(faces)

    # Island placement: rotate, put the ice base at the waterline and the slide end at LIP.
    rotation = rotation_y(HEADING)
    slide_mesh = parts["slide"][0]
    island_ice_bottom = min(trimesh.Trimesh(ice_mesh.vertices, ice_mesh.faces[ice_labels == l]).bounds[0][1]
                            for l in np.unique(ice_labels)
                            if (lambda bb: (bb[1] - bb[0])[0] >= 2.0)(trimesh.Trimesh(ice_mesh.vertices, ice_mesh.faces[ice_labels == l]).bounds))
    slide_points = slide_mesh.vertices
    end = slide_points[np.argmax(slide_points[:, 2])]
    rotated_end = rotation @ end
    offset = np.array([LIP[0] - rotated_end[0], -island_ice_bottom - 0.05, LIP[1] - rotated_end[2]])

    def to_island(p):
        return p @ rotation.T + offset

    # Slide centreline (inner trough surface) in game coordinates.
    sx = np.median(slide_points[:, 0])
    z0, z1 = slide_points[:, 2].min(), slide_points[:, 2].max()
    track = []
    for z in np.linspace(z0 + 0.04 * (z1 - z0), z1 - 0.02 * (z1 - z0), 41):
        near = slide_points[(np.abs(slide_points[:, 2] - z) < 0.05) & (np.abs(slide_points[:, 0] - sx) < 0.07)]
        track.append([sx, near[:, 1].max(), z])
    track = np.array(track)
    track[:, 1] = ndimage.uniform_filter1d(track[:, 1], 5, mode="nearest")
    track = to_island(track)
    # Stand on the deck, behind the top of the slide.
    deck_mesh, _, deck_labels = parts["deck"]
    deck = max((trimesh.Trimesh(deck_mesh.vertices, deck_mesh.faces[deck_labels == l]) for l in np.unique(deck_labels)),
               key=lambda m: (m.bounds[1] - m.bounds[0])[2])
    stand = to_island(np.array([(deck.bounds[0][0] + deck.bounds[1][0]) / 2, deck.bounds[1][1], (deck.bounds[0][2] + deck.bounds[1][2]) / 2]))
    snow_main = max((trimesh.Trimesh(parts["snow"][0].vertices, parts["snow"][0].faces[parts["snow"][2] == l]) for l in np.unique(parts["snow"][2])),
                    key=lambda m: len(m.faces))
    island_top = float(np.percentile(to_island(snow_main.vertices)[:, 1], 70))
    island_center = to_island((snow_main.bounds[0] + snow_main.bounds[1]) / 2)
    island_half = (snow_main.bounds[1] - snow_main.bounds[0]) / 2

    # The three floes share one model: the lightest floe, and its sign.
    pick = min(range(3), key=lambda k: sum(len(f) for (key, _), faces in buckets.items() if key == f"floe{k}" for f in faces))
    info = floe_info[pick]
    floe_origin = np.array([info["center"][0], info["top"], info["center"][2]])
    # The sign is turned in the model; turn the board so its face looks straight down +z (the game
    # turns it towards the camera). The face normal is the flattest direction of the sign's points.
    sign_mesh, _, _ = parts["sign"]
    sign_points = np.concatenate([sign_mesh.vertices[np.unique(sign_mesh.faces[f])] for f in buckets[(f"board{pick}", "sign")]])
    normal = np.linalg.svd(sign_points - sign_points.mean(0), full_matrices=False)[2][2]
    normal *= np.sign(normal[2]) or 1.0
    board_rotation = rotation_y(-math.atan2(normal[0], normal[2]))
    # Upright at the back of the floe, so the character lands in front of it.
    board_root = np.array([0, (signs[pick] - floe_origin)[1] * BOARD_SCALE + FLOE_TOP, BOARD_BACK])

    meshes = {}
    meta = {
        "track": track.round(4).tolist(), "stand": stand.round(4).tolist(), "islandTop": round(island_top, 4),
        "island": {"center": [round(island_center[0], 4), round(island_center[2], 4)], "half": [round(island_half[0], 4), round(island_half[2], 4)], "angle": round(HEADING, 5)},
        "floe": {"board": board_root.round(4).tolist(), "radius": round(0.72 * FLOE_SCALE, 4)},
    }
    transforms = {"island": to_island,
                  "floe": lambda p: (p - floe_origin) * FLOE_SCALE + np.array([0, FLOE_TOP, 0]),
                  "board": lambda p: (p - signs[pick]) @ board_rotation.T * BOARD_SCALE}
    renamed = {f"floe{pick}": "floe", f"board{pick}": "board", "island": "island"}
    buckets = {(renamed[key], kind): faces for (key, kind), faces in buckets.items() if key in renamed}

    for (key, kind), face_lists in sorted(buckets.items()):
        mesh, uv, _ = parts[kind]
        faces = np.concatenate(face_lists)
        v, n, t, f = submesh(mesh, uv, faces)
        v = transforms[key](v)
        if key == "island":
            n = n @ rotation.T
        elif key == "board":
            n = n @ board_rotation.T
        if key == "board" and kind == "sign":
            # The quiz face goes on the sign's front (towards +z, the camera side). The panel is
            # pillowy; press its front flat so the face plane sits just in front of all of it.
            tri = trimesh.Trimesh(v, f, process=False)
            front = tri.face_normals[:, 2] > 0.6
            pts = tri.triangles[front].reshape(-1, 3)
            lo, hi = pts.min(0), pts.max(0)
            flat = np.percentile(pts[:, 2], 30)
            pressed = v[:, 2] > flat
            v[pressed, 2] = flat
            n[pressed] = [0, 0, 1]
            size = (hi - lo)[:2] * 0.84
            center = np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, flat + 0.006])
            meta["floe"]["face"] = {"center": center.round(4).tolist(), "normal": [0, 0, 1], "size": size.round(4).tolist()}
        group = meshes.setdefault(key, [[], [], [], [], 0])
        group[0].append(v); group[1].append(n); group[2].append(t); group[3].append(f + group[4]); group[4] += len(v)

    blob = json.dumps(meta).encode()
    with open(f"{out_dir}/IcyStage.bin", "wb") as out:
        out.write(b"STG2" + struct.pack("<I", len(blob)) + blob + struct.pack("<I", len(meshes)))
        for key, (vs, ns, ts, fs, _) in sorted(meshes.items()):
            p, n, t, i = (np.concatenate(x) for x in (vs, ns, ts, fs))
            name = key.encode()
            out.write(struct.pack("<H", len(name)) + name + struct.pack("<II", len(p), i.size))
            out.write(p.astype("<f4").tobytes() + n.astype("<f4").tobytes() + t.astype("<f4").tobytes() + i.astype("<u4").tobytes())
            print(f"{key:8s} vertices {len(p):6d} triangles {i.size // 3:6d}")
    print(json.dumps({k: meta[k] for k in ("stand", "islandTop", "island")}), "track", meta["track"][0], "->", meta["track"][-1])

    for name in ("stage_base.jpg", "stage_normal.png", "stage_rough.png"):
        shutil.copy(f"{source_dir}/{name}", f"{out_dir}/{name}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
