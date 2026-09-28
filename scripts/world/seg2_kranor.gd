extends Node3D
## SEGMENT 2 — The Logistics Hub Infiltration: Kranor Logistics Yard
## SEGMENT 3 — The Ambush and Comms Jam: the same buildings after the blackout
##
## Layout (metres):
##   Access road (asphalt) ....... x 8..22,  z 36..210
##   Container maze .............. x -64..4, z 44..126
##   Warehouse W1 + catwalks ..... x 36..76, z 56..100
##   Admin block (3 floors) ...... x 36..52, z 100..116   (terminal on the top floor)
##   Loading bay + trucks ........ x 22..36, z 58..98
##   Generators / storage ........ x -66..0, z 134..168
##   Exit gate ................... z 184

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const MD := preload("res://scripts/models.gd")
const Ladder := preload("res://scripts/world/ladder.gd")
const PowerLines := preload("res://scripts/world/powerlines.gd")

const ADMIN_MIN := Vector3(36, 0, 100)
const ADMIN_MAX := Vector3(52, 0, 116)
const FLOOR_H := 3.6
const W1_MIN := Vector3(36, 0, 56)
const W1_MAX := Vector3(76, 0, 100)
const TERMINAL_POS := Vector3(50.2, 7.2, 102.6)
const WINDOW_POS := Vector3(36.4, 3.6, 111.5)      # blown-out window on the 2nd storey
const CATWALK_DOOR := Vector3(41, 3.6, 100)
const RAMP_B_TOP := Vector3(47.2, 5.4, 106.8)   # floor-2 half landing of the stairwell
const EXIT_GATE_Z := 184.0

var game
var rng := RandomNumberGenerator.new()
var lanes: Array = []            # z of container lanes (for patrols)
var yard_lights: Array = []      # lights that die in the blackout
var yard_emissive: Array = []    # emissive materials that die in the blackout
var emergency_lights: Array = []
var window_blocker: Node3D
var window_glass: Node3D
var blackout := false
var exit_gate: Node3D
var terminal_screen: StandardMaterial3D
var _smoke: Array = []
var _hum: AudioStreamPlayer3D
var _alarm: AudioStreamPlayer
var _t := 0.0
var _catwalk_rects: Array = []   # [x0, x1, z0, z1]
var _cont_x: Array = []          # container transforms (drawn with MultiMesh)
var _cont_c: Array = []


func _ready() -> void:
	rng.seed = 404
	_build_ground_details()
	_build_containers()
	_build_warehouse()
	_build_admin()
	_build_loading_bay()
	_build_generators()
	_build_halogens()
	_build_perimeter()


func _process(delta: float) -> void:
	_t += delta
	if blackout:
		var strobe := 0.5 + 0.5 * sin(_t * 7.0)
		for l in emergency_lights:
			l.light_energy = 1.2 + strobe * 2.4


func surface_at(pos: Vector3) -> String:
	if pos.y > 3.0 and pos.y < 4.6:
		for r in _catwalk_rects:
			if pos.x > r[0] and pos.x < r[1] and pos.z > r[2] and pos.z < r[3]:
				return "metal"
	if pos.x > W1_MIN.x and pos.x < W1_MAX.x and pos.z > W1_MIN.z and pos.z < ADMIN_MAX.z:
		return "hard"
	return ""


func in_admin(pos: Vector3) -> bool:
	return pos.x > ADMIN_MIN.x and pos.x < ADMIN_MAX.x and pos.z > ADMIN_MIN.z and pos.z < ADMIN_MAX.z


func in_w1(pos: Vector3) -> bool:
	return pos.x > W1_MIN.x and pos.x < W1_MAX.x and pos.z > W1_MIN.z and pos.z < W1_MAX.z


func floor_of(pos: Vector3) -> int:
	return int(floor((pos.y + 0.5) / FLOOR_H))


# ------------------------------------------------------------------ ground

func _build_ground_details() -> void:
	# Asphalt road + painted lines
	B.box(self, Vector3(14, 0.06, 176), Vector3(15, 0.03, 123), M.get_mat("asphalt"), false)
	var paint := M.emissive(Color(0.8, 0.75, 0.5), 0.15)
	var z := 40.0
	while z < 205.0:
		B.box(self, Vector3(0.15, 0.07, 3.0), Vector3(15, 0.035, z), paint, false)
		z += 6.0
	# Puddles (shiny, dark) reflecting the lights
	var puddle := StandardMaterial3D.new()
	puddle.albedo_color = Color(0.08, 0.09, 0.1)
	puddle.roughness = 0.02
	puddle.metallic = 0.3
	for i in 26:
		var px := rng.randf_range(-60, 70)
		var pz := rng.randf_range(40, 180)
		var cm := CylinderMesh.new()
		cm.top_radius = rng.randf_range(0.8, 2.5)
		cm.bottom_radius = cm.top_radius
		cm.height = 0.02
		var pm := B.mesh(self, cm, Vector3(px, 0.02, pz), puddle, Vector3.ZERO, false)
		pm.scale = Vector3(1, 1, rng.randf_range(0.5, 1.0))


# ------------------------------------------------------------------ containers

func _build_containers() -> void:
	var colors := [Color(0.55, 0.12, 0.1), Color(0.12, 0.26, 0.5), Color(0.16, 0.4, 0.22), Color(0.75, 0.36, 0.12), Color(0.78, 0.64, 0.12), Color(0.45, 0.46, 0.47), Color(0.1, 0.35, 0.42)]
	var row_z := 46.0
	var row := 0
	while row_z < 124.0:
		lanes.append(row_z + 2.44 + 1.6)
		var x := -64.0 + rng.randf_range(0, 3)
		while x < 2.0:
			if rng.randf() < 0.18:
				x += rng.randf_range(2.8, 4.0)   # gap: a way through to the next lane
				continue
			var stack := 1 + int(rng.randf() < 0.55) + int(rng.randf() < 0.3)
			var col: Color = colors[rng.randi() % colors.size()]
			_container_stack(Vector3(x + 3.05, 0, row_z + 1.22), stack, col, 0.0)
			x += 6.3 + (rng.randf_range(0.0, 0.4))
		# Occasional crosswise container in the lane to break sightlines
		if row % 2 == 1:
			var cx := rng.randf_range(-55, -5)
			_container_stack(Vector3(cx, 0, row_z + 2.44 + 1.6), 1, colors[rng.randi() % colors.size()], 90.0)
		row_z += 2.44 + 3.2
		row += 1
	if not _cont_x.is_empty():
		MD.multi(self, "container", _cont_x, _cont_c)
	# A ladder up onto the container stacks for a sniper's view of the yard
	_container_stack(Vector3(-12, 0, 41.5), 2, Color(0.45, 0.46, 0.47), 0.0)
	Ladder.create(self, Vector3(-12, 0, 40.2), 5.2, 180.0)
	B.label3d(self, "KRANOR  LOGISTICS", Vector3(-30, 7.5, 44.9), 160, Color(0.9, 0.9, 0.85), Vector3(0, 180, 0))


