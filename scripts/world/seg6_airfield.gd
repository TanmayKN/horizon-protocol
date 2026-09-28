extends Node3D
## SEGMENT 6 — The Buyer: Vostok Airfield at dawn.
## Hale's buyer lands at 07:00. Get in, kill the tower radar so the jet can't get clearance,
## free Reyes from the hangar office, then stop Hale at the jet.
##
## Layout (z grows north):  start + fuel depot (z 990-1080) | fence z 1080 (gate x 20-32, broken
## section x -104..-98) | tower (x 93) + hangars (z 1105-1131) | apron + jet (z 1140-1190) | runway z 1215

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const MD := preload("res://scripts/models.gd")

const START_POS := Vector3(-62, 0.2, 1004)
const FENCE_Z := 1080.0
const FENCE_GAP := Vector2(-104, -98)
const GATE := Vector2(20, 32)
const TOWER := Vector3(100, 0, 1096)
const TOWER_CONSOLE := Vector3(100, 12, 1098.2)
const CAB_Y := 12.0
const HANGAR_X := [-60.0, 0.0, 60.0]
const HANGAR_Z0 := 1105.0
const HANGAR_Z1 := 1131.0
const OFFICE_DOOR := Vector3(-66, 0, 1108.8)
const REYES_POS := Vector3(-71.5, 0, 1108.0)
const JET_POS := Vector3(0, 0, 1166)
const HELIPAD := Vector3(72, 0, 1170)

var game
var rng := RandomNumberGenerator.new()
var jet: Node3D
var jet_body: StaticBody3D
var heli: Node3D
var radar: Node3D
var radar_dead := false
var beacon: OmniLight3D
var office_door: Node3D
var reyes_actor: Node3D
var _t := 0.0
var _jet_snd: AudioStreamPlayer3D
var jet_engines := 0.0          # 0 = off .. 1 = full power (spooling up for take-off)
var _heli_rotor: Node3D


func _ready() -> void:
	rng.seed = 707
	_build_ground()
	_build_fence()
	_build_start_area()
	_build_tower()
	for i in 3:
		_build_hangar(HANGAR_X[i], i)
	_build_office()
	_build_apron()
	_build_runway()
	_build_jet()
	_build_helipad()
	_build_boundaries()


func _process(delta: float) -> void:
	_t += delta
	if radar and not radar_dead:
		radar.rotation.y += delta * 1.6
	if beacon:
		beacon.light_energy = 3.0 if fmod(_t, 1.2) < 0.15 else 0.0
	if _heli_rotor:
		_heli_rotor.rotation.y += delta * 3.0
	if _jet_snd:
		_jet_snd.volume_db = lerpf(-30.0, 8.0, jet_engines)
		_jet_snd.pitch_scale = lerpf(0.6, 1.6, jet_engines)
		if jet_engines > 0.01 and not _jet_snd.playing:
			_jet_snd.play()


func inside(pos: Vector3) -> bool:
	return pos.z > 985.0 and pos.z < 1290.0 and absf(pos.x) < 150.0 and pos.y > -5.0 and pos.y < 40.0


func surface_at(pos: Vector3) -> String:
	if not inside(pos):
		return ""
	if pos.y > 3.0 and absf(pos.x - (TOWER.x + 6.5)) < 2.5:
		return "metal"      # tower stairs
	if pos.y > 11.5:
		return "hard"
	if pos.z > 1100.0 and pos.z < 1235.0:
		return "hard"       # hangars, apron, runway
	if absf(pos.x - 26.0) < 5.0:
		return "hard"       # approach road
	if pos.x < -80.0 and pos.z > 1030.0 and pos.z < 1062.0:
		return "gravel"     # fuel depot
	return "grass"


func in_office(pos: Vector3) -> bool:
	return pos.x > -74.0 and pos.x < -66.0 and pos.z > 1105.0 and pos.z < 1112.0


# ------------------------------------------------------------------ ground & scenery

func _mat_grass() -> Material:
	var m: Material = M.get_mat("meadow")
	return m if m else M.get_mat("ground")


func _build_ground() -> void:
	B.box(self, Vector3(640, 1, 640), Vector3(0, -0.5, 1135), _mat_grass())
	_build_mountains()
	_build_grass()
	# pine woods between the road and the fence, and behind the hangars
	var trees := Node3D.new()
	trees.set_script(load("res://scripts/world/trees.gd"))
	add_child(trees)
	trees.rng.seed = 77
	var placed := 0
	var tries := 0
	while placed < 120 and tries < 3000:
		tries += 1
		var p2 := Vector3(rng.randf_range(-140, 140), 0, rng.randf_range(992, 1074))
		if absf(p2.x - 26.0) < 9.0 or (p2.x < -70.0 and p2.z > 1028.0) or p2.distance_to(START_POS) < 12.0:
			continue
		if p2.x > -50.0 and p2.x < -20.0 and p2.z > 1040.0:
			continue   # clearing so you can see the airfield from the road
		trees.add_tree(p2, rng.randf_range(10.0, 17.0), rng.randf() < 0.4)
		placed += 1
	for k in 60:
		var side := -1.0 if k % 2 == 0 else 1.0
		trees.add_tree(Vector3(side * rng.randf_range(118, 145), 0, rng.randf_range(1080, 1245)), rng.randf_range(12.0, 19.0), rng.randf() < 0.5)
	trees.flush()


