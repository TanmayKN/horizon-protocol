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


def box(name, size, loc, material, bevel=0.0, rot=(0, 0, 0), segs=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=[math.radians(r) for r in rot])
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material, bevel, segs)


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
    # Put every part's origin at the model origin so shaders see real model-space heights
    bpy.context.scene.cursor.location = (0, 0, 0)
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.parent is None:
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.origin_set(type="ORIGIN_CURSOR")


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


def _tire(x, y, r=0.56, w=0.38, dual=False):
    """Off-road tyre with chunky tread blocks, dished steel rim and lug nuts."""
    offs = (-0.21, 0.21) if dual else (0.0,)
    for o in offs:
        cx = x + o * (1 if x > 0 else -1)
        tw = 0.36 if dual else w
        cyl("tire", r - 0.04, tw, (cx, y, r), "black", rot=(0, 90, 0), verts=28, bevel=0.05)
        # tread lugs, alternating chevrons
        n = 26
        for i in range(n):
            a = i / n * math.tau
            side = 1 if i % 2 == 0 else -1
            box("tread", (tw * 0.45, 0.13, 0.06), (cx + side * tw * 0.22, y + math.cos(a) * (r - 0.02), r + math.sin(a) * (r - 0.02)),
                "black", 0.012, rot=(math.degrees(a) + 90, 0, 0))
        cyl("sidewall", r - 0.12, tw + 0.01, (cx, y, r), "black", rot=(0, 90, 0), verts=24)
    face = x + (max(offs) + 0.2) * (1 if x > 0 else -1)
    s = 1 if x > 0 else -1
    cyl("rim", r * 0.58, 0.06, (face - s * 0.02, y, r), "rim_paint", rot=(0, 90, 0), verts=20, bevel=0.01)
    cyl("rim_dish", r * 0.36, 0.1, (face, y, r), "rim_paint", rot=(0, 90, 0), verts=16)
    cyl("hub", r * 0.16, 0.2, (face + s * 0.04, y, r), "gun_metal", rot=(0, 90, 0), verts=10, bevel=0.01)
    for i in range(8):
        a = i / 8 * math.tau
        cyl("lug", 0.025, 0.08, (face + s * 0.05, y + math.cos(a) * r * 0.26, r + math.sin(a) * r * 0.26), "metal", rot=(0, 90, 0), verts=6)


def _arch(name, cx, cy, cz, r, width, thick, material, a0=0, a1=180, segs=12):
    """Curved wheel-arch fender made of short segments (arc in the Y/Z plane)."""
    for i in range(segs):
        a = math.radians(a0 + (a1 - a0) * (i + 0.5) / segs)
        seg_len = r * math.radians(a1 - a0) / segs * 1.08
        box(name, (width, seg_len, thick), (cx, cy + math.cos(a) * r, cz + math.sin(a) * r), material, 0.01, rot=(math.degrees(a) + 90, 0, 0))


def _tube(name, p1, p2, r, material, verts=10):
    p1 = Vector(p1); p2 = Vector(p2)
    d = p2 - p1
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=verts, location=(p1 + p2) / 2)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    return _finish(o, material)


