"""Model game assets in Blender and export them as .glb files into assets/models/.
Run with Blender's Python (bpy):   python tools/blender_assets.py [asset ...]

Material names match the game's material library (scripts/mats.gd), so Godot swaps in
the realistic PBR textures automatically when the model is loaded.
Blender is Z-up; glTF/Godot is Y-up. Blender +Y becomes Godot -Z (forward).
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models")
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    return m


def _finish(obj, material, bevel=0.0, segments=2):
    obj.data.materials.append(mat(material))
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    return obj


def box(name, size, loc, material, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, bevel)


def cyl(name, r, depth, loc, material, rot=(0, 0, 0), verts=16, bevel=0.0, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=[math.radians(a) for a in rot])
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, vertices=verts, location=loc, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    return _finish(o, material, bevel)


def torus(name, major, minor, loc, material, rot=(0, 0, 0), segs=24, arc=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segs, minor_segments=6, location=loc, rotation=[math.radians(a) for a in rot])
    o = bpy.context.active_object
    o.name = name
    return _finish(o, material)


def uv_all():
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=1.0)
        bpy.ops.object.mode_set(mode="OBJECT")
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))


def join_by_material():
    """One object per material = far fewer draw calls in the game."""
    groups = {}
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.data.materials:
            groups.setdefault(o.data.materials[0].name, []).append(o)
    for mname, objs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.active_object.name = mname


def export(name):
    uv_all()
    join_by_material()
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_materials="EXPORT", export_image_format="NONE")
    tris = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"exported {name}.glb  ({tris} faces)")


# ---------------------------------------------------------------- assets

def ladder(height=9.4, name="ladder"):
    """Industrial steel ladder with a safety cage (origin at the bottom centre, climbs along +Z)."""
    reset()
    w = 0.52
    for sx in (-w / 2, w / 2):
        box("rail", (0.05, 0.07, height), (sx, 0, height / 2), "metal", 0.008)
    n = int(height / 0.3)
    for i in range(n):
        cyl("rung", 0.017, w, (0, 0, 0.3 + i * 0.3), "metal", rot=(0, 90, 0), verts=10)
    # Wall brackets
    for z in (0.6, height / 2, height - 0.5):
        for sx in (-w / 2, w / 2):
            box("bracket", (0.04, 0.22, 0.05), (sx, 0.13, z), "rust", 0.005)
    # Safety cage hoops from 2.4 m up, with vertical straps
    z = 2.4
    while z < height + 0.9:
        bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.014, major_segments=20, minor_segments=5, location=(0, -0.3, z))
        hoop = bpy.context.active_object
        hoop.name = "hoop"
        # Cut the back half off (the ladder side stays open)
        bm = bmesh.new()
        bm.from_mesh(hoop.data)
        geom = [v for v in bm.verts if v.co.y > 0.2]
        bmesh.ops.delete(bm, geom=geom, context="VERTS")
        bm.to_mesh(hoop.data)
        bm.free()
        _finish(hoop, "metal")
        z += 0.9
    for ang in (-150, -110, -70, -30):
        x = math.cos(math.radians(ang)) * 0.38
        y = -0.3 + math.sin(math.radians(ang)) * 0.38
        box("strap", (0.04, 0.012, height - 2.4 + 0.8), (x, y, 2.4 + (height - 2.4 + 0.8) / 2 - 0.4), "metal")
    # Grab handles at the top
    for sx in (-w / 2, w / 2):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.3, minor_radius=0.02, major_segments=16, minor_segments=5, location=(sx, 0.3, height), rotation=(0, math.radians(90), 0))
        o = bpy.context.active_object
        _finish(o, "metal")
    export(name)


def rifle():
    """Suppressed carbine viewmodel. Barrel points along Blender +Y (Godot -Z). Optic centre at (0, 0.02, 0.086)."""
    reset()
    M, P = "gun_metal", "gun_polymer"
    box("upper", (0.052, 0.3, 0.06), (0, 0.0, 0.0), M, 0.006)
    box("lower", (0.048, 0.2, 0.055), (0, -0.03, -0.05), M, 0.006)
    box("magwell", (0.044, 0.07, 0.06), (0, 0.035, -0.09), M, 0.005)
    # Curved magazine: stacked slightly rotated segments
    for i in range(6):
        a = i * 4.0
        z = -0.12 - i * 0.03
        y = 0.035 + i * i * 0.0012 + i * 0.004
        box("mag", (0.034, 0.068, 0.034), (0, y, z), P, 0.004, rot=(a, 0, 0))
    box("grip", (0.036, 0.045, 0.1), (0, -0.075, -0.1), P, 0.008, rot=(-18, 0, 0))
    box("trigger_guard", (0.008, 0.06, 0.006), (0, -0.02, -0.088), M)
    # Buttstock (M4 style)
    box("buffer", (0.032, 0.14, 0.032), (0, -0.2, -0.005), M, 0.006)
    box("stock", (0.042, 0.16, 0.07), (0, -0.28, -0.02), P, 0.01)
    box("stock_pad", (0.045, 0.02, 0.1), (0, -0.365, -0.03), "gear", 0.006)
    box("cheek", (0.04, 0.1, 0.02), (0, -0.28, 0.022), P, 0.006)
    # Handguard: octagonal tube with rail on top and vent slots
    cyl("handguard", 0.032, 0.3, (0, 0.3, 0.004), P, rot=(90, 0, 22.5), verts=8, bevel=0.003)
    for i in range(8):
        box("vent", (0.07, 0.016, 0.01), (0, 0.19 + i * 0.03, 0.004), M, rot=(0, 90, 0))
    box("rail_top", (0.022, 0.56, 0.012), (0, 0.13, 0.037), M)
    for i in range(24):
        box("rail_slot", (0.024, 0.006, 0.004), (0, -0.13 + i * 0.022, 0.044), M)
    # Barrel + suppressor with grip rings
    cyl("barrel", 0.011, 0.14, (0, 0.52, 0.006), M, rot=(90, 0, 0), verts=12)
    cyl("suppressor", 0.021, 0.2, (0, 0.68, 0.006), M, rot=(90, 0, 0), verts=16, bevel=0.004)
    for i in range(6):
        cyl("supp_ring", 0.0225, 0.006, (0, 0.6 + i * 0.03, 0.006), M, rot=(90, 0, 0), verts=16)
    # Charging handle + ejection port + forward assist
    box("charging", (0.03, 0.02, 0.01), (0, -0.14, 0.03), M)
    box("port", (0.002, 0.06, 0.018), (0.027, 0.02, 0.005), "black")
    cyl("assist", 0.008, 0.02, (0.03, -0.06, 0.012), M, rot=(0, 90, 0), verts=10)
    # Red dot optic (tube) on a riser mount
    box("mount", (0.03, 0.05, 0.02), (0, 0.02, 0.052), M, 0.003)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.022, depth=0.07, vertices=20, location=(0, 0.02, 0.086), rotation=(math.radians(90), 0, 0))
    tube = bpy.context.active_object
    tube.name = "optic"
    # Hollow it so you can see through
    bm = bmesh.new()
    bm.from_mesh(tube.data)
    caps = [f for f in bm.faces if abs(f.normal.y) > 0.9]
    bmesh.ops.delete(bm, geom=caps, context="FACES_ONLY")
    bm.to_mesh(tube.data)
    bm.free()
    solid = tube.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = 0.003
    _finish(tube, M)
    box("optic_knob", (0.012, 0.014, 0.014), (0.024, 0.02, 0.086), M, 0.002)
    # Front vertical grip
    cyl("vgrip", 0.014, 0.08, (0, 0.33, -0.065), P, verts=12, bevel=0.003)
    export("rifle")


def container():
    """20 ft ISO shipping container (6.06 x 2.44 x 2.59 m), origin at the bottom centre, long axis = X."""
    reset()
    L, W, H = 6.06, 2.44, 2.59
    C = "container_paint"
    box("floor", (L, W, 0.12), (0, 0, 0.06), "rust")
    box("roof", (L, W, 0.06), (0, 0, H - 0.03), C)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box("post", (0.16, 0.16, H), (sx * (L / 2 - 0.08), sy * (W / 2 - 0.08), H / 2), C, 0.01)
            for z in (0.08, H - 0.08):
                box("casting", (0.18, 0.18, 0.12), (sx * (L / 2 - 0.09), sy * (W / 2 - 0.09), z), "rust")
    for sy in (-1, 1):
        box("rail_top", (L, 0.12, 0.12), (0, sy * (W / 2 - 0.06), H - 0.1), C)
        box("rail_bot", (L, 0.14, 0.16), (0, sy * (W / 2 - 0.07), 0.12), C)
        # Corrugated side walls: alternating in/out panels
        n = 22
        pw = (L - 0.4) / n
        for i in range(n):
            x = -L / 2 + 0.2 + pw * (i + 0.5)
            depth = 0.05 if i % 2 == 0 else 0.02
            box("rib", (pw * 0.98, depth, H - 0.36), (x, sy * (W / 2 - depth / 2), H / 2), C)
    # Front wall (corrugated) and door end
    for i in range(8):
        y = -W / 2 + 0.2 + (W - 0.4) / 8 * (i + 0.5)
        box("front_rib", (0.04 if i % 2 else 0.02, (W - 0.4) / 8, H - 0.36), (-L / 2 + 0.03, y, H / 2), C)
    for sy in (-1, 1):
        box("door", (0.04, W / 2 - 0.12, H - 0.3), (L / 2 - 0.02, sy * (W / 4 - 0.02), H / 2), C, 0.005)
        for k in (-0.35, 0.35):
            cyl("lock_rod", 0.018, H - 0.2, (L / 2 + 0.02, sy * (W / 4 - 0.02) + k * (W / 4) / 0.7, H / 2), "metal", verts=8)
            box("lock_handle", (0.03, 0.03, 0.3), (L / 2 + 0.05, sy * (W / 4 - 0.02) + k * (W / 4) / 0.7, 1.2), "metal", rot=(0, 0, 0))
        for z in (0.5, H / 2, H - 0.5):
            box("hinge", (0.06, 0.08, 0.1), (L / 2 + 0.01, sy * (W / 2 - 0.1), z), "rust")
    export("container")


def drum():
    """55 gallon steel drum."""
    reset()
    cyl("drum", 0.29, 0.88, (0, 0, 0.44), "drum_paint", verts=24)
    for z in (0.02, 0.3, 0.58, 0.86):
        cyl("rib", 0.3, 0.025, (0, 0, z), "drum_paint", verts=24)
    cyl("bung", 0.03, 0.02, (0.15, 0.05, 0.885), "metal", verts=10)
    export("drum")


def pallet():
    reset()
    for i in range(7):
        box("top", (1.2, 0.1, 0.02), (0, -0.45 + i * 0.15, 0.134), "wood", 0.003)
    for y in (-0.45, 0, 0.45):
        box("stringer", (1.2, 0.1, 0.08), (0, y, 0.084), "wood", 0.003)
    for i in range(3):
        box("bottom", (1.2, 0.1, 0.02), (0, -0.45 + i * 0.45, 0.034), "wood", 0.003)
    for x in (-0.55, 0, 0.55):
        for y in (-0.45, 0, 0.45):
            box("block", (0.1, 0.1, 0.06), (x, y, 0.074), "wood")
    export("pallet")


def crate():
    reset()
    s = 1.1
    box("core", (s - 0.04, s - 0.04, s - 0.04), (0, 0, s / 2), "wood")
    for axis in range(3):
        for sgn in (-1, 1):
            for k in (-1, 1):
                if axis == 0:
                    box("frame", (0.04, s, 0.1), (sgn * s / 2, 0, s / 2 + k * (s / 2 - 0.05)), "wood", 0.004)
                    box("frame", (0.04, 0.1, s), (sgn * s / 2, k * (s / 2 - 0.05), s / 2), "wood", 0.004)
                elif axis == 1:
                    box("frame", (s, 0.04, 0.1), (0, sgn * s / 2, s / 2 + k * (s / 2 - 0.05)), "wood", 0.004)
                    box("frame", (0.1, 0.04, s), (k * (s / 2 - 0.05), sgn * s / 2, s / 2), "wood", 0.004)
    for sgn in (-1, 1):
        box("diag", (0.04, s * 1.3, 0.1), (sgn * s / 2, 0, s / 2), "wood", 0.004, rot=(45, 0, 0))
    export("crate")


def jersey_barrier():
    """Concrete road barrier with the classic sloped profile, extruded 3 m along X."""
    reset()
    prof = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.18, 0.33), (0.08, 0.81), (-0.08, 0.81), (-0.18, 0.33), (-0.3, 0.08)]
    mesh = bpy.data.meshes.new("barrier")
    bm = bmesh.new()
    front = [bm.verts.new((-1.5, y, z)) for y, z in prof]
    back = [bm.verts.new((1.5, y, z)) for y, z in prof]
    bm.faces.new(front[::-1])
    bm.faces.new(back)
    n = len(prof)
    for i in range(n):
        bm.faces.new((front[i], front[(i + 1) % n], back[(i + 1) % n], back[i]))
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("barrier", mesh)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    _finish(o, "concrete", 0.01)
    for x in (-1.1, 1.1):
        box("lift_slot", (0.2, 0.62, 0.08), (x, 0, 0.05), "black")
    export("jersey_barrier")


def sandbags():
    """A 2.4 m wall of stacked sandbags (3 rows)."""
    reset()
    for row in range(3):
        count = 6 - (row % 2)
        for i in range(count):
            x = -1.2 + 0.2 + i * 0.44 + (0.22 if row % 2 else 0)
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.25, segments=12, ring_count=8, location=(x, 0, 0.1 + row * 0.19))
            b = bpy.context.active_object
            b.scale = (0.9, 0.55, 0.38)
            bpy.ops.object.transform_apply(scale=True)
            _finish(b, "sandbag")
    export("sandbags")


def floodlight_head():
    reset()
    box("frame", (2.2, 0.12, 0.12), (0, 0, 0), "metal")
    for i in range(4):
        x = -0.8 + i * 0.53
        box("housing", (0.42, 0.25, 0.32), (x, -0.08, 0.0), "metal", 0.02)
        box("lens", (0.36, 0.01, 0.26), (x, -0.21, 0.0), "lamp_glass")
    export("floodlight_head")


def fallen_tree():
    """Fallen pine trunk with snapped branch stubs, lying along X."""
    reset()
    cyl("trunk", 0.32, 9.0, (0, 0, 0.3), "bark", rot=(0, 90, 0), verts=14, r2=0.14)
    cyl("root", 0.55, 0.5, (-4.6, 0, 0.35), "bark", rot=(0, 90, 0), verts=14, r2=0.3)
    import random
    random.seed(4)
    for i in range(12):
        x = random.uniform(-3.5, 4.0)
        a = random.uniform(0, 360)
        cyl("stub", 0.04, random.uniform(0.3, 0.9), (x, math.cos(math.radians(a)) * 0.35, 0.3 + math.sin(math.radians(a)) * 0.35), "bark", rot=(a - 90, random.uniform(-30, 30), 0), verts=6, r2=0.015)
    export("fallen_tree")


def _wheel(x, y, r=0.5, w=0.32):
    cyl("tire", r, w, (x, y, r), "black", rot=(0, 90, 0), verts=20, bevel=0.04)
    cyl("rim", r * 0.55, w + 0.02, (x, y, r), "metal", rot=(0, 90, 0), verts=12)
    cyl("hub", r * 0.18, w + 0.06, (x, y, r), "rust", rot=(0, 90, 0), verts=8)


def supply_truck():
    """Military supply truck. Front (cab) toward Blender +Y = Godot -Z. Bed floor at z = 1.15, centred on y = -2.1."""
    reset()
    P = "truck_paint"
    box("chassis", (1.1, 7.6, 0.3), (0, -0.6, 0.85), "gun_metal")
    # Cab with sloped bonnet
    box("cab", (2.3, 1.9, 1.7), (0, 2.25, 1.95), P, 0.06)
    box("bonnet", (2.1, 1.3, 0.9), (0, 3.6, 1.45), P, 0.08)
    box("bonnet_slope", (2.05, 0.9, 0.5), (0, 3.3, 1.95), P, 0.05, rot=(18, 0, 0))
    box("grille", (1.5, 0.05, 0.7), (0, 4.26, 1.35), "gun_metal")
    for i in range(7):
        box("grille_bar", (1.45, 0.06, 0.04), (0, 4.28, 1.08 + i * 0.09), "metal")
    box("bumper", (2.3, 0.2, 0.25), (0, 4.35, 0.9), "gun_metal", 0.02)
    for sx in (-0.75, 0.75):
        cyl("headlight", 0.13, 0.08, (sx, 4.29, 1.62), "lamp_glass", rot=(90, 0, 0), verts=16)
    box("windscreen", (2.0, 0.05, 0.75), (0, 3.2, 2.35), "glass", rot=(-20, 0, 0))
    for sx in (-1.16, 1.16):
        box("side_window", (0.04, 1.0, 0.6), (sx, 2.4, 2.35), "glass")
        box("mirror_arm", (0.35, 0.04, 0.04), (sx * 1.1, 3.05, 2.4), "gun_metal")
        box("mirror", (0.05, 0.12, 0.25), (sx * 1.25, 3.05, 2.4), "gun_metal")
        box("step", (0.3, 0.5, 0.06), (sx * 1.0, 2.3, 0.7), "gun_metal")
        box("fender", (0.35, 1.1, 0.15), (sx * 1.02, 3.55, 1.12), P, 0.03)
    cyl("exhaust", 0.07, 1.6, (1.15, 1.35, 2.1), "rust", verts=10)
    # Flatbed with drop sides (wooden slats)
    box("bed_floor", (2.4, 4.6, 0.12), (0, -2.1, 1.09), "wood")
    for sx in (-1.18, 1.18):
        for k in range(3):
            box("slat", (0.06, 4.6, 0.18), (sx, -2.1, 1.3 + k * 0.24), "wood", 0.01)
        for yy in (-4.3, -2.1, 0.1):
            box("stake", (0.08, 0.1, 0.85), (sx, yy, 1.5), P)
    for k in range(3):
        box("tail_slat", (2.4, 0.06, 0.18), (0, -4.38, 1.3 + k * 0.24), "wood", 0.01)
    box("headboard", (2.4, 0.1, 1.1), (0, 0.15, 1.65), P)
    # Wheels: single front axle, double rear axle
    for sx in (-1.05, 1.05):
        _wheel(sx, 3.4, 0.52, 0.34)
        _wheel(sx, -1.4, 0.52, 0.4)
        _wheel(sx, -2.8, 0.52, 0.4)
    box("tail_light_l", (0.2, 0.04, 0.1), (-0.95, -4.42, 1.0), "tail_light")
    box("tail_light_r", (0.2, 0.04, 0.1), (0.95, -4.42, 1.0), "tail_light")
    export("supply_truck")


def technical():
    """Pickup truck ('technical'). Front toward +Y. Gun mount point in the bed at (0, -1.2, 1.35)."""
    reset()
    P = "truck_paint"
    box("body_lower", (2.0, 5.0, 0.7), (0, 0, 0.85), P, 0.06)
    box("cab", (1.9, 1.7, 0.9), (0, 0.55, 1.65), P, 0.1)
    box("bonnet", (1.95, 1.5, 0.35), (0, 1.8, 1.35), P, 0.06)
    box("windscreen", (1.75, 0.04, 0.7), (0, 1.35, 1.7), "glass", rot=(-28, 0, 0))
    box("rear_window", (1.6, 0.04, 0.45), (0, -0.31, 1.75), "glass")
    for sx in (-0.96, 0.96):
        box("door_window", (0.04, 1.0, 0.45), (sx, 0.55, 1.75), "glass")
    box("grille", (1.4, 0.05, 0.35), (0, 2.52, 1.1), "gun_metal")
    box("bullbar", (1.9, 0.12, 0.5), (0, 2.65, 1.0), "gun_metal", 0.03)
    for sx in (-0.65, 0.65):
        box("headlight", (0.3, 0.04, 0.14), (sx, 2.52, 1.33), "lamp_glass")
    # Open bed
    box("bed_floor", (1.8, 2.1, 0.06), (0, -1.35, 1.2), "gun_metal")
    for sx in (-0.95, 0.95):
        box("bed_side", (0.08, 2.1, 0.45), (sx, -1.35, 1.45), P)
    box("tailgate", (1.9, 0.08, 0.45), (0, -2.45, 1.45), P)
    box("roll_bar", (1.8, 0.08, 0.08), (0, -0.45, 2.3), "gun_metal")
    for sx in (-0.88, 0.88):
        box("roll_bar_leg", (0.08, 0.08, 0.95), (sx, -0.45, 1.85), "gun_metal")
    for sx in (-0.95, 0.95):
        _wheel(sx, 1.6, 0.42, 0.3)
        _wheel(sx, -1.5, 0.42, 0.3)
    export("technical")


def helicopter():
    """Utility helicopter hull (rotors are animated in game). Nose toward +Y."""
    reset()
    P = "heli_paint"
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=24, ring_count=12, location=(0, 0.6, 1.7))
    body = bpy.context.active_object
    body.scale = (1.25, 3.2, 1.15)
    bpy.ops.object.transform_apply(scale=True)
    _finish(body, P)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=20, ring_count=10, location=(0, 3.0, 1.75))
    nose = bpy.context.active_object
    nose.scale = (1.05, 1.1, 0.85)
    bpy.ops.object.transform_apply(scale=True)
    _finish(nose, "glass")
    cyl("tail_boom", 0.38, 7.0, (0, -5.4, 2.2), P, rot=(90, 0, 0), verts=14, r2=0.18)
    box("tail_fin", (0.12, 1.2, 1.8), (0, -8.7, 3.0), P, 0.03, rot=(-15, 0, 0))
    box("stabilizer", (2.2, 0.6, 0.08), (0, -8.2, 2.3), P, 0.02)
    box("engine", (1.3, 2.4, 0.7), (0, 0.2, 3.0), P, 0.15)
    cyl("mast", 0.12, 0.6, (0, 0.3, 3.55), "gun_metal", verts=10)
    cyl("hub", 0.35, 0.2, (0, 0.3, 3.85), "gun_metal", verts=12)
    for sx in (-1.0, 1.0):
        box("skid", (0.12, 4.6, 0.12), (sx * 1.15, 0.6, 0.12), "gun_metal", 0.03)
        for yy in (-0.6, 1.8):
            box("strut", (0.1, 0.1, 0.8), (sx * 1.05, yy, 0.5), "gun_metal", rot=(0, sx * -20, 0))
        box("side_door", (0.05, 1.6, 1.1), (sx * 1.23, 0.4, 1.6), P)
        box("door_window", (0.04, 0.8, 0.5), (sx * 1.26, 0.6, 1.85), "glass")
    export("helicopter")


ALL = ["supply_truck", "technical", "helicopter", "ladder", "rifle", "container", "drum", "pallet", "crate", "jersey_barrier", "sandbags", "floodlight_head", "fallen_tree"]

if __name__ == "__main__":
    todo = [a for a in sys.argv[1:] if a in ALL] or ALL
    for a in todo:
        globals()[a]()
