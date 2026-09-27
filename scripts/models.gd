extends RefCounted
## Loads the Blender-made models in res://assets/models and applies the game's realistic materials.
## Usage: const MD := preload("res://scripts/models.gd")   MD.place(parent, "drum", pos)

const M := preload("res://scripts/mats.gd")

static var _scenes := {}


static func available(name: String) -> bool:
	return ResourceLoader.exists("res://assets/models/%s.glb" % name)


static func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		_scenes[name] = load("res://assets/models/%s.glb" % name) if available(name) else null
	return _scenes[name]


## Material for a surface named in Blender
static func material_for(mat_name: String, tint: Color) -> Material:
	var n := mat_name.to_lower()
	match n:
		"container_paint":
			return M.tinted("corrugated", tint)
		"drum_paint":
			return M.tinted("rust", tint)
		"sandbag":
			return M.tinted("concrete", Color(0.62, 0.55, 0.4))
		"lamp_glass":
			return M.emissive(Color(1, 0.97, 0.9), 5.0)
		"tail_light":
			return M.emissive(Color(1, 0.08, 0.05), 3.0)
		"truck_paint", "heli_paint":
			return vehicle_paint(tint, 0.9 if n == "truck_paint" else -5.0)
		"glass":
			return M.get_mat("glass")
		"ammo_paint":
			return vehicle_paint(tint if tint != Color.WHITE else Color(0.32, 0.36, 0.25), -5.0)
		"stencil":
			return M.emissive(Color(0.95, 0.8, 0.2), 0.25)
		"folder_red":
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.55, 0.08, 0.06)
			fm.roughness = 0.8
			return fm
		"paper":
			var pm2 := StandardMaterial3D.new()
			pm2.albedo_color = Color(0.92, 0.9, 0.84)
			pm2.roughness = 0.9
			return pm2
		"photo":
			var ph := StandardMaterial3D.new()
			ph.albedo_color = Color(0.25, 0.27, 0.3)
			ph.roughness = 0.3
			return ph
		"canvas":
			var cv: StandardMaterial3D = M.tinted("concrete", Color(0.5, 0.48, 0.35)).duplicate()
			cv.cull_mode = BaseMaterial3D.CULL_DISABLED
			cv.roughness = 1.0
			return cv
		"rim_paint":
			return vehicle_paint(Color(0.28, 0.31, 0.23), -5.0)
		"jerry_paint":
			return vehicle_paint(Color(0.24, 0.3, 0.19), -5.0)
		"transformer_paint":
			return vehicle_paint(Color(0.4, 0.45, 0.42), -5.0)
		"hvac_paint":
			return vehicle_paint(Color(0.72, 0.73, 0.7), -5.0)
		"door_paint":
			return M.tinted("corrugated", Color(0.62, 0.64, 0.62))
		"frame":
			return M.tinted("metal", Color(0.5, 0.52, 0.55))
		"porcelain":
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.42, 0.26, 0.16)
			pm.roughness = 0.15
			return pm
		"copper":
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.72, 0.42, 0.24)
			cm.metallic = 0.9
			cm.roughness = 0.35
			return cm
		"pole_wood":
			return M.tinted("log", Color(0.55, 0.45, 0.36))
		"hazard_sign":
			return M.get_mat("hazard")
		"uniform":
			return M.get_mat("uniform")
		"coat":
			return M.tinted("uniform", Color(0.45, 0.47, 0.42))
		"gear_light":
			return M.tinted("gear", Color(0.32, 0.3, 0.22))
		"boot":
			return M.tinted("gear", Color(0.2, 0.15, 0.1))
		"balaclava":
			return M.tinted("gear", Color(0.14, 0.13, 0.12))
		"helmet":
			return M.tinted("uniform", Color(0.8, 0.82, 0.72))
		"glove":
			return M.tinted("gear", Color(0.12, 0.12, 0.11))
		"nvg_glow":
			return M.emissive(Color(0.3, 1.0, 0.4), 2.5)
		"beret":
			return M.tinted("gear", Color(0.45, 0.05, 0.05))
		"skin":
			return M.tinted("gear", Color(0.72, 0.55, 0.45))
		"patch":
			return M.tinted("gear", Color(0.6, 0.12, 0.1))
		"metal", "rust", "gun_metal", "gun_polymer", "gear", "black", "wood", "concrete", "bark", "log":
			return M.get_mat(n)
	return M.get_mat("metal")


static var _paints := {}


## Matte military paint with worn edges and mud on the lower body
static func vehicle_paint(tint: Color, mud_height: float) -> Material:
	var key := "%s_%f" % [tint.to_html(), mud_height]
	if _paints.has(key):
		return _paints[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/vehicle.gdshader")
	sm.set_shader_parameter("paint", tint)
	sm.set_shader_parameter("grime", M.tex("painted_metal_albedo"))
	sm.set_shader_parameter("grime_n", M.tex("painted_metal_normal"))
	sm.set_shader_parameter("mud_height", mud_height)
	_paints[key] = sm
	return sm


## Instance a model. `tint` colours painted parts (containers, drums).
static func place(parent: Node, name: String, pos: Vector3, rot_deg := Vector3.ZERO, scale := Vector3.ONE, tint := Color.WHITE) -> Node3D:
	var sc := _scene(name)
	if sc == null:
		return null
	var inst: Node3D = sc.instantiate()
	inst.position = pos
	inst.rotation_degrees = rot_deg
	inst.scale = scale
	parent.add_child(inst)
	apply_materials(inst, tint)
	return inst


static func apply_materials(root: Node, tint := Color.WHITE) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var nm: String = src.resource_name if src else String(m.name)
			m.set_surface_override_material(i, material_for(nm, tint))


## Many copies of one model drawn with MultiMeshes (one per part). colors tint the painted parts.
static func multi(parent: Node, name: String, xforms: Array, colors: Array = []) -> void:
	var sc := _scene(name)
	if sc == null or xforms.is_empty():
		return
	var tmp: Node3D = sc.instantiate()
	for mi in tmp.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var local: Transform3D = _global_in(tmp, m)
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var nm: String = src.resource_name if src else String(m.name)
			var painted: bool = nm.to_lower() in ["container_paint", "drum_paint"]
			var surf_mesh := ArrayMesh.new()
			surf_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.mesh.surface_get_arrays(i))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = painted and not colors.is_empty()
			mm.mesh = surf_mesh
			mm.instance_count = xforms.size()
			for k in xforms.size():
				mm.set_instance_transform(k, xforms[k] * local)
				if mm.use_colors:
					mm.set_instance_color(k, colors[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var mat: Material = material_for(nm, Color.WHITE)
			if mm.use_colors:
				var pm: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
				pm.vertex_color_use_as_albedo = true
				mat = pm
			mmi.material_override = mat
			parent.add_child(mmi)
	tmp.free()


static func _global_in(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