def supply_truck():
    """6x6 military cargo truck. Front toward Blender +Y (Godot -Z).
    Bed floor top at z = 1.15 centred on y = -2.1. Driver eye ~ (-0.5, 2.05, 2.58). Cab interior is modelled."""
    reset()
    P = "truck_paint"
    # ---- chassis
    for sx in (-0.46, 0.46):
        box("rail", (0.12, 8.9, 0.3), (sx, -0.35, 0.95), "gun_metal", 0.01)
    for yy in (3.9, 2.2, 0.6, -1.0, -2.2, -3.6, -4.6):
        box("crossmember", (0.92, 0.1, 0.18), (0, yy, 0.95), "gun_metal")
    for yy in (3.3, -1.55, -2.95):
        cyl("axle", 0.09, 1.9, (0, yy, 0.56), "gun_metal", rot=(0, 90, 0), verts=12)
        _ball = bpy.ops.mesh.primitive_uv_sphere_add(radius=0.24, location=(0.08, yy, 0.56), segments=16, ring_count=10)
        o = bpy.context.active_object; o.name = "diff"; o.scale = (1.0, 0.8, 0.9); _finish(o, "gun_metal")
        for sx in (-0.5, 0.5):
            box("leaf_spring", (0.1, 1.3, 0.1), (sx, yy, 0.76), "gun_metal", 0.02)
    cyl("driveshaft", 0.05, 4.6, (0.08, 0.9, 0.62), "gun_metal", rot=(90, 0, 0), verts=8)
    # ---- front end
    box("bumper", (2.5, 0.28, 0.3), (0, 4.52, 0.95), "gun_metal", 0.03)
    for sx in (-0.9, 0.9):
        torus("tow_hook", 0.1, 0.03, (sx, 4.7, 0.95), "rust", rot=(0, 90, 0), segs=12)
    cyl("winch", 0.14, 1.0, (0, 4.5, 1.2), "gun_metal", rot=(0, 90, 0), verts=14)
    box("winch_frame", (1.3, 0.3, 0.1), (0, 4.5, 1.02), "gun_metal")
    # engine housing: bonnet tapers toward the front
    box("bonnet_body", (1.55, 1.7, 0.8), (0, 3.62, 1.55), P, 0.05)
    box("bonnet_top", (1.5, 1.72, 0.14), (0, 3.62, 2.0), P, 0.05, rot=(-2.5, 0, 0))
    for k in range(9):
        box("bonnet_louver", (0.02, 0.8, 0.08), (0.79, 3.4 - 0.0, 1.55 + (k - 4) * 0.06), "gun_metal") if False else None
    for sx in (-0.785, 0.785):
        for k in range(7):
            box("louver", (0.03, 0.7, 0.035), (sx, 3.55, 1.45 + k * 0.065), "gun_metal", rot=(0, 0, 0))
    # grille: frame + vertical bars
    box("grille_frame", (1.45, 0.1, 0.9), (0, 4.47, 1.52), P, 0.04)
    box("grille_back", (1.2, 0.05, 0.7), (0, 4.45, 1.52), "black")
    for i in range(11):
        box("grille_bar", (0.045, 0.08, 0.72), (-0.55 + i * 0.11, 4.52, 1.52), "gun_metal", 0.01)
    # front fenders: flat-topped military wings with curved arch
    for sx in (-1.0, 1.0):
        _arch("fender_arch", sx, 3.3, 0.56, 0.72, 0.52, 0.04, P, a0=0, a1=180, segs=12)
        box("fender_top", (0.52, 1.25, 0.05), (sx, 3.45, 1.3), P, 0.02)
        box("fender_step", (0.5, 0.5, 0.05), (sx, 2.55, 0.88), "gun_metal")
        cyl("headlight_bucket", 0.15, 0.16, (sx * 0.9, 4.05, 1.48), P, rot=(90, 0, 0), verts=18, bevel=0.01)
        cyl("headlight", 0.12, 0.04, (sx * 0.9, 4.14, 1.48), "lamp_glass", rot=(90, 0, 0), verts=18)
        torus("headlight_guard", 0.15, 0.012, (sx * 0.9, 4.2, 1.48), "gun_metal", rot=(90, 0, 0), segs=16)
        box("blackout_light", (0.12, 0.05, 0.06), (sx * 0.62, 4.06, 1.4), "tail_light")
        box("marker_light", (0.06, 0.04, 0.05), (sx * 0.95, 3.9, 1.36), "lamp_glass")
    # ---- cab (hollow shell so the driver sees out)
    CX, CY0, CY1, CZ0, CZ1 = 1.2, 1.3, 2.85, 1.35, 2.9
    box("cab_floor", (2.4, CY1 - CY0, 0.08), (0, (CY0 + CY1) / 2, CZ0), P)
    box("firewall", (2.4, 0.08, 0.8), (0, CY1, CZ0 + 0.4), P, 0.02)
    box("cowl", (2.4, 0.35, 0.08), (0, CY1 + 0.15, 2.12), P, 0.03, rot=(-8, 0, 0))
    box("cab_back", (2.4, 0.08, CZ1 - CZ0), (0, CY0, (CZ0 + CZ1) / 2), P, 0.02)
    box("rear_window", (0.9, 0.04, 0.35), (0, CY0 - 0.03, 2.5), "glass")
    box("roof", (2.46, CY1 - CY0 + 0.2, 0.08), (0, (CY0 + CY1) / 2 + 0.05, CZ1), P, 0.04)
    for k in range(3):
        box("roof_rib", (2.3, 0.05, 0.04), (0, CY0 + 0.4 + k * 0.4, CZ1 + 0.05), P, 0.01)
    for sx in (-CX, CX):
        s = 1 if sx > 0 else -1
        box("door_lower", (0.08, CY1 - CY0 - 0.1, 0.8), (sx, (CY0 + CY1) / 2, CZ0 + 0.42), P, 0.02)
        box("door_seam", (0.09, 0.02, 0.78), (sx, CY0 + 0.25, CZ0 + 0.42), "black")
        box("door_handle", (0.05, 0.14, 0.03), (sx + s * 0.05, CY0 + 0.45, 2.02), "metal")
        box("a_pillar", (0.08, 0.08, 0.75), (sx, CY1 + 0.07, 2.52), P, 0.01, rot=(-10, 0, 0))
        box("b_pillar", (0.08, 0.1, 0.75), (sx, CY0 + 0.05, 2.52), P, 0.01)
        box("window_sill", (0.1, CY1 - CY0, 0.06), (sx, (CY0 + CY1) / 2, 2.17), P, 0.01)
        box("door_glass", (0.02, CY1 - CY0 - 0.15, 0.65), (sx, (CY0 + CY1) / 2, 2.52), "glass")
        # mirror on a tube arm
        _tube("mirror_arm", (sx, CY1 - 0.05, 2.35), (sx + s * 0.35, CY1 + 0.02, 2.4), 0.018, "gun_metal", 6)
        _tube("mirror_arm2", (sx, CY1 - 0.05, 2.7), (sx + s * 0.35, CY1 + 0.02, 2.6), 0.018, "gun_metal", 6)
        box("mirror", (0.05, 0.2, 0.34), (sx + s * 0.38, CY1 + 0.02, 2.5), "gun_metal", 0.02)
        box("mirror_glass", (0.01, 0.17, 0.3), (sx + s * 0.38, CY1 - 0.01, 2.5), "glass")
        _tube("grab_handle", (sx + s * 0.05, CY0 + 0.1, 1.7), (sx + s * 0.05, CY0 + 0.1, 2.3), 0.015, "metal", 6)
        box("cab_step", (0.35, 0.45, 0.05), (sx * 1.0, CY0 + 0.6, 0.95), "gun_metal")
    # split windscreen, raked back
    box("screen_frame_top", (2.4, 0.1, 0.08), (0, CY1 + 0.02, CZ1 - 0.05), P, 0.01)
    box("screen_frame_mid", (0.08, 0.08, 0.68), (0, CY1 + 0.1, 2.52), P, 0.01, rot=(-10, 0, 0))
    for sx in (-0.58, 0.58):
        box("windscreen", (1.08, 0.03, 0.66), (sx, CY1 + 0.1, 2.52), "glass", rot=(-10, 0, 0))
        _tube("wiper", (sx - 0.3, CY1 + 0.18, 2.2), (sx + 0.1, CY1 + 0.13, 2.6), 0.01, "black", 5)
    box("sun_visor", (2.3, 0.14, 0.05), (0, CY1 + 0.12, CZ1 + 0.01), P, 0.01)
    # interior: dash, gauges, steering wheel, seats, gear levers
    box("dash", (2.3, 0.35, 0.22), (0, CY1 - 0.2, 2.02), "gear", 0.03)
    box("dash_panel", (0.8, 0.02, 0.16), (-0.5, CY1 - 0.38, 2.05), "black")
    for i, gx in enumerate((-0.75, -0.6, -0.45, -0.3)):
        cyl("gauge", 0.045, 0.02, (gx, CY1 - 0.395, 2.06), "metal", rot=(90, 0, 0), verts=12)
        cyl("gauge_face", 0.037, 0.01, (gx, CY1 - 0.41, 2.06), "black", rot=(90, 0, 0), verts=12)
    _tube("steering_column", (-0.5, CY1 - 0.3, 1.9), (-0.5, CY1 - 0.62, 2.18), 0.035, "black", 8)
    torus("steering_wheel", 0.2, 0.022, (-0.5, CY1 - 0.64, 2.2), "black", rot=(-55, 0, 0), segs=24)
    for a in (0, 120, 240):
        ra = math.radians(a)
        _tube("spoke", (-0.5, CY1 - 0.64, 2.2),
              (-0.5 + math.cos(ra) * 0.19, CY1 - 0.64 + math.sin(ra) * 0.19 * math.sin(math.radians(55)), 2.2 + math.sin(ra) * 0.19 * math.cos(math.radians(55))),
              0.012, "black", 5)
    for sx in (-0.5, 0.55):
        box("seat_base", (0.55, 0.5, 0.14), (sx, CY0 + 0.45, 1.75), "gear", 0.04)
        box("seat_back", (0.55, 0.12, 0.62), (sx, CY0 + 0.17, 2.1), "gear", 0.04, rot=(-8, 0, 0))
        box("seat_frame", (0.4, 0.4, 0.3), (sx, CY0 + 0.45, 1.53), "gun_metal")
    _tube("gear_lever", (0.0, CY1 - 0.55, 1.4), (-0.05, CY1 - 0.7, 1.95), 0.012, "gun_metal", 6)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035, location=(-0.05, CY1 - 0.7, 1.97), segments=8, ring_count=6)
    _finish(bpy.context.active_object, "black")
    box("engine_hump", (0.6, 0.6, 0.3), (0, CY1 - 0.35, 1.5), P, 0.05)
    # snorkel air intake + exhaust stack behind cab
    _tube("air_intake", (1.3, 1.12, 1.9), (1.3, 1.12, 3.0), 0.09, "gun_metal", 12)
    cyl("air_cap", 0.13, 0.15, (1.3, 1.12, 3.05), "gun_metal", verts=12, bevel=0.01)
    _tube("exhaust", (-1.3, 1.05, 1.2), (-1.3, 1.05, 3.05), 0.06, "rust", 10)
    cyl("exhaust_guard", 0.09, 0.8, (-1.3, 1.05, 2.4), "gun_metal", verts=10)
    # ---- behind cab: spare wheel + fuel tanks + tool boxes
    _tire(0.0, 0.72, 0.5, 0.34) if False else None
    cyl("spare", 0.52, 0.36, (0, 0.72, 1.75), "black", rot=(90, 0, 0), verts=26, bevel=0.05)
    cyl("spare_rim", 0.3, 0.4, (0, 0.72, 1.75), "rim_paint", rot=(90, 0, 0), verts=18)
    box("spare_carrier", (1.2, 0.1, 0.1), (0, 0.72, 1.2), "gun_metal")
    for sx in (-1.0, 1.0):
        cyl("fuel_tank", 0.26, 1.0, (sx, 0.4, 0.85), P, rot=(90, 0, 0), verts=18, bevel=0.03)
        box("tank_strap", (0.56, 0.05, 0.56), (sx, 0.15, 0.85), "gun_metal")
        box("tank_strap2", (0.56, 0.05, 0.56), (sx, 0.65, 0.85), "gun_metal")
        cyl("fuel_cap", 0.06, 0.05, (sx, 0.55, 1.12), "black", verts=10)
        box("toolbox", (0.5, 0.9, 0.45), (sx * 1.02, -3.95, 0.75), P, 0.02)
        box("toolbox_latch", (0.05, 0.12, 0.08), (sx * 1.28, -3.95, 0.88), "metal")
    # ---- cargo bed: steel frame, wooden deck & drop sides, canvas over hoops
    BY0, BY1, BW = -4.45, 0.2, 1.23
    box("bed_frame", (2.5, BY1 - BY0, 0.14), (0, (BY0 + BY1) / 2, 0.97), "gun_metal", 0.01)
    box("bed_floor", (2.4, BY1 - BY0 - 0.05, 0.1), (0, (BY0 + BY1) / 2, 1.1), "wood")
    box("headboard", (2.5, 0.1, 1.3), (0, BY1, 1.75), P, 0.02)
    for sx in (-BW, BW):
        for k in range(4):
            box("side_board", (0.06, BY1 - BY0, 0.16), (sx, (BY0 + BY1) / 2, 1.25 + k * 0.175), "wood", 0.012)
        box("side_rail", (0.08, BY1 - BY0, 0.06), (sx, (BY0 + BY1) / 2, 1.95), P, 0.01)
        for yy in (-4.35, -3.2, -2.1, -1.0, 0.1):
            box("stake", (0.09, 0.08, 0.95), (sx * 1.01, yy, 1.5), P, 0.01)
        for yy in (-3.8, -1.5):
            box("hinge", (0.1, 0.12, 0.06), (sx * 1.02, yy, 1.18), "gun_metal")
    for k in range(4):
        box("tail_board", (2.46, 0.06, 0.16), (0, BY0, 1.25 + k * 0.175), "wood", 0.012)
    for sx in (-0.9, 0.9):
        box("tail_chain", (0.03, 0.03, 0.5), (sx, BY0 - 0.04, 1.6), "gun_metal")
    # canvas hoops + canvas roof, sides rolled up so the rider can shoot out
    hoops = (-4.3, -3.15, -2.0, -0.85, 0.1)
    for yy in hoops:
        for sx in (-BW, BW):
            _tube("hoop_leg", (sx, yy, 1.95), (sx, yy, 2.85), 0.022, "gun_metal", 6)
        _arch_pts = []
        for i in range(9):
            a = math.radians(180 * i / 8)
            _arch_pts.append((math.cos(a) * BW, yy, 2.85 + math.sin(a) * 0.35))
        for i in range(8):
            _tube("hoop_top", _arch_pts[i], _arch_pts[i + 1], 0.022, "gun_metal", 6)
    for i in range(8):
        a0 = math.radians(180 * i / 8)
        a1 = math.radians(180 * (i + 1) / 8)
        mx = (math.cos(a0) + math.cos(a1)) / 2 * (BW + 0.03)
        mz = 2.87 + (math.sin(a0) + math.sin(a1)) / 2 * 0.37
        width = math.dist((math.cos(a0) * BW, math.sin(a0) * 0.35), (math.cos(a1) * BW, math.sin(a1) * 0.35)) + 0.03
        ang = math.degrees(math.atan2(math.sin(a1) * 0.35 - math.sin(a0) * 0.35, math.cos(a1) * BW - math.cos(a0) * BW))
        box("canvas", (width, BY1 - BY0 + 0.1, 0.025), (mx, (BY0 + BY1) / 2, mz), "canvas", rot=(0, -ang, 0))
    for sx in (-BW - 0.04, BW + 0.04):
        cyl("canvas_roll", 0.1, BY1 - BY0, (sx, (BY0 + BY1) / 2, 2.8), "canvas", rot=(90, 0, 0), verts=12)
        for yy in (-3.7, -2.5, -1.4, -0.3):
            box("roll_strap", (0.23, 0.04, 0.23), (sx, yy, 2.8), "gear")
    box("canvas_front", (2.5, 0.03, 1.2), (0, BY1 + 0.02, 2.55), "canvas")
    # ---- wheels: single front, dual rear tandem
    for sx in (-1.0, 1.0):
        _tire(sx, 3.3, 0.56, 0.42)
        _tire(sx * 0.93, -1.55, 0.56, 0.36, dual=False)
        _tire(sx * 0.93, -2.95, 0.56, 0.36, dual=False)
        box("rear_mudguard", (0.46, 3.1, 0.04), (sx * 0.95, -2.25, 1.22), P, 0.01)
        box("mudflap", (0.42, 0.02, 0.4), (sx * 0.95, -3.7, 0.72), "black")
        box("mudflap_f", (0.42, 0.02, 0.35), (sx * 1.0, 2.55, 0.62), "black")
    # ---- rear
    box("rear_bumper", (2.2, 0.15, 0.18), (0, -4.62, 0.85), "gun_metal", 0.02)
    for sx in (-0.95, 0.95):
        box("tail_light_box", (0.26, 0.08, 0.16), (sx, -4.62, 1.02), "gun_metal", 0.01)
        box("tail_light", (0.2, 0.02, 0.1), (sx, -4.67, 1.02), "tail_light")
    box("plate", (0.5, 0.02, 0.14), (0, -4.7, 0.85), "hazard_sign")
    torus("pintle_hook", 0.07, 0.025, (0, -4.72, 0.72), "rust", rot=(0, 90, 0), segs=10)
    # jerry cans strapped to the side
    for yy in (-0.35, -0.7):
        box("jerry_can", (0.16, 0.34, 0.46), (-1.36, yy, 1.35), "jerry_paint", 0.02)
        box("jerry_rack", (0.04, 0.8, 0.05), (-1.3, -0.52, 1.14), "gun_metal")
    export("supply_truck")



