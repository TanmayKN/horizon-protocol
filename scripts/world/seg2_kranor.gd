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

const ADMIN_MIN := Vector3(36, 0, 100)
const ADMIN_MAX := Vector3(52, 0, 116)
const FLOOR_H := 3.6
const W1_MIN := Vector3(36, 0, 56)
const W1_MAX := Vector3(76, 0, 100)
const TERMINAL_POS := Vector3(50.2, 7.2, 102.6)
const WINDOW_POS := Vector3(36.4, 3.6, 111.5)      # blown-out window on the 2nd storey
const CATWALK_DOOR := Vector3(41, 3.6, 100)
const RAMP_B_TOP := Vector3(47.5, 7.2, 107.5)
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
	B.label3d(self, "KRANOR  LOGISTICS", Vector3(-30, 7.5, 44.9), 160, Color(0.9, 0.9, 0.85), Vector3(0, 180, 0))


func _container_stack(base: Vector3, count: int, color: Color, yaw: float) -> void:
	var size := Vector3(6.06, 2.59, 2.44)
	var body := StaticBody3D.new()
	body.position = base
	body.rotation_degrees.y = yaw
	add_child(body)
	for i in count:
		var c := color if i == 0 else color.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.6).darkened(0.2)
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
			rz += 4.2
	# Forklift
	var fy := M.tinted("rust", Color(0.85, 0.6, 0.1))
	B.box(self, Vector3(1.3, 1.4, 2.4), Vector3(62, 0.9, 64), fy)
	B.box(self, Vector3(1.2, 2.6, 0.12), Vector3(62, 1.5, 62.7), M.get_mat("metal"), false)
	# Catwalks at y = 3.6 criss-crossing the interior
	_catwalk(Vector3(40.2, 3.6, 76.0), Vector3(41.8, 3.6, 100.0))    # from admin 2nd floor door
	_catwalk(Vector3(38.0, 3.6, 76.0), Vector3(74.0, 3.6, 77.6))     # cross walk
	_catwalk(Vector3(66.0, 3.6, 70.0), Vector3(67.6, 3.6, 98.0))
	B.stairs(self, Vector3(66.8, 0, 60.5), Vector3(66.8, 3.6, 70.0), 1.5, M.get_mat("metal"))
	B.label3d(self, "W1", Vector3(56, 8, 55.8), 200, Color(0.95, 0.85, 0.2), Vector3(0, 180, 0))


func _rack(base: Vector3, frame: Material, crate: Material) -> void:
	var body := StaticBody3D.new()
	body.position = base
	add_child(body)
	for px in [-0.5, 0.5]:
		for pz in [-1.8, 1.8]:
			B.mesh(body, _box_mesh(Vector3(0.1, 5.0, 0.1)), Vector3(px, 2.5, pz), frame)
	for lvl in [0.1, 1.7, 3.3]:
		B.mesh(body, _box_mesh(Vector3(1.1, 0.1, 3.7)), Vector3(0, lvl, 0), frame)
		for k in 3:
			if rng.randf() < 0.75:
				var s := rng.randf_range(0.7, 1.0)
				B.mesh(body, _box_mesh(Vector3(0.9, 1.1 * s, 1.0)), Vector3(0, lvl + 0.05 + 0.55 * s, -1.2 + k * 1.2), crate)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 5.0, 3.7)
	B.add_shape(body, shape, Vector3(0, 2.5, 0))


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


# ------------------------------------------------------------------ admin block

func _build_admin() -> void:
	var con := M.get_mat("concrete")
	var inner := M.tinted("concrete", Color(0.75, 0.74, 0.7))
	var a := ADMIN_MIN
	var b := ADMIN_MAX
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
	# Floor slabs with the stairwell hole (x 46..49, z 108..116)
	for f in [1, 2]:
		var y2: float = f * FLOOR_H - 0.15
		B.box(self, Vector3(10, 0.3, 16), Vector3(41, y2, 108), inner)
		B.box(self, Vector3(3, 0.3, 8), Vector3(47.5, y2, 104), inner)
		B.box(self, Vector3(3, 0.3, 16), Vector3(50.5, y2, 108), inner)
	B.box(self, Vector3(16.6, 0.3, 16.6), Vector3(44, 3 * FLOOR_H + 0.15, 108), con)
	B.box(self, Vector3(16, 0.1, 16), Vector3(44, 0.05, 108), inner)
	# Stairs (stacked switchbacks)
	B.stairs(self, Vector3(47.5, 0, 115.6), Vector3(47.5, FLOOR_H, 108.0), 2.8, inner)
	B.stairs(self, Vector3(47.5, FLOOR_H, 115.6), Vector3(47.5, FLOOR_H * 2, 108.0), 2.8, inner)
	# Stairwell side wall so you can't fall off the ramps
	B.box(self, Vector3(0.15, FLOOR_H * 3, 8), Vector3(45.9, FLOOR_H * 1.5, 112), inner)
	# Invisible blocker in the big window (removed when it blows out)
	window_blocker = B.wall(self, Vector3(0.4, 1.8, 3.0), Vector3(a.x, FLOOR_H + 1.75, a.z + 11.5))

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
		B.box(self, Vector3(0.7, 2.1, 1.0), Vector3(43.5 + i * 0.9, FLOOR_H * 2 + 1.05, 115.2), dark)
		B.box(self, Vector3(0.6, 1.6, 0.02), Vector3(43.5 + i * 0.9, FLOOR_H * 2 + 1.1, 114.68), M.emissive(Color(0.2, 0.6, 1.0), 1.5), false)
	B.box(self, Vector3(2.4, 0.9, 1.0), Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 0.45, TERMINAL_POS.z - 0.6), desk)
	terminal_screen = M.emissive(Color(0.2, 0.9, 0.4), 2.0).duplicate()
	B.box(self, Vector3(0.9, 0.6, 0.05), Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 1.25, TERMINAL_POS.z - 0.9), terminal_screen, false)
	B.label3d(self, "KRANOR SECURE NODE\n> ENCRYPTED: RASKOV_LOGS", Vector3(TERMINAL_POS.x - 0.2, FLOOR_H * 2 + 1.25, TERMINAL_POS.z - 0.87), 10, Color(0.1, 0.2, 0.1))


