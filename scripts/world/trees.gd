extends Node3D
## Batched pine trees (same look as the forest in Segment 1). Add trees, then flush() once.
##   var t := Trees.new(); add_child(t); t.add_tree(pos, h, needles); t.flush()

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")

var rng := RandomNumberGenerator.new()


func add_tree(pos: Vector3, height: float, dark := false) -> void:
	_add_tree(pos, height, M.get_mat("bark"), M.tinted("needles", Color(0.75, 0.8, 0.75)) if dark else M.get_mat("needles"))


func flush() -> void:
	_flush_trees()


var _trunks: Array = []
var _cones: Array = []        # [Transform3D, dark?]
var _cards: Array = []        # branch cards (Transform3D)


func _add_tree(pos: Vector3, height: float, _bark: Material, needles: Material) -> void:
	# Collision only; the visuals are batched into MultiMeshes (see _flush_trees)
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = height
	B.add_shape(body, shape, Vector3(0, height / 2.0, 0))
	var yaw := rng.randf() * TAU
	var base := Basis(Vector3.UP, yaw)
	_trunks.append(Transform3D(base.scaled(Vector3(0.38, height, 0.38)), pos + Vector3(0, height / 2.0, 0)))
	var dark := needles != M.get_mat("needles")
	var use_cards := M.tex("pine_card_albedo") != null
	var start := height * rng.randf_range(0.2, 0.3)
	if use_cards:
		# Whorls of drooping branch cards around the trunk + a dark inner core
		var whorls := int(height / 0.9)
		for i in whorls:
			var t := float(i) / whorls
			var y := lerpf(start, height * 0.98, t)
			var length := lerpf(3.4, 0.5, pow(t, 0.85)) * rng.randf_range(0.85, 1.15)
			var count := 6 if t < 0.8 else 4
			var yaw0 := rng.randf() * TAU
			for k in count:
				var yaw_k := yaw0 + k * TAU / count + rng.randf_range(-0.25, 0.25)
				var droop := deg_to_rad(lerpf(28.0, 8.0, t) + rng.randf_range(-6, 8))
				var bb := Basis(Vector3.UP, yaw_k) * Basis(Vector3.BACK, -droop)
				_cards.append(Transform3D(bb.scaled(Vector3(length, length, length)), pos + Vector3(0, y, 0)))
		for i in 3:
			var ct := float(i) / 3.0
			var cr := lerpf(1.4, 0.4, ct)
			var ch := (height - start) * 0.45
			_cones.append([Transform3D(Basis().scaled(Vector3(cr, ch, cr)), pos + Vector3(0, start + ch * 0.5 + ct * (height - start) * 0.5, 0)), true])
		return
	var layers := rng.randi_range(9, 12)
	var spacing := (height * 0.98 - start) / layers
	for i in layers:
		var t := float(i) / layers
		var r := lerpf(3.0, 0.45, pow(t, 0.9)) * rng.randf_range(0.85, 1.12)
		var y := start + i * spacing
		var cone_h := spacing * rng.randf_range(2.2, 2.8)
		var off := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var b := Basis.from_euler(Vector3(deg_to_rad(rng.randf_range(-8, 8)), rng.randf() * TAU, deg_to_rad(rng.randf_range(-8, 8))))
		_cones.append([Transform3D(b.scaled(Vector3(r, cone_h, r)), pos + Vector3(0, y + cone_h * 0.3, 0) + off), dark])


static func branch_card_mesh() -> ArrayMesh:
	# Two crossed quads from x = 0 (trunk) to x = 1 (branch tip)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := [
		[Vector3(0, 0, -0.45), Vector3(1, 0, -0.45), Vector3(1, 0, 0.45), Vector3(0, 0, 0.45), Vector3.UP],
		[Vector3(0, 0.45, 0), Vector3(1, 0.45, 0), Vector3(1, -0.45, 0), Vector3(0, -0.45, 0), Vector3.BACK],
	]
	for q in quads:
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(q[4])
			st.set_uv(uvs[idx])
			st.add_vertex(q[idx])
	return st.commit()


func _flush_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.37
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 8
	trunk_mesh.rings = 1
	_multimesh(trunk_mesh, _trunks, M.get_mat("bark"))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 2
	var light: Array = []
	var dark: Array = []
	for c in _cones:
		(dark if c[1] else light).append(c[0])
	_multimesh(cone, light, M.get_mat("needles"))
	_multimesh(cone, dark, M.tinted("needles", Color(0.45, 0.5, 0.45)))
	if not _cards.is_empty():
		_multimesh(branch_card_mesh(), _cards, M.get_mat("pine_card"))
	_trunks.clear()
	_cones.clear()
	_cards.clear()


func _multimesh(m: Mesh, xforms: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


