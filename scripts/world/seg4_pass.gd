extends Node3D
## SEGMENT 4 — The Escape Vector: The Mountain Access Pass
## A scripted truck ride. Vance stays in first person in the truck bed and fights off pursuers.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const TechScript := preload("res://scripts/technical.gd")
const MD := preload("res://scripts/models.gd")

const ROAD_W := 8.0
const PASS_START_Z := 200.0

var game
var curve := Curve3D.new()
var length := 0.0
var truck: Node3D
var bed_anchor: Node3D
var active := false
var s := 0.0                  # distance travelled along the road
var speed := 0.0
var target_speed := 16.0
var techs: Array = []
var events: Array = []        # [distance, name, done]
var checkpoint_s := 0.0
var branches: Array = []      # [distance, node, done]
var _bounce_t := 0.0
var _engine: AudioStreamPlayer3D
var _river: AudioStreamPlayer3D
var _roadblock_nodes: Array = []
var _leap_t := -1.0
var _leap_from := Vector3.ZERO
var rng := RandomNumberGenerator.new()

# Named distances (filled in _ready)
var s_window := 0.0
var s_gate := 0.0
var s_bridge_a := 0.0
var s_bridge_b := 0.0
var s_tunnel := 0.0
var s_roadblock := 0.0
var s_end := 0.0


func _ready() -> void:
	rng.seed = 77
	for p in [Vector3(27, 0, 64), Vector3(31, 0, 96), Vector3(31, 0, 112), Vector3(24, 0, 132), Vector3(15, 0, 156),
			Vector3(15, 0, 184), Vector3(15, 0.2, 206), Vector3(11, 1.2, 232), Vector3(0, 3, 262), Vector3(-22, 6, 292),
			Vector3(-38, 8, 324), Vector3(-42, 9, 352), Vector3(-40, 10, 384), Vector3(-30, 12, 410), Vector3(-8, 14, 434),
			Vector3(16, 15, 452), Vector3(32, 16, 478), Vector3(36, 17, 512), Vector3(26, 18, 546), Vector3(14, 19, 574),
			Vector3(10, 19, 600), Vector3(10, 19, 626)]:
		curve.add_point(p)
	# Smooth the corners
	for i in range(1, curve.point_count - 1):
		var prev := curve.get_point_position(i - 1)
		var next := curve.get_point_position(i + 1)
		var t := (next - prev) * 0.22
		curve.set_point_in(i, -t)
		curve.set_point_out(i, t)
	curve.bake_interval = 0.5
	length = curve.get_baked_length()
	s_window = _closest_s(Vector3(31, 0, 111.5))
	s_gate = _closest_s(Vector3(15, 0, 184))
	s_bridge_a = _closest_s(Vector3(-42, 9, 348))
	s_bridge_b = _closest_s(Vector3(-40, 10, 388))
	s_tunnel = _closest_s(Vector3(-8, 14, 434))
	s_roadblock = _closest_s(Vector3(14, 19, 574))
	s_end = length - 6.0
	events = [
		[s_gate - 3.0, "gate", false],
		[s_gate + 30.0, "techs1", false],
		[s_bridge_a - 45.0, "bridge_warn", false],
		[s_bridge_a, "bridge", false],
		[s_bridge_b + 25.0, "techs2", false],
		[s_tunnel - 25.0, "tunnel", false],
		[s_roadblock - 60.0, "roadblock_warn", false],
		[s_roadblock - 4.0, "roadblock", false],
		[s_end - 20.0, "bunker_gate", false],
		[s_end, "crash", false],
	]
	_build_pass()
	_build_truck()


func pos_at(dist: float) -> Vector3:
	return curve.sample_baked(clampf(dist, 0.0, length), true)


func dir_at(dist: float) -> Vector3:
	var a := pos_at(dist - 1.0)
	var b := pos_at(dist + 1.0)
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


func _closest_s(p: Vector3) -> float:
	return curve.get_closest_offset(p)


# ------------------------------------------------------------------ building