## Grass tufts in 40 m chunks (each chunk culls on its own at distance)
func _build_grass() -> void:
	var quad := SurfaceTool.new()
	quad.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := k * PI / 2.0
		var dx := cos(a) * 0.45
		var dz := sin(a) * 0.45
		for v in [[Vector3(-dx, 0, -dz), Vector2(0, 1)], [Vector3(dx, 0, dz), Vector2(1, 1)], [Vector3(dx, 0.5, dz), Vector2(1, 0)],
				[Vector3(-dx, 0, -dz), Vector2(0, 1)], [Vector3(dx, 0.5, dz), Vector2(1, 0)], [Vector3(-dx, 0.5, -dz), Vector2(0, 0)]]:
			quad.set_normal(Vector3.UP)
			quad.set_uv(v[1])
			quad.add_vertex(v[0])
	var mesh := quad.commit()
	var mat: StandardMaterial3D = M.tinted("grass", Color(0.95, 1.0, 0.72)).duplicate()
	mat.backlight = Color(0.35, 0.4, 0.2)   # sunrise shining through the blades instead of black silhouettes
	for cx in range(-140, 140, 40):
		for cz in range(990, 1250, 40):
			var xforms: Array = []
			for i in 420:
				var x := cx + rng.randf() * 40.0
				var z := cz + rng.randf() * 40.0
				if _paved(x, z):
					continue
				var sc := rng.randf_range(0.6, 1.5)
				xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.7, 1.4), sc)), Vector3(x, -0.03, z)))
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 75.0
			add_child(mmi)


func _paved(x: float, z: float) -> bool:
	if absf(x - 26.0) < 5.5 and z < FENCE_Z:
		return true                                     # approach road
	if z > HANGAR_Z0 - 1.0 and z < 1236.0 and absf(x) < 105.0:
		return true                                     # hangars, apron, runway
	if absf(z - 1215.0) < 19.0:
		return true
	if Vector2(x - TOWER.x - 3, z - TOWER.z).length() < 10.0:
		return true
	if x < -80.0 and z > 1030.0 and z < 1062.0:
		return true                                     # fuel depot gravel
	return false


## A ring of real mountains around the valley (heightfield mesh), snow on the peaks
func _build_mountains() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 606
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2(0, 1135)
	var segs := 128
	var rings := 18
	var r0 := 230.0
	var r1 := 520.0
	var verts := []
	for j in rings + 1:
		var row := []
		var rr := lerpf(r0, r1, float(j) / rings)
		for i in segs + 1:
			var a := float(i) / segs * TAU
			var x := center.x + sin(a) * rr
			var z := center.y + cos(a) * rr
			var t := clampf((rr - r0) / 120.0, 0.0, 1.0)
			var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
			var h := t * t * (60.0 + n * 150.0) * (0.6 + 0.4 * sin(a * 3.0 + 1.0) * sin(a * 5.0))
			h = maxf(h, t * 25.0)
			row.append(Vector3(x, h - 2.0, z))
		verts.append(row)
	for j in rings:
		for i in segs:
			var q := [verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]]
			for idx in [0, 2, 1, 0, 3, 2]:
				var v: Vector3 = q[idx]
				var snow := clampf((v.y - 95.0) / 40.0, 0.0, 1.0)
				st.set_color(Color(0.5, 0.47, 0.44).lerp(Color(0.95, 0.95, 0.97), snow))
				st.set_uv(Vector2(v.x, v.z) * 0.02)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := M.pbr("rock", Color.WHITE, Vector3(0.05, 0.05, 0.05), true, 1.0)
	if mat == null:
		mat = StandardMaterial3D.new()
	mat = mat.duplicate()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _fence_run(z: float, x0: float, x1: float, gaps: Array) -> void:
	var post := M.get_mat("metal")
	var link := M.get_mat("chainlink")
	var x := x0
	while x < x1 - 0.1:
		var mid := x + 1.5
		var open := false
		for g in gaps:
			if mid > g.x and mid < g.y:
				open = true
		B.cyl(self, 0.05, 0.05, 3.3, Vector3(x, 1.65, z), post, false, Vector3.ZERO, 6)
		if not open:
			B.box(self, Vector3(3.0, 2.8, 0.04), Vector3(mid, 1.4, z), link, false)
			B.box(self, Vector3(3.0, 0.02, 0.02), Vector3(mid, 3.05, z), post, false)
			B.box(self, Vector3(3.0, 0.02, 0.02), Vector3(mid, 3.2, z - 0.05), post, false)
		x += 3.0
	# one tall player-only wall per solid stretch (bullets and eyes still pass through the chain-link)
	var edges := [x0]
	for g in gaps:
		edges.append(g.x)
		edges.append(g.y)
	edges.append(x1)
	for i in range(0, edges.size(), 2):
		var a: float = edges[i]
		var b2: float = edges[i + 1]
		if b2 - a > 0.2:
			B.player_wall(self, Vector3(b2 - a, 12.0, 0.5), Vector3((a + b2) / 2.0, 6.0, z))


