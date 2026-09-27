import bpy, os, sys, math
from mathutils import Vector
MD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models")
out = sys.argv[-1]
names = sys.argv[sys.argv.index("--")+1:-1] if "--" in sys.argv else []
for n in names:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MD, n + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    ctr = (mn + mx) / 2; size = (mx - mn).length
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.collection.objects.link(cam)
    cam.location = ctr + Vector((size*0.9, -size*1.1, size*0.6))
    d = ctr - cam.location; cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_cavity = True
    sc.render.resolution_x = 400; sc.render.resolution_y = 300
    sc.render.filepath = os.path.join(out, n + ".png")
    bpy.ops.render.render(write_still=True)