func _container_stack(base: Vector3, count: int, color: Color, yaw: float) -> void:
	var size := Vector3(6.06, 2.59, 2.44)
	var body := StaticBody3D.new()
	body.position = base
	body.rotation_degrees.y = yaw
	add_child(body)
	var use_model := MD.available("container")
	for i in count:
		var c := color if i == 0 else color.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.6).darkened(0.2)
		if use_model:
			var t := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), base + Vector3(0, i * size.y, 0))
			if rng.randf() < 0.5:
				t = t * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # doors at either end
			_cont_x.append(t)
			_cont_c.append(c)
			continue
		var mat := M.tinted("corrugated", c)
		B.mesh(body, _box_mesh(size), Vector3(0, size.y / 2.0 + i * size.y, 0), mat, Vector3(0, 0, 0))
		# Door end details
		B.mesh(body, _box_mesh(Vector3(0.04, 2.4, 2.3)), Vector3(3.05, size.y / 2.0 + i * size.y, 0), M.get_mat("rust"))
		for bar in [-0.5, 0.5]:
			B.mesh(body, _box_mesh(Vector3(0.05, 2.3, 0.05)), Vector3(3.08, size.y / 2.0 + i * size.y, bar), M.get_mat("metal"))
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y * count, size.z)
	B.add_shape(body, shape, Vector3(0, size.y * count / 2.0, 0))


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


# ------------------------------------------------------------------ warehouse W1

func _build_warehouse() -> void:
	var cor := M.get_mat("corrugated")
	var h := 10.5
	var a := W1_MIN
	var b := W1_MAX
	# West wall with two open roll-up doors (loading bay side)
	B.wall_openings(self, Vector3(a.x, 0, a.z), Vector3(a.x, 0, b.z), h, 0.2, cor, [[8, 6, 0, 4.8], [24, 6, 0, 4.8]])
	B.wall_openings(self, Vector3(b.x, 0, a.z), Vector3(b.x, 0, b.z), h, 0.2, cor, [[20, 5, 0, 4.5]])
	B.wall_openings(self, Vector3(a.x, 0, a.z), Vector3(b.x, 0, a.z), h, 0.2, cor, [])
	# North wall is shared with the admin block for x 36..52
	B.wall_openings(self, Vector3(52, 0, b.z), Vector3(b.x, 0, b.z), h, 0.2, cor, [])
	B.box(self, Vector3(b.x - a.x + 1, 0.3, b.z - a.z + 1), Vector3((a.x + b.x) / 2.0, h + 0.15, (a.z + b.z) / 2.0), cor)
	# Half-open roller shutters
	if MD.available("rollup_door"):
		_warehouse_details()
	else:
		for dz in [8, 24]:
			B.box(self, Vector3(0.1, 1.2, 6), Vector3(a.x, 4.2, a.z + dz + 3), M.get_mat("hazard"), false)
	# Interior lights (die in the blackout)
	for lx in [44.0, 56.0, 68.0]:
		for lz in [64.0, 78.0, 92.0]:
			var l := B.omni(self, Vector3(lx, 9.0, lz), Color(0.9, 0.95, 1.0), 1.4, 14.0)
			yard_lights.append(l)
			var lamp_mat := M.emissive(Color(0.9, 0.95, 1.0), 3.0).duplicate()
			B.box(self, Vector3(1.4, 0.1, 0.3), Vector3(lx, 9.4, lz), lamp_mat, false)
			yard_emissive.append(lamp_mat)
			var el := B.omni(self, Vector3(lx, 8.0, lz), Color(1, 0.08, 0.05), 0.0, 12.0)
			emergency_lights.append(el)
	# Pallet racks
	var rack := M.tinted("metal", Color(0.2, 0.3, 0.6))
	var crate := M.get_mat("wood")
	for rx in [45.0, 51.0, 58.0]:
		var rz := 60.0
		while rz < 96.0:
			if rng.randf() < 0.8:
				_rack(Vector3(rx, 0, rz), rack, crate)
			rz += 5.0      # 1.3 m gaps between racks to walk through
	# Pallets, drums and crates on the warehouse floor
	for k in 10:
		MD.place(self, "pallet", Vector3(40 + (k % 5) * 1.4, 0, 60 + floorf(k / 5.0) * 1.4), Vector3(0, rng.randf_range(-8, 8), 0))
	for k in 8:
		var dp := Vector3(70 + (k % 3) * 0.7, 0, 90 + floorf(k / 3.0) * 0.7)
		var db := StaticBody3D.new()
		db.position = dp
		add_child(db)
		MD.place(db, "drum", Vector3.ZERO, Vector3(0, rng.randf() * 360, 0), Vector3.ONE, [Color(0.2, 0.3, 0.5), Color(0.55, 0.45, 0.1)][k % 2])
		var ds := CylinderShape3D.new()
		ds.radius = 0.3
		ds.height = 0.9
		B.add_shape(db, ds, Vector3(0, 0.45, 0))
	# Forklift
	var fy := M.tinted("rust", Color(0.85, 0.6, 0.1))
	B.box(self, Vector3(1.3, 1.4, 2.4), Vector3(62, 0.9, 64), fy)
	B.box(self, Vector3(1.2, 2.6, 0.12), Vector3(62, 1.5, 62.7), M.get_mat("metal"), false)
	# Catwalks at y = 3.6 criss-crossing the interior
	_catwalk(Vector3(40.2, 3.6, 76.0), Vector3(41.8, 3.6, 100.0))    # from admin 2nd floor door
	_catwalk(Vector3(38.0, 3.6, 76.0), Vector3(74.0, 3.6, 77.6))     # cross walk
	_catwalk(Vector3(66.0, 3.6, 70.0), Vector3(67.6, 3.6, 98.0))
	_catwalk_rail_colliders()
	B.stairs(self, Vector3(66.8, 0, 60.5), Vector3(66.8, 3.6, 70.0), 1.5, M.get_mat("metal"))
	B.label3d(self, "W1", Vector3(56, 8, 55.8), 200, Color(0.95, 0.85, 0.2), Vector3(0, 180, 0))