func _build_fence() -> void:
	_fence_run(FENCE_Z, -140.0, 140.0, [FENCE_GAP, GATE])
	# the broken section: a torn panel lying on the ground
	B.box(self, Vector3(3.0, 2.8, 0.04), Vector3(-101, 0.12, FENCE_Z + 1.4), M.get_mat("chainlink"), false, Vector3(-86, 12, 0))
	# gate: guard booth, barrier arm, sign
	var con := M.get_mat("concrete")
	B.box(self, Vector3(0.5, 3.6, 0.5), Vector3(GATE.x, 1.8, FENCE_Z), con)
	B.box(self, Vector3(0.5, 3.6, 0.5), Vector3(GATE.y, 1.8, FENCE_Z), con)
	B.box(self, Vector3(3.0, 2.8, 3.0), Vector3(GATE.y + 2.5, 1.4, FENCE_Z + 2.0), M.get_mat("corrugated"))
	B.box(self, Vector3(3.2, 0.15, 3.2), Vector3(GATE.y + 2.5, 2.9, FENCE_Z + 2.0), M.get_mat("metal"), false)
	B.box(self, Vector3(1.2, 0.8, 0.05), Vector3(GATE.y + 2.5, 1.7, FENCE_Z + 0.49), M.get_mat("glass"))
	B.box(self, Vector3(10.0, 0.12, 0.12), Vector3(26, 1.05, FENCE_Z - 0.4), M.get_mat("hazard"), false, Vector3(0, 0, 8))
	B.label3d(self, "VOSTOK AIRFIELD\nPRIVATE  -  NO ENTRY", Vector3(26, 4.2, FENCE_Z - 0.3), 44, Color(0.92, 0.9, 0.85), Vector3(0, 180, 0))
	B.box(self, Vector3(13, 0.5, 0.3), Vector3(26, 3.9, FENCE_Z - 0.1), M.tinted("metal", Color(0.2, 0.3, 0.5)), false)
	for gx in [GATE.x - 1.0, GATE.y + 1.0]:
		_floodlight(Vector3(gx, 0, FENCE_Z - 2.0), 0.0)


func _floodlight(p: Vector3, yaw: float) -> void:
	B.cyl(self, 0.08, 0.1, 7.0, p + Vector3(0, 3.5, 0), M.get_mat("metal"), true, Vector3.ZERO, 8)
	if MD.place(self, "floodlight_head", p + Vector3(0, 7.0, 0), Vector3(0, yaw, 0)) == null:
		B.box(self, Vector3(0.5, 0.35, 0.3), p + Vector3(0, 7.0, 0), M.get_mat("metal"), false)
	B.spot(self, p + Vector3(0, 6.9, 0), Vector3(-55, yaw + 180.0, 0), Color(1, 0.93, 0.8), 3.0, 30.0, 50.0)


func _build_start_area() -> void:
	var asph := M.get_mat("asphalt")
	# approach road from the south up to the gate
	B.box(self, Vector3(9, 0.08, 95), Vector3(26, 0.04, 1032), asph, false)
	B.box(self, Vector3(0.15, 0.09, 95), Vector3(26, 0.045, 1032), M.emissive(Color(0.9, 0.8, 0.3), 0.2), false)
	# Raskov's gun truck that Vance drove down the mountain
	var tech := Node3D.new()
	add_child(tech)
	tech.global_position = START_POS + Vector3(3.5, -0.2, 2.0)
	tech.rotation_degrees.y = 160.0
	MD.place(tech, "technical", Vector3.ZERO, Vector3.ZERO, Vector3.ONE, Color(0.34, 0.37, 0.28))
	var tb := StaticBody3D.new()
	tech.add_child(tb)
	var ts := BoxShape3D.new()
	ts.size = Vector3(2.3, 1.9, 5.0)
	B.add_shape(tb, ts, Vector3(0, 1.1, 0))
	B.spot(tech, Vector3(0, 1.2, -2.5), Vector3(-6, 0, 0), Color(1, 0.95, 0.8), 2.0, 30.0, 25.0)
	# Fuel depot by the broken fence: big tanks, pipes, a tanker
	var tank := M.tinted("metal", Color(0.78, 0.78, 0.74))
	for i in 3:
		var tp := Vector3(-120 + i * 13.0, 0, 1048)
		B.cyl(self, 5.0, 5.0, 8.0, tp + Vector3(0, 4.0, 0), tank, true, Vector3.ZERO, 24)
		B.cyl(self, 5.05, 5.05, 0.3, tp + Vector3(0, 8.1, 0), M.get_mat("metal"), false, Vector3.ZERO, 24)
		B.label3d(self, "JET A-1", tp + Vector3(0, 5.0, -5.06), 72, Color(0.8, 0.15, 0.1), Vector3(0, 180, 0))
	for i in 4:
		B.cyl(self, 0.18, 0.18, 30.0, Vector3(-107, 0.5 + i * 0.4, 1040), M.get_mat("metal"), false, Vector3(0, 0, 90), 8)
	var tanker := StaticBody3D.new()
	add_child(tanker)
	tanker.global_position = Vector3(-92, 0, 1036)
	MD.place(tanker, "supply_truck", Vector3.ZERO, Vector3(0, 90, 0), Vector3.ONE, Color(0.55, 0.52, 0.45))
	B.truck_shapes(tanker, Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO))
	B.box(self, Vector3(40, 0.05, 28), Vector3(-104, 0.025, 1046), M.get_mat("gravel"), false)
	for p in [Vector3(-88, 0, 1062), Vector3(-80, 0, 1070), Vector3(-110, 0, 1068)]:
		_solid_model("crate", p, rng.randf() * 90.0, Vector3(1.1, 1.1, 1.1), Vector3(0, 0.55, 0))
	for p in [Vector3(-70, 0, 1050), Vector3(-66, 0, 1058)]:
		_solid_model("jersey_barrier", p, 90.0, Vector3(3.0, 0.81, 0.6), Vector3(0, 0.4, 0))