def _hollow_tube(name, r, length, loc, material, thick=0.003):
    """Open-ended tube along Y (optic / scope bodies you can see through)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=length, vertices=20, location=loc, rotation=(math.radians(90), 0, 0))
    tube = bpy.context.active_object
    tube.name = name
    bm = bmesh.new()
    bm.from_mesh(tube.data)
    caps = [f for f in bm.faces if abs(f.normal.y) > 0.9]
    bmesh.ops.delete(bm, geom=caps, context="FACES_ONLY")
    bm.to_mesh(tube.data)
    bm.free()
    solid = tube.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = thick
    return _finish(tube, material)


def ak():
    """AK-74 style rifle carried by Kranor troops. Barrel along +Y. Iron-sight line at z = 0.058. Muzzle at y = 0.66."""
    reset()
    M, W = "gun_metal", "wood"
    box("receiver", (0.05, 0.3, 0.058), (0, 0.0, 0.0), M, 0.004)
    box("dust_cover", (0.046, 0.26, 0.02), (0, -0.01, 0.036), M, 0.008)
    for i in range(5):
        box("cover_rib", (0.048, 0.008, 0.004), (0, -0.09 + i * 0.04, 0.047), M)
    box("trunnion", (0.052, 0.05, 0.06), (0, 0.17, 0.0), M, 0.004)
    box("selector", (0.004, 0.12, 0.018), (0.027, 0.0, 0.012), M)
    box("charging_handle", (0.03, 0.012, 0.012), (0.035, 0.08, 0.01), M)
    # curved steel magazine
    for i in range(8):
        a = i * 5.0
        box("mag", (0.03, 0.07, 0.03), (0, 0.075 + i * 0.012 + i * i * 0.001, -0.05 - i * 0.026), "gun_metal", 0.003, rot=(a, 0, 0))
    box("grip", (0.034, 0.045, 0.1), (0, -0.07, -0.075), "gun_polymer", 0.008, rot=(-20, 0, 0))
    box("trigger_guard", (0.008, 0.07, 0.006), (0, -0.01, -0.045), M)
    # wooden stock
    box("stock_neck", (0.034, 0.12, 0.04), (0, -0.2, -0.01), W, 0.008, rot=(-6, 0, 0))
    box("stock", (0.04, 0.2, 0.075), (0, -0.33, -0.04), W, 0.012, rot=(-6, 0, 0))
    box("butt_plate", (0.042, 0.01, 0.085), (0, -0.435, -0.05), M, 0.003)
    # wooden handguards
    box("lower_guard", (0.05, 0.2, 0.045), (0, 0.29, -0.005), W, 0.012)
    box("upper_guard", (0.04, 0.17, 0.028), (0, 0.29, 0.042), W, 0.01)
    cyl("gas_tube", 0.011, 0.2, (0, 0.3, 0.035), M, rot=(90, 0, 0), verts=10)
    box("gas_block", (0.03, 0.03, 0.05), (0, 0.44, 0.022), M, 0.003)
    cyl("barrel", 0.01, 0.26, (0, 0.5, 0.0), M, rot=(90, 0, 0), verts=12)
    cyl("brake", 0.014, 0.07, (0, 0.645, 0.0), M, rot=(90, 0, 0), verts=12, bevel=0.002)
    # iron sights
    box("rear_sight", (0.03, 0.03, 0.02), (0, 0.13, 0.05), M, 0.002)
    box("rear_notch", (0.006, 0.032, 0.012), (0, 0.13, 0.062), "black")
    box("front_post_base", (0.018, 0.02, 0.05), (0, 0.6, 0.03), M, 0.002)
    box("front_post", (0.004, 0.004, 0.02), (0, 0.6, 0.058), M)
    torus("front_hood", 0.012, 0.002, (0, 0.6, 0.058), M, rot=(90, 0, 0), segs=12)
    box("sling_loop", (0.006, 0.02, 0.02), (0, 0.42, -0.04), M)
    export("ak")


def dmr():
    """Scoped marksman rifle dropped by Kranor snipers. Barrel along +Y. Scope axis at z = 0.075. Muzzle at y = 0.86."""
    reset()
    M, W = "gun_metal", "wood"
    box("receiver", (0.048, 0.32, 0.055), (0, 0.0, 0.0), M, 0.004)
    box("mag", (0.03, 0.08, 0.07), (0, 0.06, -0.06), M, 0.004, rot=(8, 0, 0))
    box("trigger_guard", (0.008, 0.07, 0.006), (0, -0.04, -0.045), M)
    # skeleton stock + pistol grip in wood
    box("grip", (0.034, 0.045, 0.1), (0, -0.1, -0.075), W, 0.01, rot=(-22, 0, 0))
    box("stock_top", (0.036, 0.3, 0.03), (0, -0.3, 0.005), W, 0.01)
    box("stock_bottom", (0.036, 0.22, 0.03), (0, -0.34, -0.085), W, 0.01, rot=(12, 0, 0))
    box("stock_rear", (0.038, 0.04, 0.12), (0, -0.45, -0.04), W, 0.01)
    box("cheek_rest", (0.034, 0.14, 0.02), (0, -0.3, 0.03), "gun_polymer", 0.006)
    box("butt_pad", (0.04, 0.012, 0.125), (0, -0.475, -0.04), "gear", 0.004)
    box("handguard", (0.05, 0.32, 0.05), (0, 0.33, 0.0), W, 0.012)
    for i in range(6):
        box("vent", (0.052, 0.02, 0.008), (0, 0.22 + i * 0.045, 0.012), M)
    cyl("barrel", 0.011, 0.4, (0, 0.66, 0.005), M, rot=(90, 0, 0), verts=12)
    cyl("flash_hider", 0.015, 0.06, (0, 0.85, 0.005), M, rot=(90, 0, 0), verts=10, bevel=0.002)
    # scope: rings, tube, objective and eyepiece bells, turrets, lenses
    for yy in (-0.03, 0.1):
        box("scope_ring", (0.04, 0.02, 0.05), (0, yy, 0.05), M, 0.004)
    _hollow_tube("scope_tube", 0.016, 0.26, (0, 0.035, 0.075), M)
    cyl("objective", 0.026, 0.07, (0, 0.2, 0.075), M, rot=(90, 0, 0), verts=20, r2=0.018)
    cyl("eyepiece", 0.021, 0.06, (0, -0.12, 0.075), M, rot=(-90, 0, 0), verts=20, r2=0.017)
    cyl("lens_front", 0.023, 0.004, (0, 0.235, 0.075), "glass", rot=(90, 0, 0), verts=20)
    cyl("lens_rear", 0.018, 0.004, (0, -0.15, 0.075), "glass", rot=(90, 0, 0), verts=20)
    cyl("turret_top", 0.012, 0.03, (0, 0.04, 0.1), M, verts=14, bevel=0.002)
    cyl("turret_side", 0.012, 0.03, (0.027, 0.04, 0.075), M, rot=(0, 90, 0), verts=14, bevel=0.002)
    cyl("bipod_leg_l", 0.005, 0.18, (-0.018, 0.42, -0.1), M, rot=(10, -8, 0), verts=6)
    cyl("bipod_leg_r", 0.005, 0.18, (0.018, 0.42, -0.1), M, rot=(10, 8, 0), verts=6)
    export("dmr")


def pistol():
    """Service pistol (sidearm). Barrel along +Y. Sight line at z = 0.034. Muzzle at y = 0.1."""
    reset()
    M = "gun_metal"
    box("slide", (0.03, 0.19, 0.032), (0, 0.0, 0.0), M, 0.004)
    for i in range(7):
        box("serration", (0.032, 0.004, 0.026), (0, -0.085 + i * 0.008, 0.0), "black")
    box("port", (0.002, 0.04, 0.014), (0.0155, 0.02, 0.004), "black")
    box("frame", (0.028, 0.16, 0.024), (0, 0.005, -0.026), "gun_polymer", 0.004)
    box("rail", (0.022, 0.05, 0.01), (0, 0.06, -0.042), "gun_polymer")
    box("grip", (0.03, 0.05, 0.11), (0, -0.065, -0.085), "gun_polymer", 0.008, rot=(-14, 0, 0))
    box("trigger_guard", (0.006, 0.05, 0.006), (0, 0.02, -0.058), "gun_polymer")
    box("trigger", (0.006, 0.006, 0.02), (0, 0.01, -0.045), M)
    box("mag_base", (0.032, 0.054, 0.01), (0, -0.078, -0.142), M, 0.002, rot=(-14, 0, 0))
    cyl("barrel", 0.007, 0.02, (0, 0.1, 0.004), M, rot=(90, 0, 0), verts=10)
    box("rear_sight", (0.024, 0.01, 0.01), (0, -0.085, 0.022), M)
    box("front_sight", (0.004, 0.008, 0.01), (0, 0.085, 0.022), M)
    box("hammer", (0.008, 0.012, 0.018), (0, -0.1, -0.005), M, rot=(20, 0, 0))
    export("pistol")


def knife():
    """Combat knife held in the right hand. Blade along +Y."""
    reset()
    # blade: flat wedge with a clipped tip, darkened steel
    bm = bmesh.new()
    pts = [(0, 0.0, 0.012), (0, 0.15, 0.012), (0, 0.19, 0.0), (0, 0.16, -0.01), (0, 0.0, -0.016)]
    top = [bm.verts.new((x + 0.002, y, z)) for x, y, z in pts]
    bot = [bm.verts.new((x - 0.002, y, z)) for x, y, z in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        bm.faces.new([top[i], top[(i + 1) % n], bot[(i + 1) % n], bot[i]])
    me = bpy.data.meshes.new("blade")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("blade", me)
    bpy.context.collection.objects.link(ob)
    _finish(ob, "metal")
    box("edge_bevel", (0.001, 0.15, 0.004), (0, 0.075, -0.014), "metal")
    box("guard", (0.02, 0.012, 0.05), (0, -0.006, -0.002), "gun_metal", 0.003)
    cyl("handle", 0.014, 0.11, (0, -0.065, -0.002), "gear", rot=(90, 0, 0), verts=10, bevel=0.003)
    for i in range(5):
        cyl("handle_ring", 0.0145, 0.004, (0, -0.03 - i * 0.017, -0.002), "black", rot=(90, 0, 0), verts=10)
    cyl("pommel", 0.013, 0.015, (0, -0.125, -0.002), "gun_metal", rot=(90, 0, 0), verts=10, bevel=0.003)
    export("knife")



def ammo_can():
    """Steel military ammo can (M2A1 style) with carry handle and lid latch. Origin at the bottom centre."""
    reset()
    A = "ammo_paint"
    box("body", (0.28, 0.14, 0.17), (0, 0, 0.085), A, 0.008)
    box("lid", (0.29, 0.15, 0.03), (0, 0, 0.185), A, 0.006)
    box("lid_rib", (0.26, 0.02, 0.012), (0, 0, 0.205), A, 0.003)
    box("gasket", (0.281, 0.141, 0.006), (0, 0, 0.168), "black")
    box("latch", (0.03, 0.02, 0.07), (0.15, 0, 0.16), "gun_metal", 0.003)
    box("hinge", (0.025, 0.12, 0.02), (-0.145, 0, 0.18), "gun_metal")
    for sx in (-0.07, 0.07):
        box("handle_post", (0.012, 0.012, 0.03), (sx, 0, 0.215), "gun_metal")
    box("handle", (0.16, 0.02, 0.012), (0, 0, 0.232), "gun_metal", 0.004)
    for side in (-1, 1):
        box("stencil_band", (0.24, 0.002, 0.03), (0, side * 0.0705, 0.1), "stencil")
        box("rib", (0.26, 0.004, 0.012), (0, side * 0.0715, 0.04), A)
    export("ammo_can")


def intel_folder():
    """Classified dossier: red folder with papers and a photo sticking out. Origin at the bottom centre."""
    reset()
    box("folder_back", (0.32, 0.24, 0.006), (0, 0, 0.003), "folder_red", 0.002)
    box("papers", (0.3, 0.22, 0.012), (0.01, 0.005, 0.012), "paper")
    box("paper_out", (0.2, 0.15, 0.002), (0.09, 0.07, 0.02), "paper", rot=(0, 0, 18))
    box("photo", (0.09, 0.07, 0.002), (-0.08, 0.06, 0.021), "photo", rot=(0, 0, -12))
    box("folder_front", (0.32, 0.24, 0.006), (0, -0.01, 0.024), "folder_red", 0.002, rot=(-4, 0, 3))
    box("secret_band", (0.3, 0.04, 0.002), (0, -0.05, 0.028), "stencil", rot=(-4, 0, 3))
    export("intel_folder")


def technical():
    """Military light utility vehicle (4x4) with a ring-mounted machine gun. Front toward +Y.
    Gunner stands in the rear bay at (0, -1.2, 1.35); gun muzzle at (0, 0.52, 2.62)."""
    reset()
    P = "truck_paint"
    # chassis + wide low body with flared fenders
    box("frame", (1.2, 4.6, 0.25), (0, 0.0, 0.62), "gun_metal")
    box("body", (2.2, 4.7, 0.6), (0, 0.0, 1.0), P, 0.05)
    for sx in (-1.12, 1.12):
        for yy in (1.55, -1.45):
            _arch("fender", sx, yy, 0.52, 0.62, 0.34, 0.035, P, a0=0, a1=180, segs=10)
            box("fender_top", (0.34, 1.2, 0.04), (sx, yy, 1.18), P, 0.01)
        box("rocker", (0.1, 1.6, 0.25), (sx, 0.05, 0.82), "gun_metal", 0.02)
        box("step", (0.28, 0.6, 0.04), (sx * 1.08, 0.1, 0.7), "gun_metal")
    # sloped bonnet with vent slots and a split grille
    box("bonnet", (2.1, 1.5, 0.2), (0, 1.55, 1.35), P, 0.04, rot=(-6, 0, 0))
    for i in range(6):
        box("bonnet_vent", (1.2, 0.04, 0.02), (0, 1.2 + i * 0.12, 1.46 + i * 0.0125), "black")
    box("grille", (1.7, 0.08, 0.55), (0, 2.34, 1.05), P, 0.02)
    for i in range(9):
        box("grille_slot", (0.07, 0.1, 0.4), (-0.64 + i * 0.16, 2.37, 1.07), "black")
    box("bumper", (2.2, 0.25, 0.25), (0, 2.45, 0.7), "gun_metal", 0.03)
    cyl("winch", 0.1, 0.8, (0, 2.5, 0.88), "gun_metal", rot=(0, 90, 0), verts=12)
    for sx in (-0.78, 0.78):
        cyl("headlight", 0.1, 0.05, (sx, 2.4, 1.2), "lamp_glass", rot=(90, 0, 0), verts=14)
        box("light_guard", (0.28, 0.04, 0.04), (sx, 2.46, 1.2), "gun_metal")
        box("blackout", (0.1, 0.04, 0.06), (sx * 0.62, 2.39, 1.24), "tail_light")
    # armoured cabin: flat panels, small thick windows, roof with a gunner hatch ring
    box("cabin_lower", (2.1, 1.7, 0.5), (0, 0.15, 1.55), P, 0.03)
    box("windscreen_frame", (2.0, 0.1, 0.6), (0, 0.95, 2.0), P, 0.02, rot=(-12, 0, 0))
    for sx in (-0.48, 0.48):
        box("windscreen", (0.82, 0.03, 0.45), (sx, 1.0, 2.0), "glass", rot=(-12, 0, 0))
    for sx in (-1.03, 1.03):
        box("door", (0.08, 1.5, 0.95), (sx, 0.15, 1.75), P, 0.02)
        box("door_window", (0.02, 0.55, 0.35), (sx * 1.02, 0.45, 2.0), "glass")
        box("door_window2", (0.02, 0.55, 0.35), (sx * 1.02, -0.2, 2.0), "glass")
        box("door_handle", (0.04, 0.14, 0.03), (sx * 1.04, 0.1, 1.8), "metal")
        box("mirror", (0.04, 0.16, 0.2), (sx * 1.2, 0.95, 2.05), "gun_metal", 0.01)
        box("mirror_arm", (0.2, 0.03, 0.03), (sx * 1.1, 0.95, 2.05), "gun_metal")
    box("roof", (2.1, 1.7, 0.08), (0, 0.15, 2.3), P, 0.03)
    # rear bay (open) where the gunner stands
    box("bay_floor", (2.0, 1.9, 0.06), (0, -1.45, 1.32), "gun_metal")
    for sx in (-1.03, 1.03):
        box("bay_side", (0.08, 1.9, 0.55), (sx, -1.45, 1.58), P, 0.02)
    box("tailgate", (2.1, 0.08, 0.55), (0, -2.38, 1.58), P, 0.02)
    cyl("spare", 0.42, 0.3, (0, -2.55, 1.35), "black", rot=(90, 0, 0), verts=20, bevel=0.03)
    cyl("spare_hub", 0.22, 0.32, (0, -2.55, 1.35), "rim_paint", rot=(90, 0, 0), verts=12)
    for sx in (-0.8, 0.8):
        box("jerry_can", (0.16, 0.34, 0.46), (sx, -2.2, 1.6), "jerry_paint", 0.02)
        box("tail_light", (0.14, 0.03, 0.08), (sx * 1.2, -2.37, 1.2), "tail_light")
    # gun ring on a pedestal + shielded machine gun
    cyl("pedestal", 0.07, 1.2, (0, -0.95, 1.95), "gun_metal", verts=10)
    torus("gun_ring", 0.45, 0.04, (0, -0.95, 2.45), "gun_metal", segs=24)
    box("shield", (0.9, 0.05, 0.5), (0, -0.2, 2.65), P, 0.02, rot=(8, 0, 0))
    box("shield_l", (0.05, 0.3, 0.45), (-0.45, -0.32, 2.65), P, 0.02)
    box("shield_r", (0.05, 0.3, 0.45), (0.45, -0.32, 2.65), P, 0.02)
    box("mg_body", (0.1, 0.5, 0.14), (0, -0.4, 2.62), "gun_metal", 0.01)
    cyl("mg_barrel", 0.025, 0.85, (0, 0.1, 2.62), "gun_metal", rot=(90, 0, 0), verts=10)
    cyl("mg_shroud", 0.04, 0.35, (0, -0.05, 2.62), "gun_metal", rot=(90, 0, 0), verts=10)
    box("ammo_box", (0.18, 0.2, 0.16), (0.14, -0.45, 2.56), "jerry_paint", 0.01)
    box("mg_grips", (0.2, 0.04, 0.12), (0, -0.7, 2.6), "gun_metal")
    cyl("antenna", 0.008, 2.0, (0.9, -0.3, 3.2), "black", verts=5)
    # big off-road tyres
    for sx in (-1.0, 1.0):
        _tire(sx, 1.55, 0.5, 0.36)
        _tire(sx, -1.45, 0.5, 0.36)
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


# ---------------------------------------------------------------- soldiers (posable)

def _between(name, p1, p2, r1, r2, material, verts=12):
    """Tapered cylinder from p1 to p2 (for limbs)."""
    a, b = Vector(p1), Vector(p2)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=d.length, vertices=verts, location=(a + b) / 2)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(rotation=True)
    _finish(o, material, 0.0)
    sub = o.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    return o


def _ball(name, loc, scale, material, segs=16):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=segs, ring_count=segs // 2, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, material)


def _join(name, objs, pivot):
    """Join objects into one part whose origin (joint) is at `pivot`."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    part = bpy.context.active_object
    part.name = name
    bpy.context.scene.cursor.location = pivot
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return part