## Steel stringers, a smooth soffit underneath and a handrail for one stair flight.
## outer: +1 = rail on the +x side, -1 = rail on the -x side
func _flight_trim(bottom: Vector3, top: Vector3, width: float, outer: int) -> void:
	var steel := M.tinted("metal", Color(0.28, 0.3, 0.33))
	var rail_mat := M.tinted("metal", Color(0.75, 0.62, 0.1))      # yellow safety rail
	var d := top - bottom
	var run := Vector2(d.x, d.z).length()
	var slope := sqrt(run * run + d.y * d.y)
	var pitch := rad_to_deg(atan2(d.y, run))
	var yaw := rad_to_deg(atan2(d.x, d.z))
	var mid := (bottom + top) * 0.5
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	var side := Vector3(fwd.z, 0, -fwd.x)
	for sgn in [-1.0, 1.0]:
		# stringer: slanted steel channel along each side of the treads
		var sp: Vector3 = mid + side * sgn * (width * 0.5 + 0.04) + Vector3(0, -0.12, 0)
		B.box(self, Vector3(0.08, 0.34, slope + 0.2), sp, steel, false, Vector3(-pitch, yaw, 0))
	# soffit plate hides the stepped underside
	B.box(self, Vector3(width, 0.05, slope), mid + Vector3(0, -0.36, 0), steel, false, Vector3(-pitch, yaw, 0))
	# handrail on the open side + posts
	var rail_side: Vector3 = side * float(outer) * (width * 0.5 + 0.04)
	B.box(self, Vector3(0.05, 0.05, slope + 0.1), mid + rail_side + Vector3(0, 0.95, 0), rail_mat, false, Vector3(-pitch, yaw, 0))
	for t in [0.1, 0.5, 0.9]:
		var pp: Vector3 = bottom.lerp(top, t) + rail_side + Vector3(0, 0.5, 0)
		B.box(self, Vector3(0.05, 0.95, 0.05), pp, rail_mat, false)


func _rack(base: Vector3, frame: Material, crate: Material) -> void:
	# Every post, shelf and crate has its own collider, so you can duck/crawl through the empty bays
	for px in [-0.5, 0.5]:
		for pz in [-1.8, 1.8]:
			B.box(self, Vector3(0.1, 5.0, 0.1), base + Vector3(px, 2.5, pz), frame)
	for lvl in [0.1, 1.7, 3.3]:
		B.box(self, Vector3(1.1, 0.1, 3.7), base + Vector3(0, lvl, 0), frame)
		for k in 3:
			if rng.randf() < (0.35 if lvl < 1.0 else 0.75):     # ground bays mostly empty: crawl through
				var s := rng.randf_range(0.7, 1.0)
				B.box(self, Vector3(0.9, 1.1 * s, 1.0), base + Vector3(0, lvl + 0.05 + 0.55 * s, -1.2 + k * 1.2), crate)


func _catwalk(a: Vector3, b: Vector3) -> void:
	var grate := M.get_mat("metal")
	var size := Vector3(absf(b.x - a.x), 0.08, absf(b.z - a.z))
	var c := (a + b) / 2.0
	B.box(self, size, c, grate)
	_catwalk_rects.append([minf(a.x, b.x), maxf(a.x, b.x), minf(a.z, b.z), maxf(a.z, b.z)])
	# Railings (visual) along the long sides
	var along_x := size.x > size.z
	for side in [-1, 1]:
		var off := Vector3(0, 1.0, side * size.z / 2.0) if along_x else Vector3(side * size.x / 2.0, 1.0, 0)
		var rail_size := Vector3(size.x, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, size.z)
		B.box(self, rail_size, c + off, grate, false)
		B.box(self, rail_size, c + off - Vector3(0, 0.5, 0), grate, false)
	# Support posts
	var n := int(maxf(size.x, size.z) / 6.0)
	for i in n + 1:
		var t := float(i) / maxf(1, n)
		var p := a.lerp(b, t)
		B.box(self, Vector3(0.12, 3.6, 0.12), Vector3(p.x, 1.8, p.z), grate, false)


## Invisible walls along the catwalk railings so nobody (you or the soldiers) falls off,
## with gaps where catwalks cross each other.
func _catwalk_rail_colliders() -> void:
	for r in _catwalk_rects:
		var along_x: bool = (r[1] - r[0]) > (r[3] - r[2])
		for side in [0, 1]:
			var lo: float = r[0] if along_x else r[2]
			var hi: float = r[1] if along_x else r[3]
			var fixed: float = (r[2] if side == 0 else r[3]) if along_x else (r[0] if side == 0 else r[1])
			# gaps where another catwalk meets this side
			var gaps: Array = []
			for o in _catwalk_rects:
				if o == r:
					continue
				var o_lo: float = o[0] if along_x else o[2]
				var o_hi: float = o[1] if along_x else o[3]
				var o_c_lo: float = o[2] if along_x else o[0]
				var o_c_hi: float = o[3] if along_x else o[1]
				if fixed >= o_c_lo - 0.3 and fixed <= o_c_hi + 0.3 and o_hi > lo and o_lo < hi:
					gaps.append([o_lo - 0.1, o_hi + 0.1])
			gaps.sort_custom(func(g1, g2): return g1[0] < g2[0])
			var cur := lo
			for g in gaps + [[hi, hi]]:
				var seg_end: float = minf(g[0], hi)
				if seg_end - cur > 0.3:
					var mid := (cur + seg_end) * 0.5
					var length := seg_end - cur
					var pos := Vector3(mid, 4.15, fixed) if along_x else Vector3(fixed, 4.15, mid)
					var size := Vector3(length, 1.1, 0.1) if along_x else Vector3(0.1, 1.1, length)
					B.wall(self, size, pos)
				cur = maxf(cur, g[1])


# ------------------------------------------------------------------ admin block