func _build_pass() -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cliff := SurfaceTool.new()
	cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drop := SurfaceTool.new()
	drop.begin(Mesh.PRIMITIVE_TRIANGLES)
	var start_s := _closest_s(Vector3(15, 0, PASS_START_Z))
	var step := 2.0
	var d := start_s
	var prev: Dictionary = {}
	while d <= length:
		var p := pos_at(d)
		if p.z > 602.0:
			break
		var f := dir_at(d)
		var left := Vector3.UP.cross(f).normalized()
		var on_bridge := d > s_bridge_a and d < s_bridge_b
		var n := rng.randf_range(-1, 1)
		var cur := {
			"rl": p + left * ROAD_W / 2.0, "rr": p - left * ROAD_W / 2.0,
			"c0": p + left * (ROAD_W / 2.0 + 0.5), "c1": p + left * (ROAD_W / 2.0 + 4.0) + Vector3(0, 20.0 + n * 3.0, 0), "c2": p + left * 26.0 + Vector3(0, 24.0 + n * 2.0, 0),
			"d0": p - left * (ROAD_W / 2.0 + 0.3), "d1": p - left * (ROAD_W / 2.0 + 5.0) + Vector3(0, -38.0, 0), "d2": p - left * 45.0 + Vector3(0, -44.0, 0),
			"bridge": on_bridge,
		}
		if on_bridge:
			# Both sides fall away into the gorge
			cur.c0 = p + left * (ROAD_W / 2.0 + 0.3)
			cur.c1 = p + left * (ROAD_W / 2.0 + 5.0) + Vector3(0, -38.0, 0)
			cur.c2 = p + left * 45.0 + Vector3(0, -44.0, 0)
		if not prev.is_empty():
			_quad(road, prev.rl, cur.rl, cur.rr, prev.rr, Color(0.3, 0.24, 0.17))
			_quad(cliff, prev.c1, cur.c1, cur.c0, prev.c0, Color(0.42, 0.41, 0.38))
			_quad(cliff, prev.c2, cur.c2, cur.c1, prev.c1, Color(0.24, 0.3, 0.18))
			_quad(drop, prev.d0, cur.d0, cur.d1, prev.d1, Color(0.4, 0.39, 0.36))
			_quad(drop, prev.d1, cur.d1, cur.d2, prev.d2, Color(0.28, 0.32, 0.22))
		prev = cur
		# Foliage on the cliff side
		if not on_bridge and rng.randf() < 0.45:
			var tp: Vector3 = p + left * rng.randf_range(ROAD_W / 2.0 + 4.5, 20.0)
			tp.y = p.y + 21.0 + rng.randf_range(-1, 2)
			_tree(tp, rng.randf_range(8, 15))
		if not on_bridge and rng.randf() < 0.3:
			var bp: Vector3 = p + left * (ROAD_W / 2.0 + 1.0)
			_bush(bp)
		# Stone guard wall on the drop side, with gaps
		if not on_bridge and rng.randf() < 0.55:
			var wp: Vector3 = p - left * (ROAD_W / 2.0 + 0.2) + Vector3(0, 0.35, 0)
			var wall := B.box(self, Vector3(0.4, 0.7, 2.0), wp, M.tinted("concrete", Color(0.55, 0.52, 0.48)), false)
			wall.look_at(wp + f, Vector3.UP)
		# Branches reaching over the road (they snap when the truck hits them)
		if not on_bridge and rng.randf() < 0.06:
			var br := Node3D.new()
			br.position = p + left * 3.0 + Vector3(0, 3.2, 0)
			add_child(br)
			var limb := B.cyl(br, 0.05, 0.12, 5.0, Vector3(-0.0, 0, 0), M.get_mat("bark"), false, Vector3(0, 0, 90), 6)
			limb.look_at_from_position(br.global_position, br.global_position - left, Vector3.UP)
			limb.rotate_object_local(Vector3.RIGHT, PI / 2)
			var leaves := B.mesh(br, SphereMesh.new(), -left * 2.2, M.get_mat("needles"))
			leaves.scale = Vector3(1.6, 0.8, 1.6)
			branches.append([d, br, false])
		d += step
	for st in [[road, M.tinted("mud", Color(0.3, 0.25, 0.2)), true], [cliff, M.get_mat("ground"), true], [drop, M.get_mat("ground"), false]]:
		var surf: SurfaceTool = st[0]
		surf.generate_normals()
		var mesh := surf.commit()
		var mat: StandardMaterial3D = st[1]
		if st[1] == M.get_mat("ground"):
			mat = st[1]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		if st[0] == road:
			var rm := M.get_mat("ground").duplicate()
			rm.roughness = 0.4
			mi.material_override = rm
		add_child(mi)
		if st[2]:
			var body := StaticBody3D.new()
			add_child(body)
			var cs := CollisionShape3D.new()
			cs.shape = mesh.create_trimesh_shape()
			body.add_child(cs)

	# Valley floor far below + distant mountains
	B.box(self, Vector3(900, 1, 700), Vector3(0, -40, 520), M.tinted("ground", Color(0.2, 0.26, 0.17)), false)
	for i in 40:
		var side := -1.0 if i % 2 == 0 else 1.0
		var mp := Vector3(side * rng.randf_range(140, 320), -40, rng.randf_range(220, 800))
		var hgt := rng.randf_range(60, 140)
		B.cyl(self, 0.5, hgt * 0.8, hgt, mp + Vector3(0, hgt / 2.0, 0), M.tinted("concrete", Color(0.38, 0.4, 0.4)), false, Vector3.ZERO, 7)
	_flush_foliage()
	_build_bridge()
	_build_river()
	_build_tunnel()
	_build_roadblock()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	# Two triangles, clockwise when seen from the front
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_uv(Vector2(v.x, v.z) * 0.1)
		st.add_vertex(v)