def _parent(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def _empty(name, loc, parent):
    e = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(e)
    e.location = loc
    _parent(e, parent)
    return e


def _soldier(officer=False):
    reset()
    U = "coat" if officer else "uniform"
    parts = {}
    # --- pelvis
    objs = [box("hips", (0.34, 0.22, 0.2), (0, 0, 0.94), U, 0.07, segs=4)]
    objs.append(box("belt", (0.37, 0.25, 0.06), (0, 0, 1.0), "gear", 0.02, segs=3))
    objs.append(box("buckle", (0.06, 0.02, 0.045), (0, 0.13, 1.0), "gun_metal", 0.005))
    if not officer:
        for x in (-0.14, 0.14):
            objs.append(box("hip_pouch", (0.07, 0.1, 0.12), (x, -0.12, 0.95), "gear", 0.015))
    else:
        sk = _between("coat_skirt", (0, 0, 1.0), (0, 0, 0.55), 0.2, 0.27, U, verts=16)
        sk.scale = (1.0, 0.75, 1.0)
        bpy.context.view_layer.objects.active = sk
        bpy.ops.object.transform_apply(scale=True)
        objs.append(sk)
    pelvis = _join("pelvis", objs, (0, 0, 0.95))
    # --- legs
    for side, sx in (("l", -0.1), ("r", 0.1)):
        th = [_between("thigh", (sx, 0, 0.93), (sx, 0.02, 0.5), 0.09, 0.07, U)]
        if not officer:
            th.append(box("cargo", (0.04, 0.13, 0.15), (sx * 1.85, 0.02, 0.7), U, 0.02, segs=3))
            if side == "r":
                th.append(box("holster", (0.05, 0.1, 0.16), (sx * 1.9, -0.02, 0.84), "gear", 0.02, segs=3))
                th.append(box("pistol", (0.03, 0.09, 0.05), (sx * 1.9, 0.0, 0.94), "gun_metal", 0.008))
        thigh = _join("thigh_" + side, th, (sx, 0, 0.92))
        sh = [_between("shin", (sx, 0.02, 0.5), (sx, 0, 0.12), 0.066, 0.05, U)]
        sh.append(box("knee_pad", (0.115, 0.06, 0.13), (sx, 0.075, 0.5), "gear", 0.03, segs=3))
        sh.append(box("sole", (0.125, 0.29, 0.035), (sx, 0.045, 0.018), "black", 0.012, segs=2))
        sh.append(box("boot", (0.115, 0.27, 0.1), (sx, 0.04, 0.085), "boot", 0.045, segs=4))
        sh.append(box("boot_top", (0.11, 0.13, 0.13), (sx, 0, 0.19), "boot", 0.04, segs=3))
        shin = _join("shin_" + side, sh, (sx, 0.02, 0.5))
        _parent(thigh, pelvis)
        _parent(shin, thigh)
    # --- torso
    t = [_between("chest", (0, 0, 0.98), (0, 0, 1.46), 0.17, 0.21, U, verts=20)]
    t[0].scale = (1.15, 0.75, 1.0)
    bpy.context.view_layer.objects.active = t[0]
    bpy.ops.object.transform_apply(scale=True)
    t.append(_ball("shoulders", (0, 0, 1.42), (0.23, 0.13, 0.08), U))
    if officer:
        cf = _between("coat_chest", (0, 0, 0.98), (0, 0, 1.44), 0.2, 0.22, U, verts=16)
        cf.scale = (1.1, 0.78, 1.0)
        bpy.context.view_layer.objects.active = cf
        bpy.ops.object.transform_apply(scale=True)
        t.append(cf)
        t.append(box("belt_officer", (0.44, 0.33, 0.05), (0, 0, 1.02), "gear", 0.015))
        t.append(box("lapel", (0.2, 0.02, 0.2), (0, 0.165, 1.35), "gear", 0.01))
        for x in (-0.19, 0.19):
            t.append(box("epaulette", (0.1, 0.12, 0.02), (x, 0, 1.47), "beret", 0.005))
        for i in range(3):
            t.append(cyl("button", 0.012, 0.01, (0.05, 0.17, 1.1 + i * 0.09), "metal", rot=(90, 0, 0), verts=8))
        t.append(box("holster", (0.06, 0.12, 0.16), (0.2, 0, 1.0), "gear", 0.02))
    else:
        t.append(box("plate_carrier", (0.41, 0.3, 0.37), (0, 0, 1.22), "gear", 0.06, segs=4))
        t.append(box("cummerbund", (0.44, 0.26, 0.12), (0, 0, 1.08), "gear", 0.04, segs=3))
        for i, x in enumerate((-0.12, 0.0, 0.12)):
            t.append(box("mag_pouch", (0.09, 0.065, 0.14), (x, 0.175, 1.13), "gear_light", 0.025, segs=3))
            t.append(box("pouch_flap", (0.092, 0.07, 0.03), (x, 0.178, 1.2), "gear", 0.01))
        t.append(box("admin_pouch", (0.2, 0.05, 0.1), (0, 0.17, 1.3), "gear_light", 0.02, segs=3))
        t.append(box("name_tape", (0.12, 0.005, 0.03), (0, 0.2, 1.36), "patch"))
        for x in (-0.19, 0.19):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, segments=10, ring_count=6, location=(x, 0.1, 1.1))
            t.append(_finish(bpy.context.active_object, "gun_metal"))   # grenades
        t.append(box("radio", (0.08, 0.06, 0.16), (-0.2, -0.06, 1.2), "gear", 0.015))
        t.append(cyl("antenna", 0.006, 0.55, (-0.2, -0.08, 1.55), "gun_metal", verts=6))
        t.append(box("backpack", (0.3, 0.15, 0.4), (0, -0.2, 1.22), "gear_light", 0.04))
        t.append(box("pack_top", (0.28, 0.14, 0.08), (0, -0.2, 1.44), "gear", 0.03))
        t.append(box("strap_l", (0.05, 0.3, 0.03), (-0.12, 0, 1.44), "gear"))
        t.append(box("strap_r", (0.05, 0.3, 0.03), (0.12, 0, 1.44), "gear"))
        t.append(box("patch", (0.06, 0.005, 0.05), (0.21, 0.0, 1.34), "patch", rot=(0, 0, 90)))
    torso = _join("torso", t, (0, 0, 0.98))
    _parent(torso, pelvis)
    # --- head
    h = [_between("neck", (0, 0, 1.46), (0, 0.01, 1.56), 0.055, 0.05, "balaclava")]
    h.append(_ball("head", (0, 0.015, 1.64), (0.095, 0.11, 0.12), "balaclava"))
    h.append(box("eye_slit", (0.13, 0.03, 0.035), (0, 0.105, 1.655), "black", 0.012))
    if officer:
        h.append(_ball("face", (0, 0.03, 1.63), (0.085, 0.1, 0.105), "skin"))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=16, ring_count=8, location=(0.02, 0.0, 1.73))
        beret = bpy.context.active_object
        beret.scale = (0.12, 0.13, 0.04)
        bpy.ops.object.transform_apply(scale=True)
        h.append(_finish(beret, "beret"))
        h.append(box("brow", (0.12, 0.01, 0.015), (0, 0.105, 1.67), "gear"))
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, segments=18, ring_count=10, location=(0, 0.0, 1.66))
        helm = bpy.context.active_object
        helm.name = "helmet"
        bm = bmesh.new()
        bm.from_mesh(helm.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.02], context="VERTS")
        bm.to_mesh(helm.data)
        bm.free()
        helm.scale = (1.0, 1.1, 1.0)
        bpy.ops.object.transform_apply(scale=True)
        sol = helm.modifiers.new("solid", "SOLIDIFY")
        sol.thickness = 0.012
        h.append(_finish(helm, "helmet"))
        for x in (-0.13, 0.13):
            h.append(cyl("ear_pro", 0.045, 0.035, (x, 0.0, 1.62), "gear", rot=(0, 90, 0), verts=12))
        h.append(box("nvg_mount", (0.05, 0.03, 0.05), (0, 0.15, 1.72), "gun_metal", 0.008))
        for x in (-0.03, 0.03):
            h.append(cyl("nvg_tube", 0.018, 0.07, (x, 0.18, 1.69), "gun_metal", rot=(90, 0, 0), verts=10))
            h.append(cyl("nvg_lens", 0.015, 0.004, (x, 0.216, 1.69), "nvg_glow", rot=(90, 0, 0), verts=10))
        h.append(box("goggle_band", (0.26, 0.02, 0.025), (0, 0.0, 1.69), "gear"))
    head = _join("head", h, (0, 0, 1.52))
    _parent(head, torso)
    # --- arms in a rifle-ready pose (right arm is a separate joint for hand signals)
    for side, sh_p, el_p, ha_p in (("r", (0.21, 0, 1.4), (0.24, 0.14, 1.16), (0.07, 0.3, 1.18)),
                                   ("l", (-0.21, 0, 1.4), (-0.2, 0.22, 1.2), (0.0, 0.5, 1.24))):
        a = [_between("upper", sh_p, el_p, 0.07, 0.058, U), _between("fore", el_p, ha_p, 0.056, 0.046, U)]
        a.append(_ball("glove", ha_p, (0.052, 0.065, 0.045), "glove"))
        a.append(_ball("thumb", (ha_p[0] + 0.03, ha_p[1] + 0.02, ha_p[2] + 0.02), (0.018, 0.035, 0.018), "glove", segs=8))
        a.append(_ball("elbow_pad", el_p, (0.07, 0.06, 0.06), "gear", segs=10))
        if not officer:
            a.append(box("shoulder_pad", (0.1, 0.1, 0.05), (sh_p[0] * 1.05, 0, sh_p[2] + 0.02), "gear", 0.02))
        arm = _join("arm_" + side, a, sh_p)
        _parent(arm, torso)
    # --- carbine held at the chest, pointing forward (+Y)
    gm, gp = "gun_metal", "gun_polymer"
    g = [box("g_recv", (0.05, 0.3, 0.07), (0.05, 0.3, 1.25), gm, 0.006)]
    g.append(box("g_stock", (0.045, 0.2, 0.07), (0.05, 0.06, 1.23), gp, 0.01))
    g.append(cyl("g_hand", 0.028, 0.26, (0.05, 0.56, 1.255), gp, rot=(90, 0, 22.5), verts=8))
    g.append(cyl("g_barrel", 0.011, 0.12, (0.05, 0.75, 1.255), gm, rot=(90, 0, 0), verts=10))
    g.append(box("g_mag", (0.032, 0.07, 0.15), (0.05, 0.36, 1.14), gp, 0.006, rot=(12, 0, 0)))
    g.append(box("g_grip", (0.034, 0.045, 0.1), (0.05, 0.22, 1.17), gp, 0.008, rot=(-18, 0, 0)))
    g.append(cyl("g_optic", 0.018, 0.07, (0.05, 0.32, 1.31), gm, rot=(90, 0, 0), verts=12))
    gun = _join("gun", g, (0.05, 0.3, 1.25))
    _parent(gun, torso)
    _empty("gun_tip", (0.0, 0.52, 0.005), gun)
    # Everything under a root that stands on the ground
    root = bpy.data.objects.new("soldier_root", None)
    bpy.context.collection.objects.link(root)
    _parent(pelvis, root)
    return root