func _build_admin() -> void:
	var con := M.get_mat("concrete")
	var inner := M.tinted("concrete", Color(0.75, 0.74, 0.7))
	var a := ADMIN_MIN
	var b := ADMIN_MAX
	var west_per_floor: Array = []
	for f in 3:
		var y := f * FLOOR_H
		var west := [[1.5, 2, 1.0, 2.4], [9, 1.5, 1.0, 2.4], [13, 1.8, 1.0, 2.4]]
		var south := []
		var east := [[3, 2, 1.0, 2.4], [8, 2, 1.0, 2.4], [12, 2, 1.0, 2.4]]
		var north := [[3, 2, 1.0, 2.4], [8, 2, 1.0, 2.4]]
		match f:
			0:
				west = [[4, 2, 0, 2.4], [9, 2, 1.0, 2.4], [13, 1.8, 1.0, 2.4]]   # door from the loading bay
				south = [[8, 2, 0, 2.4]]                                       # door into W1
			1:
				west = [[3, 2, 1.0, 2.4], [10, 3, 0.9, 2.6]]                   # the big window (blown out later)
				south = [[4, 2, 0, 2.4]]                                       # catwalk door
			2:
				west = [[3, 2, 1.0, 2.4], [10, 3, 1.0, 2.4]]
		west_per_floor.append(west)
		B.wall_openings(self, Vector3(a.x, y, a.z), Vector3(a.x, y, b.z), FLOOR_H, 0.3, con, west)
		B.wall_openings(self, Vector3(b.x, y, a.z), Vector3(b.x, y, b.z), FLOOR_H, 0.3, con, east)
		B.wall_openings(self, Vector3(a.x, y, a.z), Vector3(b.x, y, a.z), FLOOR_H, 0.3, con, south)
		B.wall_openings(self, Vector3(a.x, y, b.z), Vector3(b.x, y, b.z), FLOOR_H, 0.3, con, north)
		# Glass in the windows
		for w in west:
			if w[2] > 0.0:
				var g := B.box(self, Vector3(0.05, w[3] - w[2], w[1]), Vector3(a.x, y + (w[2] + w[3]) / 2.0, a.z + w[0] + w[1] / 2.0), M.get_mat("glass"))
				if f == 1 and w[0] == 10:
					window_glass = g
		for w in east:
			B.box(self, Vector3(0.05, w[3] - w[2], w[1]), Vector3(b.x, y + (w[2] + w[3]) / 2.0, a.z + w[0] + w[1] / 2.0), M.get_mat("glass"))
		for w in north:
			B.box(self, Vector3(w[1], w[3] - w[2], 0.05), Vector3(a.x + w[0] + w[1] / 2.0, y + (w[2] + w[3]) / 2.0, b.z), M.get_mat("glass"))
		# Ceiling lights
		for lx in [40.0, 46.0]:
			for lz in [104.0, 112.0]:
				var l := B.omni(self, Vector3(lx, y + 3.1, lz), Color(0.92, 0.96, 1.0), 0.9, 8.0)
				yard_lights.append(l)
				var lm := M.emissive(Color(0.95, 0.97, 1.0), 2.5).duplicate()
				B.box(self, Vector3(1.2, 0.05, 0.25), Vector3(lx, y + 3.28, lz), lm, false)
				yard_emissive.append(lm)
		emergency_lights.append(B.omni(self, Vector3(44, y + 2.8, 108), Color(1, 0.08, 0.05), 0.0, 10.0))
	# Floor slabs with the stairwell hole (x 45.4..49, z 106..116)
	for f in [1, 2]:
		var y2: float = f * FLOOR_H - 0.15
		B.box(self, Vector3(9.4, 0.3, 16), Vector3(40.7, y2, 108), inner)       # west
		B.box(self, Vector3(3.6, 0.3, 6), Vector3(47.2, y2, 103), inner)        # south of the stairwell
		B.box(self, Vector3(3, 0.3, 16), Vector3(50.5, y2, 108), inner)         # east
		# Safety rail round the stairwell hole (gap at the top landing)
		var rail := M.get_mat("metal")
		B.box(self, Vector3(0.06, 1.0, 8.5), Vector3(45.4, f * FLOOR_H + 0.5, 110.25), rail)
		B.box(self, Vector3(3.6, 1.0, 0.06), Vector3(47.2, f * FLOOR_H + 0.5, 106.0), rail)
		B.box(self, Vector3(0.06, 1.0, 10.0), Vector3(49.0, f * FLOOR_H + 0.5, 111.0), rail)
	B.box(self, Vector3(16.6, 0.3, 16.6), Vector3(44, 3 * FLOOR_H + 0.15, 108), con)
	B.box(self, Vector3(15.7, 0.04, 15.7), Vector3(44, 0.02, 108), inner, false)
	# Switchback stairs: flight A climbs south to a half landing, flight B climbs back north to the next floor
	for f in 2:
		var y0: float = f * FLOOR_H
		var half: float = FLOOR_H * 0.5
		_flight_trim(Vector3(48.1, y0, 114.8), Vector3(48.1, y0 + half, 109.2), 1.7, 1)
		_flight_trim(Vector3(46.25, y0 + half, 109.2), Vector3(46.25, y0 + FLOOR_H, 114.8), 1.7, -1)
		B.stairs(self, Vector3(48.1, y0, 114.8), Vector3(48.1, y0 + half, 109.2), 1.7, inner, false)
		B.box(self, Vector3(3.6, 0.25, 3.2), Vector3(47.2, y0 + half - 0.125, 107.6), inner)          # half landing
		B.stairs(self, Vector3(46.25, y0 + half, 109.2), Vector3(46.25, y0 + FLOOR_H, 114.8), 1.7, inner, false)
		B.box(self, Vector3(3.6, 0.25, 1.3), Vector3(47.2, y0 + FLOOR_H - 0.125, 115.35), inner)       # top landing
		B.box(self, Vector3(3.6, 0.02, 0.08), Vector3(47.2, y0 + half + 0.005, 109.2), M.get_mat("hazard"), false)   # landing edge
		B.box(self, Vector3(0.05, 0.9, 3.2), Vector3(49.0, y0 + half + 0.45, 107.6), M.tinted("metal", Color(0.75, 0.62, 0.1)), false)
		B.omni(self, Vector3(47.2, y0 + half + 2.2, 107.8), Color(1.0, 0.95, 0.85), 0.8, 6.0)
	# Invisible blocker in the big window (removed when it blows out)
	window_blocker = B.wall(self, Vector3(0.4, 1.8, 3.0), Vector3(a.x, FLOOR_H + 1.75, a.z + 11.5))

	_admin_details(west_per_floor)
	# Furniture
	var desk := M.get_mat("wood")
	var dark := M.get_mat("gear")
	B.box(self, Vector3(3.5, 1.1, 1.0), Vector3(41, 0.55, 106), desk)            # reception
	B.label3d(self, "KRANOR LOGISTICS", Vector3(41, 2.4, 100.2), 36, Color(0.9, 0.9, 0.9))
	for d in [Vector3(39, 0, 103.5), Vector3(43, 0, 103.5), Vector3(39, 0, 110), Vector3(43, 0, 110)]:
		_desk(Vector3(d.x, FLOOR_H, d.z), desk, dark)
	for d in [Vector3(39, 0, 104), Vector3(39, 0, 111)]:
		_desk(Vector3(d.x, FLOOR_H * 2, d.z), desk, dark)
	# Filing cabinets
	for i in 4:
		B.box(self, Vector3(0.5, 1.4, 0.6), Vector3(51.4, FLOOR_H + 0.7, 101 + i * 0.7), M.get_mat("metal"))
	# Server racks + the target terminal on the top floor
	for i in 3:
		B.box(self, Vector3(0.7, 2.1, 1.0), Vector3(40.5 + i * 0.9, FLOOR_H * 2 + 1.05, 115.2), dark)
		B.box(self, Vector3(0.6, 1.6, 0.02), Vector3(40.5 + i * 0.9, FLOOR_H * 2 + 1.1, 114.68), M.emissive(Color(0.2, 0.6, 1.0), 1.5), false)
	B.box(self, Vector3(2.4, 0.9, 1.0), Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 0.45, TERMINAL_POS.z - 0.6), desk)
	terminal_screen = M.emissive(Color(0.2, 0.9, 0.4), 2.0).duplicate()
	B.box(self, Vector3(0.9, 0.6, 0.05), Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 1.25, TERMINAL_POS.z - 0.9), terminal_screen, false)
	B.label3d(self, "KRANOR SECURE NODE\n> ENCRYPTED: RASKOV_LOGS", Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 1.25, TERMINAL_POS.z - 0.87), 10, Color(0.1, 0.2, 0.1))


