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
			return M.tinted("metal", tint)
		"glass":
			return M.get_mat("glass")
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