func _solid_model(name: String, pos: Vector3, yaw: float, size: Vector3, center: Vector3, tint := Color(1, 1, 1)) -> Node3D:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = pos
	body.rotation_degrees.y = yaw
	if MD.place(body, name, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, tint) == null:
		B.mesh(body, _bm(size), center, M.get_mat("wood"))
	var s := BoxShape3D.new()
	s.size = size
	B.add_shape(body, s, center)
	return body


func _bm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# ------------------------------------------------------------------ control tower

func _build_tower() -> void:
	var con := M.get_mat("concrete")
	var steel := M.tinted("metal", Color(0.35, 0.37, 0.4))
	var c := TOWER
	# concrete core under the cab (with a locked service door)
	B.box(self, Vector3(4.0, CAB_Y, 4.0), Vector3(c.x, CAB_Y / 2.0, c.z), con)
	B.box(self, Vector3(1.2, 2.2, 0.05), Vector3(c.x, 1.1, c.z - 2.03), M.tinted("metal", Color(0.3, 0.1, 0.08)), false)
	B.label3d(self, "TWR", Vector3(c.x, 8.0, c.z - 2.05), 96, Color(0.85, 0.85, 0.8), Vector3(0, 180, 0))
	# external switchback stairs on the east side
	var x1 := c.x + 5.6
	var x2 := c.x + 7.4
	B.stairs(self, Vector3(x1, 0, c.z - 4.00), Vector3(x1, 4, c.z + 3.00), 1.7, steel, false)
	B.stairs(self, Vector3(x2, 4, c.z + 3.00), Vector3(x2, 8, c.z - 4.00), 1.7, steel, false)
	B.stairs(self, Vector3(x1, 8, c.z - 4.00), Vector3(x1, 12, c.z + 3.00), 1.7, steel, false)
	B.box(self, Vector3(3.6, 0.25, 2.0), Vector3(c.x + 6.50, 4 - 0.125, c.z + 4.00), steel)
	B.box(self, Vector3(3.6, 0.25, 2.0), Vector3(c.x + 6.50, 8 - 0.125, c.z - 5.00), steel)
	B.box(self, Vector3(4.4, 0.25, 2.4), Vector3(c.x + 6.10, CAB_Y - 0.125, c.z + 4.20), steel)
	# steel frame + rails (the rail on the outside is solid, the rest is visual)
	for zz in [c.z - 6.00, c.z + 5.20]:
		for xx in [c.x + 4.80, c.x + 8.30]:
			B.cyl(self, 0.08, 0.08, CAB_Y + 1.0, Vector3(xx, (CAB_Y + 1.0) / 2.0, zz), steel, false, Vector3.ZERO, 6)
	var rail := M.tinted("metal", Color(0.75, 0.62, 0.1))
	for y in [4.0, 8.0, 12.0]:
		B.box(self, Vector3(0.05, 1.0, 11.5), Vector3(c.x + 8.30, y + 0.5, c.z - 0.50), rail, false)
	B.player_wall(self, Vector3(0.3, 14.0, 12.0), Vector3(c.x + 8.45, 7.0, c.z - 0.50))
	B.player_wall(self, Vector3(3.8, 11.0, 0.3), Vector3(c.x + 6.50, 8.5, c.z - 6.20))
	B.player_wall(self, Vector3(4.4, 14.0, 0.3), Vector3(c.x + 6.30, 7.0, c.z + 5.60))
	# glass cab (8 x 8) with a door on the east side
	var cab := Vector3(c.x, CAB_Y, c.z)
	B.box(self, Vector3(8.4, 0.3, 8.4), cab + Vector3(0, -0.15, 0), con)
	var a := Vector3(cab.x - 4, CAB_Y, cab.z - 4)
	var b := Vector3(cab.x + 4, CAB_Y, cab.z + 4)
	var wall_m := M.tinted("concrete", Color(0.7, 0.7, 0.68))
	B.wall_openings(self, Vector3(a.x, CAB_Y, a.z), Vector3(b.x, CAB_Y, a.z), 3.2, 0.2, wall_m, [[0.5, 7.0, 1.0, 2.9]])
	B.wall_openings(self, Vector3(a.x, CAB_Y, b.z), Vector3(b.x, CAB_Y, b.z), 3.2, 0.2, wall_m, [[0.5, 7.0, 1.0, 2.9]])
	B.wall_openings(self, Vector3(a.x, CAB_Y, a.z), Vector3(a.x, CAB_Y, b.z), 3.2, 0.2, wall_m, [[0.5, 7.0, 1.0, 2.9]])
	B.wall_openings(self, Vector3(b.x, CAB_Y, a.z), Vector3(b.x, CAB_Y, b.z), 3.2, 0.2, wall_m, [[0.5, 5.0, 1.0, 2.9], [6.2, 1.6, 0.0, 2.3]])
	var glass := M.tinted("glass", Color(0.5, 0.65, 0.7, 0.35))
	B.box(self, Vector3(7.0, 1.9, 0.04), Vector3(cab.x - 0.5 + 0.5, CAB_Y + 1.95, a.z), glass)
	B.box(self, Vector3(7.0, 1.9, 0.04), Vector3(cab.x, CAB_Y + 1.95, b.z), glass)
	B.box(self, Vector3(0.04, 1.9, 7.0), Vector3(a.x, CAB_Y + 1.95, cab.z), glass)
	B.box(self, Vector3(0.04, 1.9, 5.0), Vector3(b.x, CAB_Y + 1.95, a.z + 3.0), glass)
	B.box(self, Vector3(9.0, 0.35, 9.0), cab + Vector3(0, 3.35, 0), con)
	# consoles + radar screen (the sabotage target)
	B.box(self, Vector3(5.0, 1.0, 0.8), Vector3(cab.x, CAB_Y + 0.5, cab.z + 3.2), M.get_mat("gear"))
	B.box(self, Vector3(1.2, 0.8, 0.05), Vector3(cab.x, CAB_Y + 1.35, cab.z + 3.5), M.emissive(Color(0.2, 1.0, 0.4), 1.8), false)
	B.label3d(self, "RADAR / ATC", Vector3(cab.x, CAB_Y + 1.85, cab.z + 3.48), 18, Color(0.3, 1, 0.5), Vector3(0, 180, 0))
	B.box(self, Vector3(0.8, 1.0, 3.0), Vector3(cab.x - 3.2, CAB_Y + 0.5, cab.z), M.get_mat("gear"))
	B.omni(self, cab + Vector3(0, 2.6, 0), Color(0.9, 0.95, 1.0), 1.0, 8.0)
	# rotating radar on the roof + beacon
	radar = Node3D.new()
	radar.position = cab + Vector3(0, 4.2, 0)
	add_child(radar)
	B.cyl(radar, 0.15, 0.15, 1.2, Vector3(0, 0.0, 0), steel, false, Vector3.ZERO, 8)
	B.box(radar, Vector3(4.0, 0.9, 0.2), Vector3(0, 0.8, 0), M.get_mat("metal"), false, Vector3(-15, 0, 0))
	beacon = B.omni(self, cab + Vector3(0, 4.0, 3.5), Color(0.3, 1.0, 0.4), 0.0, 25.0)