## Window frames, trims, parapet, canopy, lamps, drainpipes and rooftop plant
func _admin_details(west_windows: Array) -> void:
	var a := ADMIN_MIN
	var b := ADMIN_MAX
	var trim := M.tinted("concrete", Color(0.8, 0.8, 0.78))
	# Horizontal concrete bands at each floor and a roof parapet
	for f in [1, 2, 3]:
		var y: float = f * FLOOR_H
		B.box(self, Vector3(16.8, 0.25, 0.12), Vector3(44, y, a.z - 0.2), trim, false)
		B.box(self, Vector3(16.8, 0.25, 0.12), Vector3(44, y, b.z + 0.2), trim, false)
		B.box(self, Vector3(0.12, 0.25, 16.8), Vector3(a.x - 0.2, y, 108), trim, false)
		B.box(self, Vector3(0.12, 0.25, 16.8), Vector3(b.x + 0.2, y, 108), trim, false)
	for side in [[Vector3(44, 11.25, a.z - 0.15), Vector3(16.6, 0.7, 0.2)], [Vector3(44, 11.25, b.z + 0.15), Vector3(16.6, 0.7, 0.2)], [Vector3(a.x - 0.15, 11.25, 108), Vector3(0.2, 0.7, 16.6)], [Vector3(b.x + 0.15, 11.25, 108), Vector3(0.2, 0.7, 16.6)]]:
		B.box(self, side[1], side[0], trim)
	# Entrance canopy + sign over the loading-bay door
	B.box(self, Vector3(1.6, 0.15, 3.2), Vector3(a.x - 0.8, 2.75, 105), trim)
	B.label3d(self, "KRANOR LOGISTICS  -  ADMINISTRATION", Vector3(a.x - 0.2, 3.1, 108), 40, Color(0.9, 0.9, 0.88), Vector3(0, -90, 0))
	# Window frames on every floor
	if MD.available("window_frame"):
		for f in 3:
			var y := f * FLOOR_H
			var west: Array = west_windows[f]
			for w in west:
				if w[2] > 0.0 and not (f == 1 and w[0] == 10):
					MD.place(self, "window_frame", Vector3(a.x - 0.17, y + w[2], a.z + w[0] + w[1] / 2.0), Vector3(0, 90, 0), Vector3(w[1], w[3] - w[2], 1))
			for w in [[3, 2, 1.0, 2.4], [8, 2, 1.0, 2.4], [12, 2, 1.0, 2.4]]:
				MD.place(self, "window_frame", Vector3(b.x + 0.17, y + w[2], a.z + w[0] + w[1] / 2.0), Vector3(0, -90, 0), Vector3(w[1], w[3] - w[2], 1))
			for w in [[3, 2, 1.0, 2.4], [8, 2, 1.0, 2.4]]:
				MD.place(self, "window_frame", Vector3(a.x + w[0] + w[1] / 2.0, y + w[2], b.z + 0.17), Vector3(0, 180, 0), Vector3(w[1], w[3] - w[2], 1))
	# Lamps over the doors (they go dark in the blackout)
	if MD.available("wall_lamp"):
		MD.place(self, "wall_lamp", Vector3(a.x - 0.16, 2.5, 106.8), Vector3(0, 90, 0))
		yard_lights.append(B.omni(self, Vector3(a.x - 0.6, 2.3, 106.8), Color(1, 0.85, 0.6), 1.5, 7.0))
		for dz in [11.0, 27.0]:
			MD.place(self, "wall_lamp", Vector3(W1_MIN.x - 0.12, 5.4, W1_MIN.z + dz), Vector3(0, 90, 0))
			yard_lights.append(B.omni(self, Vector3(W1_MIN.x - 0.7, 5.1, W1_MIN.z + dz), Color(1, 0.85, 0.6), 2.0, 10.0))
	# Drainpipes at the corners
	if MD.available("downpipe"):
		for dp in [[Vector3(a.x - 0.1, 0, a.z + 0.4), 90.0], [Vector3(a.x - 0.1, 0, b.z - 0.4), 90.0], [Vector3(b.x + 0.1, 0, b.z - 0.4), -90.0]]:
			var pipe := MD.place(self, "downpipe", dp[0], Vector3(0, dp[1], 0), Vector3(1, 3.6, 1))
			if pipe == null:
				break
		for dz in [2.0, 42.0]:
			MD.place(self, "downpipe", Vector3(W1_MIN.x - 0.1, 0, W1_MIN.z + dz), Vector3(0, 90, 0), Vector3(1, 3.4, 1))
	# Rooftop air-conditioning units
	if MD.available("hvac_unit"):
		MD.place(self, "hvac_unit", Vector3(40, 3 * FLOOR_H + 0.3, 104), Vector3(0, 90, 0))
		MD.place(self, "hvac_unit", Vector3(40.5, 3 * FLOOR_H + 0.3, 112), Vector3(0, 90, 0))
		for hx in [48.0, 60.0, 70.0]:
			MD.place(self, "hvac_unit", Vector3(hx, 10.8, 72), Vector3(0, rng.randf() * 180, 0))