func _desk(p: Vector3, desk: Material, dark: Material) -> void:
	B.box(self, Vector3(1.8, 0.78, 0.9), p + Vector3(0, 0.39, 0), desk)
	B.box(self, Vector3(0.55, 0.38, 0.04), p + Vector3(0, 1.0, -0.2), dark, false)
	B.box(self, Vector3(0.5, 0.32, 0.02), p + Vector3(0, 1.0, -0.175), M.emissive(Color(0.3, 0.5, 0.8), 0.8), false)


# ------------------------------------------------------------------ loading bay

func _build_loading_bay() -> void:
	B.box(self, Vector3(1.0, 0.02, 44), Vector3(35.4, 0.01, 78), M.get_mat("hazard"), false)
	for tz in [67.0, 83.0, 94.0]:
		_truck(Vector3(28.5, 0, tz), 0.0)
	# Dock bumpers + lights
	for dz in [67.0, 83.0]:
		B.box(self, Vector3(0.3, 0.5, 0.4), Vector3(36.2, 1.2, dz - 1.4), M.get_mat("black"))
		B.box(self, Vector3(0.3, 0.5, 0.4), Vector3(36.2, 1.2, dz + 1.4), M.get_mat("black"))
	B.label3d(self, "LOADING BAY  1 - 3", Vector3(35.8, 6.0, 78), 64, Color(0.95, 0.85, 0.2), Vector3(0, -90, 0))


func _truck(p: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.position = p
	body.rotation_degrees.y = yaw
	add_child(body)
	var trailer := M.tinted("corrugated", Color(0.8, 0.8, 0.78))
	var cab := M.tinted("rust", Color(0.2, 0.25, 0.35))
	B.mesh(body, _box_mesh(Vector3(9.0, 3.0, 2.5)), Vector3(1.0, 2.6, 0), trailer)
	B.mesh(body, _box_mesh(Vector3(2.4, 2.6, 2.4)), Vector3(-5.0, 1.9, 0), cab)
	B.mesh(body, _box_mesh(Vector3(0.05, 1.0, 2.0)), Vector3(-6.21, 2.5, 0), M.get_mat("glass"))
	for wx in [-5.0, -1.0, 3.5, 4.8]:
		for wz in [-1.1, 1.1]:
			var wheel := B.mesh(body, CylinderMesh.new(), Vector3(wx, 0.5, wz), M.get_mat("black"), Vector3(90, 0, 0))
			wheel.scale = Vector3(0.5, 0.18, 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(11.4, 4.1, 2.5)
	B.add_shape(body, shape, Vector3(0, 2.05, 0))


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
	# Transformer (blows during the ambush)
	B.box(self, Vector3(2.5, 3.0, 2.5), Vector3(28, 1.5, 118), M.tinted("metal", Color(0.4, 0.45, 0.4)))
	B.label3d(self, "DANGER  HIGH VOLTAGE", Vector3(28, 2.0, 116.7), 24, Color(0.95, 0.8, 0.1), Vector3(0, 180, 0))
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
	if window_blocker:
		window_blocker.queue_free()
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
		B.box(self, Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(0.6, 1.4), rng.randf_range(1.0, 2.0)), Vector3(47.5 + rng.randf_range(-1, 1), FLOOR_H + 0.5 + i * 0.25, 108.8 + rng.randf_range(-0.6, 0.6)), rubble, true, Vector3(rng.randf() * 40, rng.randf() * 90, rng.randf() * 40))
	B.box(self, Vector3(3.0, 1.2, 0.8), Vector3(47.5, FLOOR_H + 0.6, 107.6), rubble)   # blocks the way down
	B.box(self, Vector3(0.2, 2.4, 2.0), Vector3(36, 1.2, 105), M.tinted("metal", Color(0.4, 0.1, 0.08)))   # locked door
	B.box(self, Vector3(2.0, 2.4, 0.2), Vector3(45, 1.2, 100), M.tinted("metal", Color(0.4, 0.1, 0.08)))   # locked door


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