def _export_rig(name):
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
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_materials="EXPORT", export_image_format="NONE")
    faces = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"exported {name}.glb  ({faces} faces)")


def soldier():
    _soldier(False)
    _export_rig("soldier")


def raskov():
    _soldier(True)
    _export_rig("raskov")


# ---------------------------------------------------------------- electrical

def _insulator(x, y, z, rings=5, r=0.09, material="porcelain"):
    for i in range(rings):
        cyl("ins_disc", r, 0.03, (x, y, z + i * 0.07), material, verts=14, bevel=0.01)
        cyl("ins_core", r * 0.35, 0.07, (x, y, z + i * 0.07 + 0.035), material, verts=10)


def transformer():
    """Substation power transformer with radiator fins, bushings and a conservator tank (origin at ground)."""
    reset()
    T = "transformer_paint"
    box("skid", (3.2, 2.2, 0.25), (0, 0, 0.125), "gun_metal", 0.02)
    box("tank", (2.6, 1.7, 2.1), (0, 0, 1.3), T, 0.04, segs=3)
    box("tank_lid", (2.75, 1.85, 0.12), (0, 0, 2.41), T, 0.03)
    # Radiator fin banks on both long sides
    for sy in (-1, 1):
        for i in range(14):
            x = -1.1 + i * 0.17
            box("fin", (0.03, 0.45, 1.7), (x, sy * 1.12, 1.3), T)
        box("fin_header_top", (2.4, 0.12, 0.1), (0, sy * 1.12, 2.2), T)
        box("fin_header_bot", (2.4, 0.12, 0.1), (0, sy * 1.12, 0.42), T)
    # Conservator (oil expansion) tank on legs
    cyl("conservator", 0.28, 2.2, (0.2, 0.55, 3.1), T, rot=(0, 90, 0), verts=20, bevel=0.02)
    for x in (-0.6, 1.0):
        box("cons_leg", (0.08, 0.08, 0.55), (x, 0.55, 2.7), "gun_metal")
    cyl("breather", 0.05, 0.4, (-0.95, 0.55, 3.35), "rust", verts=10)
    # HV bushings (tall ribbed insulators) and LV bushings
    for i, x in enumerate((-0.8, 0.0, 0.8)):
        cyl("hv_base", 0.12, 0.2, (x, -0.35, 2.55), "gun_metal", verts=12)
        _insulator(x, -0.35, 2.66, rings=9, r=0.1)
        cyl("hv_cap", 0.06, 0.12, (x, -0.35, 3.35), "copper", verts=10)
    for x in (-0.5, 0.0, 0.5):
        _insulator(x, 0.25, 2.5, rings=3, r=0.07)
    box("cable_box", (0.9, 0.4, 0.8), (1.0, -0.95, 1.2), T, 0.03)
    box("rating_plate", (0.4, 0.01, 0.28), (-0.6, -0.86, 1.6), "metal")
    box("warning", (0.3, 0.01, 0.3), (0.4, -0.86, 1.6), "hazard_sign", rot=(0, 45, 0))
    for sx in (-1.4, 1.4):
        box("ground_rod", (0.04, 0.04, 0.6), (sx, -1.0, 0.3), "copper")
    export("transformer")