var _card_x: Array = []
var _trunk_x: Array = []
var _cone_x: Array = []
var _bush_x: Array = []


func _tree(p: Vector3, h: float) -> void:
	_trunk_x.append(Transform3D(Basis().scaled(Vector3(0.3, h, 0.3)), p + Vector3(0, h / 2.0, 0)))
	if M.tex("pine_card_albedo") != null:
		var whorls := int(h / 1.1)
		for i in whorls:
			var t := float(i) / whorls
			var length := lerpf(2.8, 0.5, t)
			for k in 5:
				var bb := Basis(Vector3.UP, k * TAU / 5.0 + rng.randf()) * Basis(Vector3.BACK, -deg_to_rad(lerpf(25, 8, t)))
				_card_x.append(Transform3D(bb.scaled(Vector3.ONE * length), p + Vector3(0, lerpf(h * 0.25, h * 0.98, t), 0)))
		_cone_x.append(Transform3D(Basis().scaled(Vector3(1.0, h * 0.5, 1.0)), p + Vector3(0, h * 0.55, 0)))
		return
	for i in 5:
		var t := i / 5.0
		var r := lerpf(2.4, 0.6, t)
		_cone_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, h * 0.35, r)), p + Vector3(0, h * (0.35 + t * 0.55), 0)))


func _bush(p: Vector3) -> void:
	_bush_x.append(Transform3D(Basis().scaled(Vector3(rng.randf_range(1.2, 2.2), rng.randf_range(0.8, 1.5), rng.randf_range(1.2, 2.2))), p + Vector3(0, 0.6, 0)))


func _flush_foliage() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.33
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 6
	var cone := CylinderMesh.new()
	cone.top_radius = 0.01
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 7
	var bush := SphereMesh.new()
	bush.radial_segments = 8
	bush.rings = 5
	bush.radius = 0.5
	bush.height = 1.0
	var specs := [[trunk, _trunk_x, M.get_mat("bark")], [cone, _cone_x, M.tinted("needles", Color(0.5, 0.55, 0.5))], [bush, _bush_x, M.tinted("needles", Color(0.8, 1.0, 0.8))]]
	if not _card_x.is_empty():
		specs.append([preload("res://scripts/world/seg1_timberline.gd").branch_card_mesh(), _card_x, M.get_mat("pine_card")])
	for spec in specs:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		var xs: Array = spec[1]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = spec[2]
		add_child(mmi)


