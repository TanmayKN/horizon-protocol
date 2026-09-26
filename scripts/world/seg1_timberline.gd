extends Node3D
## SEGMENT 1 — The Perimeter Breach: The Timberline Outpost
## Forest slope (z < -30) -> broken fence (z = -30) -> logging yard with guard tower (z -10..36)

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const Shootable := preload("res://scripts/world/shootable.gd")

const TOWER_POS := Vector3(0, 0, 18)
const WIRE_POS := Vector3(0, 0, -30)
const GAP_HALF := 1.8

var game
var terrain
var rng := RandomNumberGenerator.new()

var search_pivot: Node3D
var search_light: SpotLight3D
var search_active := true
var search_lamp_mat: StandardMaterial3D
var wire_body: Node3D
var wire_cut := false
var sniper
var _t := 0.0


func _ready() -> void:
	rng.seed = 2026
	_build_trees()
	_build_grass()
	_build_rocks()
	_build_fence()
	_build_tower()
	_build_logging_yard()
	_build_kranor_fence()


func _process(delta: float) -> void:
	_t += delta
	if search_active:
		search_pivot.rotation.y = sin(_t * 0.32) * 1.35
		# If the searchlight catches the player, the sniper swings onto them
		if sniper and not sniper.dead() and in_light(game.player.eye_position()):
			sniper.awareness = minf(1.0, sniper.awareness + delta * 0.9)
			sniper._last_seen = game.player.global_position


func h(x: float, z: float) -> float:
	return terrain.height_at(x, z)


# ------------------------------------------------------------------ searchlight

func in_light(point: Vector3) -> bool:
	if not search_active or search_light == null or search_light.light_energy <= 0.0:
		return false
	var origin := search_light.global_position
	var to := point - origin
	var dist := to.length()
	if dist > search_light.spot_range:
		return false
	# Prone players are hard to pick out at range even when lit
	if game.player.stance == 2 and dist > 28.0:
		return false
	var fwd := -search_light.global_transform.basis.z
	if fwd.angle_to(to) > deg_to_rad(search_light.spot_angle):
		return false
	var q := PhysicsRayQueryParameters3D.create(origin, point)
	q.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


func stop_searchlight(point_down := true) -> void:
	search_active = false
	if point_down:
		var tw := create_tween()
		tw.tween_property(search_pivot, "rotation:y", search_pivot.rotation.y + 0.4, 1.5)


func _on_lamp_shot(_pos: Vector3) -> void:
	search_light.light_energy = 0.0
	search_lamp_mat.emission_energy_multiplier = 0.0
	search_active = false
	S.play3d(self, "glass", search_light.global_position, 4.0)
	game.hud.hint("Searchlight destroyed")
	if sniper and not sniper.dead():
		sniper.hear(game.player.global_position, 999.0)


# ------------------------------------------------------------------ wire

func cut_wire() -> void:
	if wire_cut:
		return
	wire_cut = true
	S.play3d(self, "cut", wire_body.global_position, 2.0)
	var tw := create_tween()
	tw.tween_property(wire_body, "rotation_degrees:x", 80.0, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_disable_wire_collision)


func _disable_wire_collision() -> void:
	for c in wire_body.get_children():
		if c is CollisionShape3D:
			c.disabled = true


# ------------------------------------------------------------------ building

func _build_trees() -> void:
	var bark := M.get_mat("bark")
	var needles := M.get_mat("needles")
	var needles_dark := M.tinted("needles", Color(0.75, 0.8, 0.75))
	var placed := 0
	var tries := 0
	while placed < 330 and tries < 9000:
		tries += 1
		var x := rng.randf_range(-118, 118)
		var z := rng.randf_range(-116, -34)
		if absf(x - terrain.road_x_at(z)) < 8.0:
			continue
		if Vector2(x, z).distance_to(Vector2(0, -52)) < 4.0:
			continue
		if absf(x) < 3.5 and z > -46.0:
			continue
		_add_tree(Vector3(x, h(x, z) - 0.3, z), rng.randf_range(11, 19), bark, needles if rng.randf() < 0.6 else needles_dark)
		placed += 1
	# Tree lines on the mountain sides around both yards
	for k in 140:
		var side := -1.0 if k % 2 == 0 else 1.0
		var x2 := side * rng.randf_range(78, 125)
		var z2 := rng.randf_range(-30, 200)
		_add_tree(Vector3(x2, h(x2, z2) - 0.3, z2), rng.randf_range(12, 20), bark, needles)
	for k in 40:
		var x3 := rng.randf_range(-120, 120)
		var z3 := rng.randf_range(185, 205)
		_add_tree(Vector3(x3, h(x3, z3) - 0.3, z3), rng.randf_range(12, 20), bark, needles_dark)