## W1 exterior: concrete plinth, roof fascia and proper roll-up doors
func _warehouse_details() -> void:
	var a := W1_MIN
	var b := W1_MAX
	var con := M.get_mat("concrete")
	B.box(self, Vector3(0.15, 0.9, 5.5), Vector3(a.x - 0.1, 0.45, a.z + 5.2), con, false)
	B.box(self, Vector3(0.15, 0.9, 8.0), Vector3(a.x - 0.1, 0.45, a.z + 18.0), con, false)
	B.box(self, Vector3(0.15, 0.9, 13.5), Vector3(a.x - 0.1, 0.45, a.z + 37.2), con, false)
	B.box(self, Vector3(b.x - a.x, 0.9, 0.15), Vector3((a.x + b.x) / 2.0, 0.45, a.z - 0.1), con, false)
	B.box(self, Vector3(0.15, 0.9, b.z - a.z), Vector3(b.x + 0.1, 0.45, (a.z + b.z) / 2.0), con, false)
	var fascia := M.tinted("metal", Color(0.3, 0.32, 0.34))
	B.box(self, Vector3(0.3, 0.5, b.z - a.z + 0.6), Vector3(a.x - 0.2, 10.55, (a.z + b.z) / 2.0), fascia, false)
	B.box(self, Vector3(b.x - a.x + 0.6, 0.5, 0.3), Vector3((a.x + b.x) / 2.0, 10.55, a.z - 0.2), fascia, false)
	if MD.available("rollup_door"):
		for dz in [8.0, 24.0]:
			MD.place(self, "rollup_door", Vector3(a.x - 0.05, 3.3, a.z + dz + 3.0), Vector3(0, 90, 0), Vector3(6.0, 1.5, 1.0))
		MD.place(self, "rollup_door", Vector3(b.x + 0.05, 2.6, a.z + 22.5), Vector3(0, -90, 0), Vector3(5.0, 1.9, 1.0))


func _desk(p: Vector3, desk: Material, dark: Material) -> void:
	B.box(self, Vector3(1.8, 0.78, 0.9), p + Vector3(0, 0.39, 0), desk)
	B.box(self, Vector3(0.55, 0.38, 0.04), p + Vector3(0, 1.0, -0.2), dark, false)
	B.box(self, Vector3(0.5, 0.32, 0.02), p + Vector3(0, 1.0, -0.175), M.emissive(Color(0.3, 0.5, 0.8), 0.8), false)


# ------------------------------------------------------------------ loading bay

func _build_loading_bay() -> void:
	B.box(self, Vector3(1.0, 0.02, 44), Vector3(35.4, 0.01, 78), M.get_mat("hazard"), false)
	for tz in [67.0, 83.0, 94.0]:
		_truck(Vector3(28.5, 0, tz), 0.0)
	B.label3d(self, "LOADING BAY  1 - 3", Vector3(35.8, 6.0, 78), 64, Color(0.95, 0.85, 0.2), Vector3(0, -90, 0))


func _truck(p: Vector3, yaw: float) -> void:
	# Military cargo trucks (same Blender model as the escape truck), backed up to the docks
	var body := StaticBody3D.new()
	body.position = p
	body.rotation_degrees.y = yaw
	add_child(body)
	var tints := [Color(0.33, 0.37, 0.27), Color(0.3, 0.33, 0.28), Color(0.38, 0.36, 0.28)]
	var tint: Color = tints[int(absf(p.z)) % tints.size()]
	if MD.place(body, "supply_truck", Vector3(0.6, 0, 0), Vector3(0, 90, 0), Vector3.ONE, tint) == null:
		B.mesh(body, _box_mesh(Vector3(9.0, 3.0, 2.5)), Vector3(1.0, 2.6, 0), M.tinted("uniform", tint))
	B.truck_shapes(body, Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(0.6, 0, 0)))


# ------------------------------------------------------------------ generators / storage