def power_pole():
    """Wooden utility pole with crossarm and three pin insulators. Wire points at (+-1.05, 0, 9.05) and (0, 0, 9.35)."""
    reset()
    cyl("pole", 0.13, 9.6, (0, 0, 4.8), "pole_wood", verts=12, r2=0.1)
    box("crossarm", (2.4, 0.1, 0.12), (0, 0, 8.8), "pole_wood", 0.01)
    for sx in (-1, 1):
        box("brace", (0.05, 0.05, 0.9), (sx * 0.4, 0.07, 8.45), "gun_metal", rot=(0, sx * 35, 0))
    for x, z in ((-1.05, 8.86), (1.05, 8.86), (0.0, 9.15)):
        cyl("pin", 0.015, 0.12, (x, 0, z), "gun_metal", verts=6)
        _insulator(x, 0, z + 0.05, rings=2, r=0.055)
    cyl("cap", 0.1, 0.05, (0, 0, 9.62), "gun_metal", verts=10)
    for i in range(12):
        box("step_bolt", (0.14, 0.02, 0.02), (0, 0, 2.5 + i * 0.45), "gun_metal", rot=(0, 0, 90 if i % 2 else 0))
    box("tag", (0.1, 0.01, 0.14), (0, 0.12, 1.8), "metal")
    export("power_pole")