func kill_radar() -> void:
	radar_dead = true
	S.play3d(self, "explosion", radar.global_position, 0.0)
	S.play3d(self, "glass", TOWER_CONSOLE + Vector3(0, 1, 0), 0.0)
	var l := B.omni(self, radar.global_position, Color(1, 0.6, 0.3), 8.0, 20.0)
	create_tween().tween_property(l, "light_energy", 0.0, 1.5)
	radar.rotation_degrees.z = 25.0
	if beacon:
		beacon.queue_free()
		beacon = null


# ------------------------------------------------------------------ hangars

func _build_hangar(hx: float, idx: int) -> void:
	var cor := M.tinted("corrugated", Color(0.62, 0.64, 0.6) if idx != 1 else Color(0.55, 0.58, 0.62))
	var z0 := HANGAR_Z0
	var z1 := HANGAR_Z1
	var w := 30.0
	var h := 12.0
	var x0 := hx - w / 2.0
	var x1 := hx + w / 2.0
	B.wall_openings(self, Vector3(x0, 0, z0), Vector3(x1, 0, z0), h, 0.3, cor, [[w / 2.0 - 1.5, 3.0, 0.0, 3.0]])   # back door
	B.wall_openings(self, Vector3(x0, 0, z0), Vector3(x0, 0, z1), h, 0.3, cor, [[16.0, 2.0, 0.0, 2.4]])
	B.wall_openings(self, Vector3(x1, 0, z0), Vector3(x1, 0, z1), h, 0.3, cor, [[16.0, 2.0, 0.0, 2.4]])
	# front: big opening 24 wide, 9 tall
	B.wall_openings(self, Vector3(x0, 0, z1), Vector3(x1, 0, z1), h, 0.3, cor, [[3.0, 24.0, 0.0, 9.0]])
	# half-open sliding door leaf
	B.box(self, Vector3(8.0, 9.0, 0.25), Vector3(x0 + 7.0, 4.5, z1 + 0.4), M.tinted("corrugated", Color(0.5, 0.52, 0.5)))
	# pitched roof
	for s in [-1.0, 1.0]:
		B.box(self, Vector3(w / 2.0 + 0.6, 0.25, z1 - z0 + 1.0), Vector3(hx + s * w / 4.0, h + 1.1, (z0 + z1) / 2.0), cor, true, Vector3(0, 0, -s * 8.5))
	B.box(self, Vector3(w, 0.05, z1 - z0), Vector3(hx, 0.03, (z0 + z1) / 2.0), M.get_mat("concrete"), false)
	B.label3d(self, "HANGAR %d" % (idx + 1), Vector3(hx, 10.3, z1 + 0.2), 120, Color(0.95, 0.9, 0.3), Vector3(0, 0, 0))
	# lights inside
	for lz in [z0 + 7.0, z0 + 19.0]:
		for lx in [hx - 8.0, hx + 8.0]:
			B.omni(self, Vector3(lx, 10.0, lz), Color(1.0, 0.92, 0.8), 1.4, 14.0)
			B.box(self, Vector3(1.0, 0.2, 1.0), Vector3(lx, 10.6, lz), M.emissive(Color(1, 0.95, 0.85), 3.0), false)
	# cover inside: crates, drums, workbench, a container
	var props := [["crate", Vector3(hx + 8, 0, z0 + 6), Vector3(1.1, 1.1, 1.1), Vector3(0, 0.55, 0)],
		["crate", Vector3(hx + 9.3, 0, z0 + 6.3), Vector3(1.1, 1.1, 1.1), Vector3(0, 0.55, 0)],
		["crate", Vector3(hx + 8.6, 1.1, z0 + 6.1), Vector3(1.1, 1.1, 1.1), Vector3(0, 0.55, 0)],
		["drum", Vector3(hx - 3, 0, z0 + 3), Vector3(0.7, 1.0, 0.7), Vector3(0, 0.5, 0)],
		["drum", Vector3(hx - 2.2, 0, z0 + 3.4), Vector3(0.7, 1.0, 0.7), Vector3(0, 0.5, 0)],
		["pallet", Vector3(hx + 4, 0, z0 + 16), Vector3(1.2, 0.2, 1.0), Vector3(0, 0.1, 0)]]
	for pr in props:
		_solid_model(pr[0], pr[1], rng.randf() * 40.0, pr[2], pr[3])
	if idx != 1:
		_solid_model("container", Vector3(hx + 9.5, 0, z0 + 16.0), 90.0, Vector3(2.44, 2.6, 6.06), Vector3(0, 1.3, 0), Color(0.3, 0.4, 0.55))
	B.box(self, Vector3(3.0, 1.0, 1.0), Vector3(hx - 9, 0.5, z0 + 12), M.get_mat("metal"))