func _build_generators() -> void:
	var gen := M.tinted("rust", Color(0.3, 0.4, 0.3))
	for i in 3:
		var gp := Vector3(-18 + i * 6.5, 0, 158)
		B.box(self, Vector3(5, 2.6, 2.4), gp + Vector3(0, 1.3, 0), gen)
		B.cyl(self, 0.18, 0.18, 1.5, gp + Vector3(1.8, 3.3, 0), M.get_mat("metal"), false, Vector3.ZERO, 8)
		yard_emissive.append(M.emissive(Color(0.2, 1.0, 0.3), 2.0).duplicate())
		B.box(self, Vector3(0.1, 0.1, 0.1), gp + Vector3(-2.51, 2.0, 0.6), yard_emissive[-1], false)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = S.get_stream("hum")
	_hum.position = Vector3(-12, 1.5, 158)
	_hum.unit_size = 10.0
	_hum.volume_db = -4.0
	_hum.max_distance = 90.0
	add_child(_hum)
	_hum.play()
	# Substation: transformer inside a fenced compound (it blows during the ambush)
	var sub := Vector3(28, 0, 121)
	if MD.available("transformer"):
		var tb := StaticBody3D.new()
		tb.position = sub
		add_child(tb)
		MD.place(tb, "transformer", Vector3.ZERO, Vector3(0, 90, 0))
		var ts := BoxShape3D.new()
		ts.size = Vector3(2.4, 2.6, 3.2)
		B.add_shape(tb, ts, Vector3(0, 1.3, 0))
	else:
		B.box(self, Vector3(2.5, 3.0, 2.5), sub + Vector3(0, 1.5, 0), M.tinted("metal", Color(0.4, 0.45, 0.4)))
	B.box(self, Vector3(6.5, 0.2, 7.5), sub + Vector3(0, 0.1, 0), M.get_mat("gravel") if M.get_mat("gravel") else M.get_mat("concrete"), false)
	var link := M.get_mat("chainlink")
	for fence in [[Vector3(-3.2, 1.25, 0), Vector3(0.04, 2.5, 7.4)], [Vector3(3.2, 1.25, 0), Vector3(0.04, 2.5, 7.4)], [Vector3(0, 1.25, 3.7), Vector3(6.4, 2.5, 0.04)], [Vector3(-2.0, 1.25, -3.7), Vector3(2.4, 2.5, 0.04)], [Vector3(2.0, 1.25, -3.7), Vector3(2.4, 2.5, 0.04)]]:
		B.box(self, fence[1], sub + fence[0], link)
	for c in [Vector3(-3.2, 0, -3.7), Vector3(3.2, 0, -3.7), Vector3(-3.2, 0, 3.7), Vector3(3.2, 0, 3.7)]:
		B.cyl(self, 0.05, 0.05, 2.7, sub + c + Vector3(0, 1.35, 0), M.get_mat("metal"), false, Vector3.ZERO, 6)
	B.label3d(self, "DANGER  -  HIGH VOLTAGE\nKEEP OUT", sub + Vector3(0, 1.8, -3.75), 28, Color(0.95, 0.8, 0.1), Vector3(0, 180, 0))
	# Overhead line feeding the substation from the valley
	if MD.available("power_pole"):
		PowerLines.build(self, [Vector3(6, 0, 44), Vector3(6, 0, 72), Vector3(6, 0, 100), Vector3(12, 0, 124), Vector3(23, 0, 124)])
	# Storage warehouse W2
	var cor := M.tinted("corrugated", Color(0.55, 0.5, 0.45))
	B.wall_openings(self, Vector3(-66, 0, 134), Vector3(-36, 0, 134), 8, 0.2, cor, [[12, 6, 0, 4.5]])
	B.wall_openings(self, Vector3(-66, 0, 168), Vector3(-36, 0, 168), 8, 0.2, cor, [])
	B.wall_openings(self, Vector3(-66, 0, 134), Vector3(-66, 0, 168), 8, 0.2, cor, [])
	B.wall_openings(self, Vector3(-36, 0, 134), Vector3(-36, 0, 168), 8, 0.2, cor, [[10, 5, 0, 4.0]])
	B.box(self, Vector3(31, 0.3, 35), Vector3(-51, 8.15, 151), cor)
	for i in 8:
		B.box(self, Vector3(1.2, 1.2, 1.2), Vector3(-60 + (i % 4) * 2.5, 0.6, 142 + floorf(i / 4.0) * 12.0), M.get_mat("wood"))
	var l := B.omni(self, Vector3(-51, 7, 151), Color(1, 0.85, 0.6), 1.0, 20.0)
	yard_lights.append(l)


func _build_halogens() -> void:
	var metal := M.get_mat("metal")
	for p in [Vector3(4, 0, 50), Vector3(-30, 0, 88), Vector3(6, 0, 118), Vector3(-10, 0, 140), Vector3(26, 0, 150), Vector3(-44, 0, 126), Vector3(30, 0, 60), Vector3(8, 0, 176)]:
		B.cyl(self, 0.12, 0.18, 12.0, p + Vector3(0, 6, 0), metal, true, Vector3.ZERO, 8)
		var yaw_h := rng.randf() * 360.0
		if MD.available("floodlight_head"):
			MD.place(self, "floodlight_head", p + Vector3(0, 12.1, 0), Vector3(-20, yaw_h, 0))
			yard_emissive.append(MD.material_for("lamp_glass", Color.WHITE))
		else:
			B.box(self, Vector3(2.2, 0.8, 0.3), p + Vector3(0, 12.1, 0), metal, false)
			var lamp := M.emissive(Color(1, 0.98, 0.92), 6.0).duplicate()
			B.box(self, Vector3(2.0, 0.6, 0.05), p + Vector3(0, 12.1, -0.18), lamp, false)
			yard_emissive.append(lamp)
		var yaw := rng.randf() * 360.0
		var sp := B.spot(self, p + Vector3(0, 12.0, 0), Vector3(-62, yaw, 0), Color(1, 0.97, 0.9), 9.0, 38.0, 42.0, true)
		sp.light_volumetric_fog_energy = 2.0
		yard_lights.append(sp)


func _build_perimeter() -> void:
	var link := M.get_mat("chainlink")
	var post := M.get_mat("metal")
	for side in [-80.0, 80.0]:
		var z := 36.0
		while z < EXIT_GATE_Z:
			B.box(self, Vector3(0.04, 3.0, 3.0), Vector3(side, 1.5, z + 1.5), link)
			B.cyl(self, 0.05, 0.05, 3.4, Vector3(side, 1.7, z), post, false, Vector3.ZERO, 6)
			z += 3.0
	var x := -80.0
	while x < 80.0:
		if x < 7.0 or x > 23.0:
			B.box(self, Vector3(3.0, 3.0, 0.04), Vector3(x + 1.5, 1.5, EXIT_GATE_Z), link)
		x += 3.0
	# The exit gate the truck will smash through
	exit_gate = StaticBody3D.new()
	exit_gate.position = Vector3(15, 0, EXIT_GATE_Z)
	add_child(exit_gate)
	B.mesh(exit_gate, _box_mesh(Vector3(16, 2.8, 0.1)), Vector3(0, 1.4, 0), link)
	B.mesh(exit_gate, _box_mesh(Vector3(16, 0.2, 0.2)), Vector3(0, 2.8, 0), M.get_mat("hazard"))
	var shape := BoxShape3D.new()
	shape.size = Vector3(16, 2.8, 0.3)
	B.add_shape(exit_gate, shape, Vector3(0, 1.4, 0))
	B.box(self, Vector3(3, 2.6, 3), Vector3(27, 1.3, EXIT_GATE_Z - 4), M.get_mat("corrugated"))


# ------------------------------------------------------------------ SEGMENT 3: blackout