func _add_tree(pos: Vector3, height: float, bark: Material, needles: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = rng.randf() * TAU
	add_child(body)
	B.cyl(body, 0.14, 0.38, height, Vector3(0, height / 2.0, 0), bark, false, Vector3.ZERO, 10)
	var layers := rng.randi_range(9, 12)
	var start := height * rng.randf_range(0.18, 0.28)
	var spacing := (height * 0.98 - start) / layers
	for i in layers:
		var t := float(i) / layers
		var r := lerpf(3.0, 0.45, pow(t, 0.9)) * rng.randf_range(0.85, 1.12)
		var y := start + i * spacing
		var cone_h := spacing * rng.randf_range(2.2, 2.8)
		var off := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = r
		cm.height = cone_h
		cm.radial_segments = 8
		cm.rings = 2
		B.mesh(body, cm, Vector3(0, y + cone_h * 0.3, 0) + off, needles, Vector3(rng.randf_range(-8, 8), rng.randf() * 360, rng.randf_range(-8, 8)))
	var shape := CylinderShape3D.new()
	shape.radius = 0.38
	shape.height = height
	B.add_shape(body, shape, Vector3(0, height / 2.0, 0))


func _build_grass() -> void:
	var quad := _crossed_quads(0.9, 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	var count := 9000
	mm.instance_count = count
	var n := 0
	var tries := 0
	while n < count and tries < count * 3:
		tries += 1
		var x := rng.randf_range(-100, 100)
		var z := rng.randf_range(-112, 32)
		var road_d := absf(x - terrain.road_x_at(z))
		if road_d < 4.5:
			continue
		if z > -10.0 and rng.randf() < 0.75:
			continue   # sparse in the gravel yard
		var s := rng.randf_range(0.6, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s))
		mm.set_instance_transform(n, Transform3D(basis, Vector3(x, h(x, z) - 0.05, z)))
		n += 1
	mm.visible_instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = M.get_mat("grass")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 70.0
	add_child(mmi)


func _crossed_quads(w: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := k * PI / 2.0
		var dx := cos(a) * w / 2.0
		var dz := sin(a) * w / 2.0
		var p0 := Vector3(-dx, 0, -dz)
		var p1 := Vector3(dx, 0, dz)
		var p2 := Vector3(dx, height, dz)
		var p3 := Vector3(-dx, height, -dz)
		for v in [[p0, Vector2(0, 1)], [p1, Vector2(1, 1)], [p2, Vector2(1, 0)], [p0, Vector2(0, 1)], [p2, Vector2(1, 0)], [p3, Vector2(0, 0)]]:
			st.set_normal(Vector3.UP)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _build_rocks() -> void:
	var rock := M.tinted("concrete", Color(0.45, 0.46, 0.44))
	for i in 45:
		var x := rng.randf_range(-100, 100)
		var z := rng.randf_range(-110, -36)
		if absf(x - terrain.road_x_at(z)) < 7.0 or (absf(x) < 4.0 and z > -45.0):
			continue
		var s := rng.randf_range(0.6, 2.2)
		var body := StaticBody3D.new()
		body.position = Vector3(x, h(x, z) + s * 0.2, z)
		body.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf())
		add_child(body)
		var sm := SphereMesh.new()
		sm.radius = s
		sm.height = s * 1.3
		sm.radial_segments = 8
		sm.rings = 5
		B.mesh(body, sm, Vector3.ZERO, rock)
		var shape := SphereShape3D.new()
		shape.radius = s * 0.7
		B.add_shape(body, shape, Vector3.ZERO)


func _fence_line(z: float, x0: float, x1: float, gap_min: float, gap_max: float, height := 2.4) -> void:
	var post := M.get_mat("metal")
	var link := M.get_mat("chainlink")
	var x := x0
	while x < x1:
		var mid := x + 1.5
		var gy := h(mid, z)
		if not (x > gap_min and x < gap_max):
			B.cyl(self, 0.05, 0.05, height + 0.4, Vector3(x, h(x, z) + (height + 0.4) / 2.0 - 0.2, z), post, true, Vector3.ZERO, 6)
		if mid < gap_min or mid > gap_max:
			B.box(self, Vector3(3.0, height, 0.04), Vector3(mid, gy + height / 2.0, z), link)
			# Barbed wire strands
			for k in 3:
				B.box(self, Vector3(3.0, 0.015, 0.015), Vector3(mid, gy + height + 0.05 + k * 0.12, z - k * 0.05), post, false)
		x += 3.0


func _build_fence() -> void:
	_fence_line(WIRE_POS.z, -118.0, 118.0, -GAP_HALF - 1.5, GAP_HALF + 1.5)
	var link := M.get_mat("chainlink")
	var post := M.get_mat("metal")
	# Posts either side of the gap (leaning, damaged)
	B.cyl(self, 0.05, 0.05, 2.8, Vector3(-3.0, h(-3, WIRE_POS.z) + 1.2, WIRE_POS.z), post, true, Vector3(0, 0, 8), 6)
	B.cyl(self, 0.05, 0.05, 2.8, Vector3(3.0, h(3, WIRE_POS.z) + 1.2, WIRE_POS.z), post, true, Vector3(0, 0, -14), 6)
	# The sagging wire section that has to be cut
	wire_body = StaticBody3D.new()
	wire_body.position = Vector3(0, h(0, WIRE_POS.z), WIRE_POS.z)
	add_child(wire_body)
	B.box(wire_body, Vector3(6.0, 1.6, 0.03), Vector3(0, 0.8, 0), link, false, Vector3(0, 0, 3))
	B.add_shape(wire_body, _box_shape(Vector3(6.0, 1.6, 0.3)), Vector3(0, 0.8, 0))
	# A torn panel lying in the mud
	B.box(self, Vector3(3.0, 2.2, 0.03), Vector3(-5.5, h(-5.5, WIRE_POS.z - 1.5) + 0.2, WIRE_POS.z - 1.5), link, false, Vector3(-82, 15, 0))
	B.label3d(self, "RESTRICTED AREA\nTIMBERLINE LOGGING CO.", Vector3(8, h(8, WIRE_POS.z) + 1.4, WIRE_POS.z - 0.05), 28, Color(0.85, 0.2, 0.15), Vector3(0, 180, 0))


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _build_tower() -> void:
	var wood := M.get_mat("wood")
	var metal := M.get_mat("rust")
	var p := TOWER_POS
	for sx in [-1.6, 1.6]:
		for sz in [-1.6, 1.6]:
			B.box(self, Vector3(0.3, 9.0, 0.3), p + Vector3(sx, 4.5, sz), wood)
	# Cross bracing
	for s in [-1.6, 1.6]:
		B.box(self, Vector3(0.12, 0.12, 4.6), p + Vector3(s, 4.5, 0), wood, false, Vector3(52, 0, 0))
		B.box(self, Vector3(4.6, 0.12, 0.12), p + Vector3(0, 4.5, s), wood, false, Vector3(0, 0, 52))
	B.box(self, Vector3(4.4, 0.3, 4.4), p + Vector3(0, 9.0, 0), wood)
	for s in [-1, 1]:
		B.box(self, Vector3(4.4, 1.0, 0.12), p + Vector3(0, 9.65, s * 2.15), wood)
		B.box(self, Vector3(0.12, 1.0, 4.4), p + Vector3(s * 2.15, 9.65, 0), wood)
	for sx in [-2.1, 2.1]:
		for sz in [-2.1, 2.1]:
			B.box(self, Vector3(0.12, 2.6, 0.12), p + Vector3(sx, 10.4, sz), wood, false)
	B.box(self, Vector3(5.0, 0.2, 5.0), p + Vector3(0, 11.8, 0), M.get_mat("corrugated"), true, Vector3(4, 0, 0))
	for rung in 18:
		B.box(self, Vector3(0.8, 0.05, 0.05), p + Vector3(0, 0.4 + rung * 0.5, 2.3), metal, false)

	# Searchlight (volumetric beam through the drizzle)
	search_pivot = Node3D.new()
	search_pivot.position = p + Vector3(0, 10.5, -1.2)
	add_child(search_pivot)
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -13.0
	search_pivot.add_child(tilt)
	var lamp := StaticBody3D.new()
	lamp.set_script(Shootable)
	tilt.add_child(lamp)
	var hm := CylinderMesh.new()
	hm.top_radius = 0.36
	hm.bottom_radius = 0.3
	hm.height = 0.7
	B.mesh(lamp, hm, Vector3.ZERO, metal, Vector3(90, 0, 0))
	search_lamp_mat = M.emissive(Color(1, 0.97, 0.85), 8.0).duplicate()
	var lens := CylinderMesh.new()
	lens.top_radius = 0.32
	lens.bottom_radius = 0.32
	lens.height = 0.02
	B.mesh(lamp, lens, Vector3(0, 0, -0.36), search_lamp_mat, Vector3(90, 0, 0))
	B.add_shape(lamp, _box_shape(Vector3(0.7, 0.7, 0.8)), Vector3.ZERO)
	lamp.shot.connect(_on_lamp_shot)

	search_light = SpotLight3D.new()
	search_light.position = Vector3(0, 0, -0.4)
	search_light.light_energy = 14.0
	search_light.light_color = Color(1.0, 0.96, 0.85)
	search_light.spot_range = 75.0
	search_light.spot_angle = 10.0
	search_light.spot_attenuation = 0.6
	search_light.shadow_enabled = true
	search_light.light_volumetric_fog_energy = 3.0
	tilt.add_child(search_light)


func _build_logging_yard() -> void:
	var log_mat := M.get_mat("log")
	# Log stacks lining the muddy road
	var z := -8.0
	while z < 32.0:
		for side in [-1, 1]:
			if rng.randf() < 0.8:
				var x: float = terrain.road_x_at(z) + side * (terrain.ROAD_HALF + 2.3)
				_log_stack(Vector3(x, h(x, z), z + rng.randf_range(-1.5, 1.5)), log_mat, 0.0)
		z += 9.0
	# Cover between the fence and the tower
	_log_stack(Vector3(-5, h(-5, -4), -4), log_mat, 90.0)
	_log_stack(Vector3(6, h(6, 4), 4), log_mat, 20.0)
	_log_stack(Vector3(-9, h(-9, 12), 12), log_mat, 70.0)
	# Loose logs on the slope
	for i in 10:
		var x := rng.randf_range(-40, 40)
		var zz := rng.randf_range(-28, -12)
		B.cyl(self, 0.3, 0.3, rng.randf_range(4, 7), Vector3(x, h(x, zz) + 0.3, zz), log_mat, true, Vector3(0, rng.randf() * 180, 90), 10)

	# Sawmill shed
	var shed := Vector3(-28, 0, 8)
	var wood := M.get_mat("wood")
	for sx in [-5.0, 5.0]:
		for sz in [-4.0, 4.0]:
			B.box(self, Vector3(0.3, 4.5, 0.3), shed + Vector3(sx, 2.25, sz), wood)
	B.box(self, Vector3(11.5, 0.15, 9.5), shed + Vector3(0, 4.6, 0), M.get_mat("corrugated"), true, Vector3(0, 0, 5))
	B.box(self, Vector3(6, 0.9, 1.4), shed + Vector3(0, 0.45, 0), M.get_mat("rust"))
	B.cyl(self, 0.7, 0.7, 0.05, shed + Vector3(0, 1.1, 0), M.get_mat("metal"), false, Vector3(90, 0, 0), 24)
	B.label3d(self, "TIMBERLINE LOGGING CO.", shed + Vector3(0, 4.2, 4.3), 48, Color(0.9, 0.85, 0.7))
	B.omni(self, shed + Vector3(0, 4.0, 0), Color(1.0, 0.75, 0.45), 1.2, 12.0)

	# Log loader vehicle
	var yel := M.tinted("rust", Color(0.85, 0.65, 0.15))
	var lv := Vector3(34, 0, 2)
	B.box(self, Vector3(3, 1.6, 6), lv + Vector3(0, 1.3, 0), yel)
	B.box(self, Vector3(2.4, 1.6, 2.2), lv + Vector3(0, 2.9, -1.4), yel)
	B.box(self, Vector3(2.2, 1.2, 2.0), lv + Vector3(0, 3.0, -1.4), M.get_mat("glass"), false)
	B.box(self, Vector3(0.4, 0.4, 7), lv + Vector3(0, 4.5, 3.0), yel, false, Vector3(-25, 0, 0))
	for wx in [-1.6, 1.6]:
		for wz in [-2.0, 2.0]:
			B.cyl(self, 0.7, 0.7, 0.6, lv + Vector3(wx, 0.7, wz), M.get_mat("black"), false, Vector3(0, 0, 90), 14)
	# Fuel drums
	for i in 7:
		var dp := Vector3(10 + (i % 3) * 0.75, 0, 28 + (i / 3) * 0.75)
		B.cyl(self, 0.3, 0.3, 0.9, dp + Vector3(0, 0.45, 0), M.tinted("rust", Color(0.55, 0.2, 0.15)), true, Vector3.ZERO, 12)
	# Work lights on poles
	for lp in [Vector3(12, 0, -2), Vector3(-14, 0, 24), Vector3(28, 0, 24)]:
		B.cyl(self, 0.08, 0.1, 6.0, lp + Vector3(0, 3.0, 0), M.get_mat("metal"), true, Vector3.ZERO, 8)
		B.box(self, Vector3(0.5, 0.25, 0.3), lp + Vector3(0, 6.0, 0), M.emissive(Color(1, 0.8, 0.5), 3.0), false)
		B.spot(self, lp + Vector3(0, 5.9, 0), Vector3(-90, 0, 0), Color(1.0, 0.78, 0.5), 3.0, 16.0, 55.0, false)


func _log_stack(base: Vector3, material: Material, yaw: float) -> void:
	var r := 0.36
	var length := 6.0
	var body := StaticBody3D.new()
	body.position = base
	body.rotation_degrees.y = yaw
	add_child(body)
	for row in 3:
		var count := 4 - row
		for n in count:
			var ox := (n - (count - 1) / 2.0) * r * 2.02
			var pos := Vector3(ox, r + row * r * 1.72, rng.randf_range(-0.2, 0.2))
			B.cyl(body, r * rng.randf_range(0.9, 1.05), r, length, pos, material, false, Vector3(90, 0, 0), 12)
	B.add_shape(body, _box_shape(Vector3(r * 8.0, r * 2.0 * 2.7, length)), Vector3(0, r * 2.7, 0))


func _build_kranor_fence() -> void:
	var zf: float = terrain.YARD_Z
	_fence_line(zf, -80.0, 80.0, 13.5, 26.5, 3.0)
	var metal := M.get_mat("metal")
	# Open gate
	B.box(self, Vector3(0.4, 3.4, 0.4), Vector3(13.5, 1.7, zf), M.get_mat("concrete"))
	B.box(self, Vector3(0.4, 3.4, 0.4), Vector3(26.5, 1.7, zf), M.get_mat("concrete"))
	B.box(self, Vector3(6.0, 2.6, 0.08), Vector3(11.0, 1.4, zf + 2.5), M.get_mat("chainlink"), true, Vector3(0, -70, 0))
	B.box(self, Vector3(13.4, 0.35, 0.35), Vector3(20, 3.6, zf), M.get_mat("hazard"), false)
	B.label3d(self, "KRANOR LOGISTICS\nAUTHORIZED PERSONNEL ONLY", Vector3(20, 4.3, zf - 0.2), 40, Color(0.95, 0.85, 0.3), Vector3(0, 180, 0))
	B.box(self, Vector3(2.4, 2.6, 2.4), Vector3(29.5, 1.3, zf + 2.0), M.get_mat("corrugated"))   # guard booth
	B.box(self, Vector3(2.5, 0.15, 2.5), Vector3(29.5, 2.7, zf + 2.0), metal, false)
	B.omni(self, Vector3(20, 4.5, zf + 1.0), Color(1, 0.9, 0.7), 2.5, 14.0)