func _build_bridge() -> void:
	var stone := M.tinted("concrete", Color(0.6, 0.57, 0.52))
	var d := s_bridge_a
	while d < s_bridge_b:
		var p := pos_at(d)
		var f := dir_at(d)
		var left := Vector3.UP.cross(f).normalized()
		for side in [-1.0, 1.0]:
			var wp: Vector3 = p + left * side * (ROAD_W / 2.0 + 0.2) + Vector3(0, 0.5, 0)
			var par := B.box(self, Vector3(0.5, 1.0, 2.2), wp, stone, false)
			par.look_at(wp + f, Vector3.UP)
		d += 2.0
	# Arches / piers down to the river
	var mid := pos_at((s_bridge_a + s_bridge_b) / 2.0)
	for k in [-12.0, 0.0, 12.0]:
		var pp := pos_at((s_bridge_a + s_bridge_b) / 2.0 + k)
		B.box(self, Vector3(ROAD_W + 1.0, 30.0, 3.0), pp + Vector3(0, -15.5, 0), stone, false).look_at(pp + Vector3(0, -15.5, 0) + dir_at((s_bridge_a + s_bridge_b) / 2.0 + k), Vector3.UP)
	B.box(self, Vector3(ROAD_W + 1.0, 1.2, s_bridge_b - s_bridge_a), mid + Vector3(0, -0.65, 0), stone, false).look_at(mid + Vector3(0, -0.65, 0) + dir_at((s_bridge_a + s_bridge_b) / 2.0), Vector3.UP)


func _build_river() -> void:
	var mid := pos_at((s_bridge_a + s_bridge_b) / 2.0)
	var f := dir_at((s_bridge_a + s_bridge_b) / 2.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.2, 0.3, 0.33)
	water.roughness = 0.05
	water.metallic = 0.4
	water.emission_enabled = true
	water.emission = Color(0.05, 0.08, 0.09)
	var river := B.box(self, Vector3(400, 0.5, 16), mid + Vector3(0, -30, 0), water, false)
	river.look_at(river.global_position + f, Vector3.UP)
	river.rotate_y(PI / 2)
	# White water
	var foam := CPUParticles3D.new()
	foam.amount = 120
	foam.lifetime = 2.0
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(60, 0.2, 6)
	foam.direction = Vector3(1, 0.3, 0)
	foam.initial_velocity_min = 2.0
	foam.initial_velocity_max = 4.0
	var fm := BoxMesh.new()
	fm.size = Vector3(0.6, 0.1, 0.4)
	foam.mesh = fm
	foam.material_override = M.emissive(Color(0.85, 0.9, 0.9), 0.3)
	river.add_child(foam)
	_river = AudioStreamPlayer3D.new()
	_river.stream = S.get_stream("wind")
	_river.volume_db = 8.0
	_river.unit_size = 25.0
	_river.max_distance = 150.0
	_river.pitch_scale = 2.2
	add_child(_river)
	_river.global_position = mid + Vector3(0, -25, 0)


func _build_tunnel() -> void:
	# Old rail tunnel into the cliff, collapsed: the road swings around it
	var p := pos_at(s_tunnel)
	var f := dir_at(s_tunnel)
	var left := Vector3.UP.cross(f).normalized()
	var mouth := p + f * 16.0 + left * 7.0
	var holder := Node3D.new()
	holder.position = mouth
	add_child(holder)
	holder.look_at(mouth + f, Vector3.UP)
	var con := M.get_mat("concrete")
	B.box(holder, Vector3(1.5, 7, 3), Vector3(-4.5, 3.5, 0), con, true)
	B.box(holder, Vector3(1.5, 7, 3), Vector3(4.5, 3.5, 0), con, true)
	B.box(holder, Vector3(10.5, 1.5, 3), Vector3(0, 7.5, 0), con, true)
	var rubble := M.tinted("concrete", Color(0.45, 0.43, 0.4))
	for i in 14:
		B.box(holder, Vector3(rng.randf_range(0.8, 2.5), rng.randf_range(0.6, 2.0), rng.randf_range(0.8, 2.0)), Vector3(rng.randf_range(-3.5, 3.5), rng.randf_range(0.4, 4.5), rng.randf_range(-1, 2)), rubble, true, Vector3(rng.randf() * 60, rng.randf() * 90, rng.randf() * 60))
	B.label3d(holder, "TUNNEL CLOSED\nDETOUR", Vector3(0, 6.2, -1.6), 64, Color(0.95, 0.8, 0.1), Vector3(0, 180, 0))