## Office in the back-left corner of hangar 1, where Hale's men are holding Reyes
func _build_office() -> void:
	var wall := M.tinted("concrete", Color(0.8, 0.78, 0.72))
	var a := Vector3(-74.7, 0, 1105.2)
	var b := Vector3(-66, 0, 1112)
	B.wall_openings(self, Vector3(a.x, 0, b.z), Vector3(b.x, 0, b.z), 3.0, 0.2, wall, [[3.0, 2.0, 1.0, 2.2]])   # window
	B.wall_openings(self, Vector3(b.x, 0, a.z), Vector3(b.x, 0, b.z), 3.0, 0.2, wall, [[3.0, 1.5, 0.0, 2.3]])   # door
	B.box(self, Vector3(b.x - a.x, 0.2, b.z - a.z), Vector3((a.x + b.x) / 2.0, 3.1, (a.z + b.z) / 2.0), wall)
	B.box(self, Vector3(2.0, 1.2, 0.04), Vector3(a.x + 4.0, 1.6, b.z), M.get_mat("glass"))
	B.omni(self, Vector3(-70, 2.6, 1108.5), Color(1, 0.9, 0.7), 0.9, 6.0)
	B.box(self, Vector3(1.6, 0.8, 0.8), Vector3(-72.5, 0.4, 1110.8), M.get_mat("wood"))
	# chair for Reyes
	B.box(self, Vector3(0.5, 0.45, 0.5), REYES_POS + Vector3(0, 0.22, 0.1), M.get_mat("metal"), false)
	B.box(self, Vector3(0.5, 0.6, 0.06), REYES_POS + Vector3(0, 0.75, 0.33), M.get_mat("metal"), false)
	B.label3d(self, "OPS", Vector3(-66.12, 2.6, 1109.5), 36, Color(0.9, 0.9, 0.9), Vector3(0, 90, 0))
	# the door: locked until Vance opens it
	office_door = B.box(self, Vector3(0.08, 2.3, 1.5), Vector3(-66.0, 1.15, 1108.75), M.tinted("metal", Color(0.4, 0.42, 0.45)))