# ---------------------------------------------------------------- building kit

def rollup_door():
    """Segmented roll-up door, 1 x 1 m unit (scale it to the opening). Faces +Y."""
    reset()
    n = 10
    for i in range(n):
        box("panel", (1.0, 0.03, 1.0 / n - 0.004), (0, 0, (i + 0.5) / n), "door_paint", 0.004)
        box("rib", (1.0, 0.045, 0.006), (0, 0.005, i / n), "door_paint")
    box("bottom_seal", (1.0, 0.05, 0.02), (0, 0, 0.01), "black")
    box("handle", (0.08, 0.04, 0.02), (0.3, 0.03, 0.12), "metal")
    export("rollup_door")


def window_frame():
    """Aluminium window frame with a mullion and a concrete sill, 1 x 1 m unit, faces +Y."""
    reset()
    t = 0.05
    box("top", (1.0, 0.08, t), (0, 0, 1.0 - t / 2), "frame")
    box("bot", (1.0, 0.08, t), (0, 0, t / 2), "frame")
    box("left", (t, 0.08, 1.0), (-0.5 + t / 2, 0, 0.5), "frame")
    box("right", (t, 0.08, 1.0), (0.5 - t / 2, 0, 0.5), "frame")
    box("mullion", (0.035, 0.07, 1.0), (0, 0, 0.5), "frame")
    box("transom", (1.0, 0.07, 0.035), (0, 0, 0.68), "frame")
    box("sill", (1.12, 0.2, 0.06), (0, 0.06, -0.03), "concrete", 0.01)
    export("window_frame")