func _build_roadblock() -> void:
	var p := pos_at(s_roadblock)
	var f := dir_at(s_roadblock)
	var left := Vector3.UP.cross(f).normalized()
	var barrier := M.tinted("concrete", Color(0.7, 0.68, 0.62))
	for k in [-2.6, 0.0, 2.6]:
		var bp: Vector3 = p + left * k + Vector3(0, 0.45, 0)
		var jb: Node3D = MD.place(self, "jersey_barrier", bp - Vector3(0, 0.45, 0), Vector3.ZERO, Vector3(0.85, 1.0, 1.0))
		if jb == null:
			jb = B.box(self, Vector3(2.4, 0.9, 0.6), bp, barrier, false)
		jb.look_at(jb.global_position + left, Vector3.UP)
		jb.rotate_y(PI / 2)
		_roadblock_nodes.append(jb)
	for k in [-5.5, 5.5]:
		var sp: Vector3 = p + left * k + f * 2.0 + Vector3(0, 0.4, 0)
		var sb: Node3D = MD.place(self, "sandbags", sp - Vector3(0, 0.4, 0))
		if sb == null:
			sb = B.box(self, Vector3(3.0, 0.8, 1.0), sp, M.tinted("uniform", Color(0.7, 0.65, 0.5)), false)
		sb.look_at(sb.global_position + left, Vector3.UP)
		sb.rotate_y(PI / 2)
	B.box(self, Vector3(0.2, 3.0, 0.2), p + left * 4.8 + Vector3(0, 1.5, 0), M.get_mat("metal"), false)
	B.label3d(self, "VANGUARD CORP\nCHECKPOINT 7", p + left * 4.8 + Vector3(0, 3.3, 0) + f * 0.2, 48, Color(0.95, 0.3, 0.2)).look_at(p + left * 4.8 + Vector3(0, 3.3, 0) - f, Vector3.UP)
	var flood := B.spot(self, p + left * 4.8 + Vector3(0, 3.0, 0), Vector3.ZERO, Color(1, 0.95, 0.85), 6.0, 40.0, 35.0)
	flood.look_at_from_position(flood.global_position, p - f * 25.0, Vector3.UP)
	flood.light_volumetric_fog_energy = 2.0


# ------------------------------------------------------------------ truck