func open_office_door() -> void:
	if office_door and is_instance_valid(office_door):
		S.play3d(self, "door", office_door.global_position, -4.0)
		var tw := office_door.create_tween()
		tw.tween_property(office_door, "position:z", office_door.position.z + 1.4, 0.8)


func spawn_reyes_prisoner() -> void:
	const Actor := preload("res://scripts/actor.gd")
	reyes_actor = Actor.spawn(self, "reyes", REYES_POS + Vector3(0, 0.02, 0), 180.0)
	reyes_actor.call("pose", "sit", 0.0)
	reyes_actor.set("gun_visible", false)


# ------------------------------------------------------------------ apron, runway, jet, helipad

func _build_apron() -> void:
	var con := M.get_mat("concrete")
	B.box(self, Vector3(200, 0.1, 58), Vector3(0, 0.05, 1160), con, false)
	B.box(self, Vector3(30, 0.1, 30), Vector3(0, 0.05, 1200), M.get_mat("runway"), false)   # taxiway
	for x in range(-95, 100, 10):
		B.box(self, Vector3(0.25, 0.02, 12), Vector3(x, 0.11, 1178), M.emissive(Color(0.95, 0.8, 0.2), 0.3), false)
	# cover on the apron: barriers, baggage carts, a fuel bowser, crates, sandbags
	for p in [Vector3(-30, 0, 1150), Vector3(-24, 0, 1158), Vector3(22, 0, 1150), Vector3(30, 0, 1160), Vector3(-10, 0, 1185), Vector3(12, 0, 1187)]:
		_solid_model("jersey_barrier", p, rng.randf_range(-30, 30), Vector3(3.0, 0.81, 0.6), Vector3(0, 0.4, 0))
	for p in [Vector3(-16, 0, 1146), Vector3(18, 0, 1143), Vector3(40, 0, 1150), Vector3(-42, 0, 1148)]:
		_cart(p)
	var bowser := StaticBody3D.new()
	add_child(bowser)
	bowser.global_position = Vector3(-20, 0, 1172)
	MD.place(bowser, "supply_truck", Vector3.ZERO, Vector3(0, 0, 0), Vector3.ONE, Color(0.75, 0.72, 0.6))
	B.truck_shapes(bowser)
	for p in [Vector3(8, 0, 1148), Vector3(9.2, 0, 1148.4), Vector3(-6, 0, 1150), Vector3(26, 0, 1176), Vector3(-34, 0, 1178)]:
		_solid_model("crate", p, rng.randf() * 90.0, Vector3(1.1, 1.1, 1.1), Vector3(0, 0.55, 0))
	for p in [Vector3(4, 0, 1140), Vector3(-4, 0, 1140)]:
		_solid_model("sandbags", p, 0.0, Vector3(2.4, 0.6, 0.5), Vector3(0, 0.3, 0))
	for fx in [-50.0, 50.0]:
		_floodlight(Vector3(fx, 0, 1140), 180.0 if fx < 0 else 180.0)


func _cart(p: Vector3) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.global_position = p
	body.rotation_degrees.y = rng.randf_range(0, 180)
	var blue := M.tinted("metal", Color(0.2, 0.3, 0.55))
	B.mesh(body, _bm(Vector3(1.6, 0.15, 3.0)), Vector3(0, 0.55, 0), blue)
	B.mesh(body, _bm(Vector3(1.6, 0.9, 0.08)), Vector3(0, 1.05, -1.46), blue)
	B.mesh(body, _bm(Vector3(1.5, 0.7, 2.6)), Vector3(0, 0.98, 0.1), M.tinted("concrete", Color(0.5, 0.45, 0.35)))
	for wx in [-0.7, 0.7]:
		for wz in [-1.1, 1.1]:
			B.cyl(body, 0.22, 0.22, 0.14, Vector3(wx, 0.22, wz), M.get_mat("black"), false, Vector3(0, 0, 90), 10)
	var s := BoxShape3D.new()
	s.size = Vector3(1.6, 1.4, 3.0)
	B.add_shape(body, s, Vector3(0, 0.75, 0))