def hvac_unit():
    """Rooftop air-conditioning unit with fan grilles."""
    reset()
    box("case", (2.2, 1.3, 1.1), (0, 0, 0.55), "hvac_paint", 0.03)
    box("base", (2.3, 1.4, 0.1), (0, 0, 0.05), "gun_metal")
    for x in (-0.5, 0.5):
        cyl("fan_ring", 0.42, 0.06, (x, 0, 1.12), "gun_metal", verts=24)
        cyl("fan_hole", 0.38, 0.07, (x, 0, 1.12), "black", verts=24)
        for k in range(6):
            box("grille", (0.8, 0.02, 0.02), (x, 0, 1.15), "metal", rot=(0, 0, k * 30))
    for i in range(14):
        box("louvre", (0.02, 1.32, 0.6), (-1.0 + i * 0.15, 0, 0.5), "gun_metal")
    cyl("duct", 0.15, 0.8, (1.2, 0, 0.3), "metal", rot=(0, 90, 0), verts=12)
    export("hvac_unit")


def wall_lamp():
    """Industrial caged wall lamp, mounts on a wall (faces +Y, lamp hangs forward)."""
    reset()
    box("plate", (0.16, 0.03, 0.22), (0, 0, 0), "gun_metal", 0.01)
    box("arm", (0.04, 0.3, 0.04), (0, 0.15, 0.05), "gun_metal")
    cyl("shade", 0.18, 0.1, (0, 0.32, 0.02), "gun_metal", verts=16, r2=0.06)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, segments=12, ring_count=8, location=(0, 0.32, -0.06))
    _finish(bpy.context.active_object, "lamp_glass")
    for k in range(4):
        box("cage", (0.012, 0.012, 0.16), (math.cos(k * math.pi / 2) * 0.11, 0.32 + math.sin(k * math.pi / 2) * 0.11, -0.07), "gun_metal")
    export("wall_lamp")


def downpipe():
    """3 m drain pipe with brackets and a gutter hopper, faces +Y (mount on a wall)."""
    reset()
    cyl("pipe", 0.05, 3.0, (0, 0.1, 1.5), "metal", verts=10)
    cyl("shoe", 0.05, 0.2, (0, 0.18, 0.05), "metal", rot=(60, 0, 0), verts=10)
    box("hopper", (0.2, 0.18, 0.18), (0, 0.1, 3.05), "metal", 0.01)
    for z in (0.6, 1.5, 2.4):
        box("bracket", (0.14, 0.12, 0.03), (0, 0.06, z), "gun_metal")
    export("downpipe")


ALL = ["transformer", "power_pole", "rollup_door", "window_frame", "hvac_unit", "wall_lamp", "downpipe", "soldier", "raskov", "supply_truck", "technical", "helicopter", "ladder", "rifle", "container", "drum", "pallet", "crate", "jersey_barrier", "sandbags", "floodlight_head", "fallen_tree", "ak", "dmr", "pistol", "knife", "ammo_can", "intel_folder"]

if __name__ == "__main__":
    todo = [a for a in sys.argv[1:] if a in ALL] or ALL
    for a in todo:
        globals()[a]()