func _build_truck() -> void:
	truck = Node3D.new()
	truck.name = "SupplyTruck"
	add_child(truck)
	var cab := M.tinted("rust", Color(0.25, 0.3, 0.22))
	var wood := M.get_mat("wood")
	B.mesh(truck, _bm(Vector3(2.4, 0.4, 7.5)), Vector3(0, 0.9, 0.8), M.get_mat("gun_metal"))   # chassis
	B.mesh(truck, _bm(Vector3(2.4, 2.2, 2.2)), Vector3(0, 2.0, -2.6), cab)                   # cab
	B.mesh(truck, _bm(Vector3(2.2, 0.9, 0.05)), Vector3(0, 2.5, -3.72), M.get_mat("glass"))
	B.mesh(truck, _bm(Vector3(0.05, 0.9, 1.6)), Vector3(1.21, 2.5, -2.7), M.get_mat("glass"))
	# Open bed with wooden sides
	B.mesh(truck, _bm(Vector3(2.4, 0.1, 5.0)), Vector3(0, 1.15, 1.9), wood)
	for side in [-1.18, 1.18]:
		B.mesh(truck, _bm(Vector3(0.08, 0.8, 5.0)), Vector3(side, 1.6, 1.9), wood)
	B.mesh(truck, _bm(Vector3(2.4, 0.8, 0.08)), Vector3(0, 1.6, 4.38), wood)
	for wx in [-1.1, 1.1]:
		for wz in [-2.6, 1.0, 3.2]:
			var w := B.mesh(truck, CylinderMesh.new(), Vector3(wx, 0.55, wz), M.get_mat("black"), Vector3(0, 0, 90))
			w.scale = Vector3(0.55, 0.2, 0.55)
	# Reyes at the wheel
	B.mesh(truck, _bm(Vector3(0.5, 0.7, 0.4)), Vector3(-0.5, 2.2, -2.4), M.tinted("uniform", Color(0.6, 0.7, 0.55)))
	var hd := B.mesh(truck, SphereMesh.new(), Vector3(-0.5, 2.75, -2.4), M.get_mat("gear"))
	hd.scale = Vector3(0.25, 0.25, 0.25)
	var hl := B.spot(truck, Vector3(0, 1.4, -3.8), Vector3(-5, 180, 0), Color(1, 0.95, 0.8), 4.0, 45.0, 32.0)
	hl.rotation_degrees = Vector3(-5, 0, 0)
	hl.light_volumetric_fog_energy = 1.5
	B.mesh(truck, _bm(Vector3(0.35, 0.2, 0.05)), Vector3(-0.8, 1.4, -3.72), M.emissive(Color(1, 0.95, 0.8), 5.0))
	B.mesh(truck, _bm(Vector3(0.35, 0.2, 0.05)), Vector3(0.8, 1.4, -3.72), M.emissive(Color(1, 0.95, 0.8), 5.0))
	bed_anchor = Node3D.new()
	bed_anchor.position = Vector3(0.2, 1.2, 2.4)
	truck.add_child(bed_anchor)
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = S.get_stream("engine")
	_engine.volume_db = -6.0
	_engine.unit_size = 8.0
	truck.add_child(_engine)
	truck.visible = false
	truck.global_position = pos_at(0.0) + Vector3(0, -50, 0)


func _bm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Start the ride: the truck comes along the loading bay; Vance leaps from the window
func start(leap_from: Vector3) -> void:
	active = true
	truck.visible = true
	speed = 11.0
	s = s_window - speed * 1.1
	_engine.play()
	_leap_from = leap_from
	_leap_t = 0.0
	var p = game.player
	p.controls_enabled = false
	p.move_enabled = false
	_place_truck()