func _build_runway() -> void:
	var asph := M.get_mat("asphalt")
	B.box(self, Vector3(320, 0.08, 36), Vector3(0, 0.04, 1215), M.get_mat("runway") if M.get_mat("runway") else asph, false)
	var white := M.emissive(Color(0.95, 0.95, 0.95), 0.25)
	for x in range(-150, 150, 12):
		B.box(self, Vector3(6, 0.02, 0.6), Vector3(x, 0.09, 1215), white, false)
	for side in [-17.5, 17.5]:
		B.box(self, Vector3(320, 0.02, 0.4), Vector3(0, 0.09, 1215 + side), white, false)
		for x in range(-150, 151, 15):
			B.box(self, Vector3(0.2, 0.25, 0.2), Vector3(x, 0.12, 1215 + side * 1.08), M.emissive(Color(0.4, 0.6, 1.0), 3.0), false)
	B.label3d(self, "27", Vector3(140, 0.1, 1215), 400, Color(0.95, 0.95, 0.95), Vector3(-90, 90, 0))


func _build_jet() -> void:
	jet = Node3D.new()
	jet.name = "BuyerJet"
	add_child(jet)
	jet.global_position = JET_POS
	jet.rotation_degrees.y = 90.0      # nose toward -X (it will taxi to the runway)
	if MD.place(jet, "cargo_jet", Vector3.ZERO) == null:
		B.mesh(jet, _bm(Vector3(3.0, 3.0, 24.0)), Vector3(0, 2.7, 0), M.get_mat("metal"))
	jet_body = StaticBody3D.new()
	jet.add_child(jet_body)
	for p in [[Vector3(3.1, 3.0, 25.0), Vector3(0, 2.7, 0.9)], [Vector3(21.0, 1.0, 3.6), Vector3(0, 1.9, 0.0)],
			[Vector3(1.6, 1.6, 3.8), Vector3(-4.6, 0.75, -1.4)], [Vector3(1.6, 1.6, 3.8), Vector3(4.6, 0.75, -1.4)]]:
		var s := BoxShape3D.new()
		s.size = p[0]
		B.add_shape(jet_body, s, p[1])
	_jet_snd = AudioStreamPlayer3D.new()
	_jet_snd.stream = S.get_stream("helicopter")
	_jet_snd.unit_size = 25.0
	_jet_snd.max_distance = 300.0
	_jet_snd.volume_db = -30.0
	jet.add_child(_jet_snd)
	# engine glow that brightens as it spools
	for sx in [-4.6, 4.6]:
		var g := B.omni(jet, Vector3(sx, 0.75, 0.8), Color(1.0, 0.55, 0.3), 0.0, 6.0)
		g.set_meta("engine_glow", true)


func set_jet_power(p: float) -> void:
	jet_engines = clampf(p, 0.0, 1.0)
	for c in jet.get_children():
		if c is OmniLight3D and c.has_meta("engine_glow"):
			c.light_energy = jet_engines * 3.0


## The jet rolls toward the runway (used when Hale tries to escape / the ending)
func jet_taxi(to: Vector3, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(jet, "global_position", to, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _build_helipad() -> void:
	B.cyl(self, 9.0, 9.0, 0.12, HELIPAD + Vector3(0, 0.06, 0), M.get_mat("concrete"), false, Vector3.ZERO, 32)
	B.label3d(self, "H", HELIPAD + Vector3(0, 0.14, 0), 900, Color(0.95, 0.9, 0.2), Vector3(-90, 0, 0))
	heli = Node3D.new()
	heli.name = "HaleHeli"
	add_child(heli)
	heli.global_position = HELIPAD
	heli.rotation_degrees.y = 200.0
	if MD.place(heli, "helicopter", Vector3.ZERO, Vector3.ZERO, Vector3.ONE, Color(0.28, 0.32, 0.27)):
		_heli_rotor = Node3D.new()
		_heli_rotor.position = Vector3(0, 3.95, -0.3)
		heli.add_child(_heli_rotor)
		for k in 4:
			var blade := B.mesh(_heli_rotor, _bm(Vector3(0.35, 0.05, 7.5)), Vector3.ZERO, M.get_mat("gun_metal"))
			blade.rotation.y = k * PI / 2.0
			blade.position = Vector3(sin(k * PI / 2.0), 0, cos(k * PI / 2.0)) * 3.75
	var hb := StaticBody3D.new()
	heli.add_child(hb)
	var hs := BoxShape3D.new()
	hs.size = Vector3(2.6, 3.0, 8.0)
	B.add_shape(hb, hs, Vector3(0, 1.6, 0.5))


func _build_boundaries() -> void:
	B.player_wall(self, Vector3(1.0, 60, 320), Vector3(-146, 30, 1135))
	B.player_wall(self, Vector3(1.0, 60, 320), Vector3(146, 30, 1135))
	B.player_wall(self, Vector3(300, 60, 1.0), Vector3(0, 30, 988))
	B.player_wall(self, Vector3(300, 60, 1.0), Vector3(0, 30, 1250))