func start_blackout() -> void:
	if blackout:
		return
	blackout = true
	S.play3d(self, "explosion", Vector3(28, 2, 118), 10.0, 0.0, 200.0)
	for l in yard_lights:
		l.light_energy = 0.0
	for m in yard_emissive:
		m.emission_energy_multiplier = 0.0
	terminal_screen.emission = Color(1, 0.2, 0.1)
	if _hum:
		_hum.stop()
	_alarm = S.loop2d(self, "alarm", -18.0)
	# The transformer blast blows the window in
	if window_glass:
		window_glass.queue_free()
	# (the invisible blocker stays until Reyes' truck arrives: see open_window())
	_explosion_fx(Vector3(28, 2, 118))
	_explosion_fx(WINDOW_POS + Vector3(-1, 1, 0))
	# Smoke rolling through the halls
	for sp in [Vector3(44, FLOOR_H + 1.2, 106), Vector3(44, FLOOR_H * 2 + 1.2, 108), Vector3(41, FLOOR_H + 1.5, 100.5), Vector3(56, 4.5, 80)]:
		_smoke_at(sp)
	# New obstacles: overturned desks, collapsed stairwell, locked exits
	var desk := M.get_mat("wood")
	B.box(self, Vector3(1.8, 0.9, 0.8), Vector3(44, FLOOR_H + 0.45, 106.5), desk, true, Vector3(0, 20, 85))
	B.box(self, Vector3(1.8, 0.9, 0.8), Vector3(40, FLOOR_H + 0.45, 107), desk, true, Vector3(0, -35, -85))
	var rubble := M.tinted("concrete", Color(0.5, 0.48, 0.45))
	for i in 5:
		B.box(self, Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.6, 1.2), rng.randf_range(0.8, 1.6)), Vector3(46.3 + rng.randf_range(-0.4, 0.4), FLOOR_H - 0.6 + i * 0.2, 112.2 + rng.randf_range(-0.8, 0.8)), rubble, true, Vector3(rng.randf() * 40, rng.randf() * 90, rng.randf() * 40))
	B.box(self, Vector3(1.7, 1.6, 1.4), Vector3(46.25, FLOOR_H - 0.4, 113.0), rubble)   # collapsed flight: blocks the way down
	# The stairwell below the middle floor caves in completely: a slab of rubble fills the hole
	B.box(self, Vector3(3.5, 0.5, 8.65), Vector3(47.2, FLOOR_H - 0.25, 110.35), rubble)
	for i in 6:
		B.box(self, Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.15, 0.35), rng.randf_range(0.4, 0.9)), Vector3(rng.randf_range(45.8, 46.8), FLOOR_H + 0.08, rng.randf_range(106.8, 111.5)), rubble, false, Vector3(rng.randf() * 20, rng.randf() * 90, rng.randf() * 20))
	lockdown()


## POWER FAILURE LOCKDOWN: steel shutters slam down over every door out of the admin block
var shutters := {}
var _catwalk_block: Node3D


func lockdown() -> void:
	_shutter("west", Vector3(0.12, 2.4, 2.0), Vector3(ADMIN_MIN.x, 1.2, 105))           # ground floor, loading-bay door
	_shutter("south", Vector3(2.0, 2.4, 0.12), Vector3(45, 1.2, ADMIN_MIN.z))            # ground floor, door into W1
	_shutter("catwalk", Vector3(2.0, 2.4, 0.12), Vector3(41, FLOOR_H + 1.2, ADMIN_MIN.z)) # middle floor, catwalk door
	for k in shutters:
		close_shutter(k, 0.4 + randf() * 0.6)


func _shutter(key: String, size: Vector3, closed_pos: Vector3) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	body.position = closed_pos + Vector3(0, 2.45, 0)
	var steel := M.tinted("corrugated", Color(0.45, 0.42, 0.38))
	B.mesh(body, _box_mesh(size), Vector3.ZERO, steel)
	var strip := size
	strip.y = 0.18
	strip.x += 0.01 if size.x < 0.5 else 0.0
	strip.z += 0.01 if size.z < 0.5 else 0.0
	B.mesh(body, _box_mesh(strip), Vector3(0, -size.y / 2.0 + 0.09, 0), M.get_mat("hazard"))
	var shape := BoxShape3D.new()
	shape.size = size
	B.add_shape(body, shape, Vector3.ZERO)
	body.visible = false
	body.set_meta("closed", closed_pos)
	shutters[key] = body


func close_shutter(key: String, delay := 0.0) -> void:
	var body: Node3D = shutters.get(key)
	if body == null:
		return
	var closed: Vector3 = body.get_meta("closed")
	var tw := body.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		body.visible = true
		S.play3d(self, "door", closed, 4.0))
	tw.tween_property(body, "position", closed, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): S.play3d(self, "impact", closed, 2.0))


func open_shutter(key: String) -> void:
	var body: Node3D = shutters.get(key)
	if body == null:
		return
	var closed: Vector3 = body.get_meta("closed")
	S.play3d(self, "door", closed, 6.0)
	var tw := body.create_tween()
	tw.tween_property(body, "position", closed + Vector3(0, 2.45, 0), 1.0)


## The QRF forces the catwalk door open. They can come in; Vance still can't go out that way.
func breach_catwalk_door() -> void:
	open_shutter("catwalk")
	_explosion_fx(CATWALK_DOOR + Vector3(0, 1.2, -0.5))
	if _catwalk_block == null:
		_catwalk_block = B.player_wall(self, Vector3(2.2, 2.6, 0.6), Vector3(41, FLOOR_H + 1.3, ADMIN_MIN.z - 0.1))


func reseal_catwalk_door() -> void:
	close_shutter("catwalk", 1.5)
	if _catwalk_block:
		var blk := _catwalk_block
		_catwalk_block = null
		get_tree().create_timer(3.0).timeout.connect(blk.queue_free)


## Reyes is under the window: now you can jump
func open_window() -> void:
	if window_blocker and is_instance_valid(window_blocker):
		window_blocker.queue_free()
		window_blocker = null


func _explosion_fx(pos: Vector3) -> void:
	var l := B.omni(self, pos, Color(1, 0.6, 0.25), 12.0, 25.0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -9, 0)
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.06, 0.06)
	p.mesh = sm
	p.material_override = M.emissive(Color(1, 0.6, 0.2), 4.0)
	add_child(p)
	p.global_position = pos
	p.emitting = true


func _smoke_at(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 60
	p.lifetime = 7.0
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 8, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3, 0.5, 3)
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.05, 0)
	pm.scale_min = 2.0
	pm.scale_max = 4.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.24, 0.24, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_tex()
	q.material = mat
	p.draw_pass_1 = q
	add_child(p)
	_smoke.append(p)


var _soft: Texture2D
func _soft_tex() -> Texture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_soft = t
	return t


func stop_alarm() -> void:
	if _alarm:
		_alarm.stop()


func smash_exit_gate() -> void:
	if exit_gate == null:
		return
	S.play3d(self, "door", exit_gate.global_position, 8.0)
	for c in exit_gate.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	var tw := create_tween()
	tw.tween_property(exit_gate, "rotation_degrees:x", 85.0, 0.4)
	tw.parallel().tween_property(exit_gate, "position:z", EXIT_GATE_Z + 3.0, 0.4)