func _physics_process(delta: float) -> void:
	if not active:
		return
	var p = game.player
	# Speed profile
	var ts := target_speed
	if s < s_gate + 5.0:
		ts = 13.0
	if s > s_end - 30.0:
		ts = 12.0
	speed = move_toward(speed, ts, delta * 3.0)
	if s < s_end:
		s += speed * delta
	_place_truck()

	# The leap from the window
	if _leap_t >= 0.0:
		_leap_t += delta / 1.1
		var target := bed_anchor.global_position
		var t := clampf(_leap_t, 0.0, 1.0)
		var pos := _leap_from.lerp(target, t) + Vector3(0, sin(t * PI) * 1.8, 0)
		p.global_position = pos
		p.velocity = Vector3.ZERO
		if _leap_t >= 1.0:
			_leap_t = -1.0
			p.set_carrier(bed_anchor)
			p.controls_enabled = true
			p.stance = 0
			p._apply_stance(true)
			p.rotation.y = truck.global_rotation.y + PI   # facing back toward the pursuers
			p.head.rotation.x = 0.0
			p.add_shake(1.4)
			S.play3d(p, "step_metal", p.global_position, 6.0)
			game.mission.on_seg4_event("landed")
	else:
		# Road bumps shake the camera
		p.add_shake(delta * (0.25 + speed * 0.02) * (1.0 if rng.randf() < 0.7 else 3.0))

	# Events along the road
	for e in events:
		if not e[2] and s >= e[0]:
			e[2] = true
			_event(e[1])
	# Branches snap as the truck ploughs through
	for b in branches:
		if not b[2] and s >= b[0] - 2.0:
			b[2] = true
			var br: Node3D = b[1]
			S.play3d(self, "impact", br.global_position, 4.0)
			S.play3d(self, "cut", br.global_position, 2.0)
			var tw := br.create_tween()
			tw.tween_property(br, "position:y", br.position.y - 6.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(br, "rotation:z", 1.2, 0.6)
			p.add_shake(0.4)
	# Pursuers
	for t in techs:
		if not is_instance_valid(t):
			continue
		if not t.dead:
			t.gap = move_toward(t.gap, 18.0 + sin(Time.get_ticks_msec() * 0.0007 + t.lateral) * 7.0, delta * 3.0)
			var ts2 := maxf(0.0, s - t.gap)
			var pp := pos_at(ts2)
			var f := dir_at(ts2)
			var left := Vector3.UP.cross(f).normalized()
			t.global_position = pp + left * t.lateral + Vector3(0, sin(Time.get_ticks_msec() * 0.01 + t.lateral) * 0.04, 0)
			t.look_at(t.global_position + f, Vector3.UP)
			t.update_fire(delta, p)
		else:
			# Wrecks fall behind and tumble off the drop
			t.gap += delta * 18.0
			t.global_position += Vector3(0, -delta * 4.0, 0)


func _place_truck() -> void:
	var pos := pos_at(s)
	var f := dir_at(s)
	_bounce_t += get_physics_process_delta_time() * speed
	truck.global_position = pos + Vector3(0, sin(_bounce_t * 1.3) * 0.05 + sin(_bounce_t * 3.1) * 0.02, 0)
	truck.look_at(truck.global_position + f, Vector3.UP)
	truck.rotate_object_local(Vector3.FORWARD, sin(_bounce_t * 0.9) * 0.02)


func _spawn_techs(count: int) -> void:
	for i in count:
		var t := StaticBody3D.new()
		t.set_script(TechScript)
		t.game = game
		t.gap = 45.0 + i * 12.0
		t.lateral = -1.6 if i % 2 == 0 else 1.6
		add_child(t)
		t.global_position = pos_at(maxf(0.0, s - t.gap))
		techs.append(t)


func _event(name: String) -> void:
	match name:
		"gate":
			game.seg2.smash_exit_gate()
			game.player.add_shake(1.5)
			checkpoint_s = s_gate
		"techs1":
			_spawn_techs(2)
		"bridge":
			checkpoint_s = s_bridge_a
		"techs2":
			_spawn_techs(2)
		"roadblock":
			S.play3d(self, "door", pos_at(s_roadblock), 10.0)
			game.player.add_shake(1.8)
			for n in _roadblock_nodes:
				var tw: Tween = n.create_tween()
				tw.tween_property(n, "position", n.position + Vector3(randf_range(-6, 6), 2.0, randf_range(-3, 3)) + dir_at(s_roadblock) * 8.0, 0.5)
				tw.parallel().tween_property(n, "rotation", Vector3(randf() * 3, randf() * 3, randf() * 3), 0.5)
		"crash":
			active = false
			speed = 0.0
			_engine.stop()
			S.play3d(self, "explosion", truck.global_position, 6.0)
			game.player.add_shake(2.0)
	game.mission.on_seg4_event(name)


func alive_techs() -> int:
	var n := 0
	for t in techs:
		if is_instance_valid(t) and not t.dead:
			n += 1
	return n


## Called when Vance dies during the ride: rewind to the last checkpoint on the road
func rewind() -> void:
	for t in techs:
		if is_instance_valid(t):
			t.queue_free()
	techs.clear()
	s = checkpoint_s
	speed = target_speed * 0.7
	for e in events:
		if e[0] > s:
			e[2] = false
	var p = game.player
	p.set_carrier(bed_anchor)
	p.controls_enabled = true


func dismount() -> Vector3:
	# Vance rolls out of the wreck onto the bunker floor
	game.player.set_carrier(null)
	var side := truck.global_transform.basis.x
	return truck.global_position + side * 2.4 + Vector3(0, 0.5, 0)
