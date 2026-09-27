import bpy, os, sys, math
from mathutils import Vector
MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models")
out = sys.argv[-1]
names = sys.argv[sys.argv.index("--")+1:-1] if "--" in sys.argv else []
for n in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MD, n + ".glb"))
    COLORS = {"uniform": (0.25,0.28,0.2,1), "coat": (0.15,0.16,0.14,1), "gear": (0.08,0.09,0.08,1), "gear_light": (0.3,0.28,0.2,1),
              "boot": (0.18,0.13,0.09,1), "balaclava": (0.12,0.11,0.1,1), "helmet": (0.3,0.32,0.25,1), "nvg_glow": (0.3,1,0.4,1),
              "gun_metal": (0.05,0.05,0.05,1), "gun_polymer": (0.35,0.3,0.2,1), "glove": (0.1,0.1,0.09,1), "beret": (0.5,0.05,0.05,1),
              "skin": (0.75,0.55,0.45,1), "patch": (0.6,0.1,0.1,1), "metal": (0.6,0.6,0.6,1),
              "transformer_paint": (0.4,0.45,0.42,1), "porcelain": (0.45,0.3,0.2,1), "copper": (0.7,0.4,0.2,1), "pole_wood": (0.35,0.25,0.15,1),
              "door_paint": (0.6,0.62,0.6,1), "frame": (0.5,0.5,0.52,1), "hvac_paint": (0.75,0.75,0.72,1), "black": (0.02,0.02,0.02,1)}
    for m in bpy.data.materials:
        if m.name in COLORS:
            m.diffuse_color = COLORS[m.name]
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    ctr = (mn + mx) / 2; size = (mx - mn).length
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam)
    cam.location = ctr + (Vector((size*0.55, size*1.0, size*0.15)) if n in ("soldier","raskov") else Vector((size*0.9, -size*1.1, size*0.6)))
    d = ctr - cam.location; cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = True
    sc.render.resolution_x = 400; sc.render.resolution_y = 300
    sc.render.filepath = os.path.join(out, n + ".png")
    bpy.ops.render.render(write_still=True)
