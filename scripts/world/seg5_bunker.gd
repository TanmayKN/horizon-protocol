extends Node3D
## SEGMENT 5 — The Subterranean Stronghold: Vanguard Command Bunker
## Brutalist cold-war bunker cut into the mountain at the end of the pass. Floor level y = 19.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const MD := preload("res://scripts/models.gd")

const Y := 19.0
const HALL_MIN := Vector3(0, 19, 604)
const HALL_MAX := Vector3(20, 19, 632)
const SERVER_MIN := Vector3(-12, 19, 660)
const SERVER_MAX := Vector3(32, 19, 692)
const CMD_FLOOR := 22.0
const BREACH_POS := Vector3(-9, 22, 692)
const VAULT_POS := Vector3(10, 22, 706)
const DRIVE_POS := Vector3(10, 23.1, 712)
const GATE_Z := 603.0

var game
var rng := RandomNumberGenerator.new()
var gate: Node3D
var breach_door: Node3D
var vault_door: Node3D
var drive: Node3D
var flicker_lights: Array = []
var _vent: AudioStreamPlayer
var _t := 0.0


func _ready() -> void:
	rng.seed = 1983
	_build_shell()
	_build_hall()
	_build_tunnels()
	_build_server_room()
	_build_command_center()
	_build_vault()


func _process(delta: float) -> void:
	_t += delta
	for l in flicker_lights:
		if rng.randf() < 0.01:
			l.light_energy = 0.2
		else:
			l.light_energy = move_toward(l.light_energy, l.get_meta("base"), delta * 8.0)


func inside(pos: Vector3) -> bool:
	return pos.z > GATE_Z + 1.0 and pos.z < 720.0 and pos.x > -22 and pos.x < 42 and pos.y > 17.0


func surface_at(pos: Vector3) -> String:
	return "hard" if inside(pos) else ""


func in_server_room(pos: Vector3) -> bool:
	return pos.x > SERVER_MIN.x and pos.x < SERVER_MAX.x and pos.z > SERVER_MIN.z and pos.z < SERVER_MAX.z


func _fluoro(pos: Vector3, energy := 1.1, rng_dist := 9.0) -> void:
	var l := B.omni(self, pos, Color(0.85, 0.93, 1.0), energy, rng_dist)
	l.set_meta("base", energy)
	flicker_lights.append(l)
	B.box(self, Vector3(1.4, 0.06, 0.2), pos + Vector3(0, 0.25, 0), M.emissive(Color(0.9, 0.95, 1.0), 2.5), false)


# ------------------------------------------------------------------ shell

func _build_shell() -> void:
	var rock := M.tinted("concrete", Color(0.42, 0.42, 0.4))
	# Mountain mass around the bunker (visual)
	B.box(self, Vector3(60, 70, 160), Vector3(-52, 45, 683), rock, false)
	B.box(self, Vector3(60, 70, 160), Vector3(72, 45, 683), rock, false)
	B.box(self, Vector3(64, 50, 160), Vector3(10, 56, 683), rock, false)
	# Portal face with the blast gate
	var con := M.get_mat("concrete")
	B.wall_openings(self, Vector3(-22, Y, GATE_Z), Vector3(42, Y, GATE_Z), 12.0, 2.0, con, [[25, 14, 0, 7.5]])
	B.box(self, Vector3(16, 1.2, 3), Vector3(10, Y + 8.1, GATE_Z - 0.5), M.get_mat("hazard"), false)
	B.label3d(self, "VANGUARD CORP  -  SITE 9", Vector3(10, Y + 9.6, GATE_Z - 1.1), 96, Color(0.85, 0.85, 0.8), Vector3(0, 180, 0))
	B.omni(self, Vector3(10, Y + 7.5, GATE_Z - 3), Color(1, 0.8, 0.5), 2.0, 16.0)
	# The gate (the truck smashes it)
	gate = StaticBody3D.new()
	gate.position = Vector3(10, Y, GATE_Z)
	add_child(gate)
	var gm := BoxMesh.new()
	gm.size = Vector3(14, 7.5, 0.5)
	B.mesh(gate, gm, Vector3(0, 3.75, 0), M.tinted("metal", Color(0.35, 0.36, 0.34)))
	var gs := BoxShape3D.new()
	gs.size = Vector3(14, 7.5, 0.5)
	B.add_shape(gate, gs, Vector3(0, 3.75, 0))
	# Floor + ceiling for the whole complex
	B.box(self, Vector3(64, 1.0, 118), Vector3(10, Y - 0.5, 662), con)
	B.box(self, Vector3(64, 1.0, 118), Vector3(10, Y + 11.5, 662), con, false)
	_vent = S.loop2d(self, "vent", -80.0)


func smash_gate() -> void:
	S.play3d(self, "explosion", gate.global_position, 8.0)
	for c in gate.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	var tw := create_tween()
	tw.tween_property(gate, "rotation_degrees:x", -80.0, 0.5)
	tw.parallel().tween_property(gate, "position", gate.position + Vector3(2, 0.3, 9), 0.5)


func set_ambience(on: bool) -> void:
	_vent.volume_db = -10.0 if on else -80.0
	# Echoing footsteps on hard concrete
	var bus := AudioServer.get_bus_index("Master")
	if on and AudioServer.get_bus_effect_count(bus) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.7
		rev.damping = 0.3
		rev.wet = 0.25
		AudioServer.add_bus_effect(bus, rev)
	elif not on:
		while AudioServer.get_bus_effect_count(bus) > 0:
			AudioServer.remove_bus_effect(bus, 0)


# ------------------------------------------------------------------ hall

func _build_hall() -> void:
	var con := M.get_mat("concrete")
	var a := HALL_MIN
	var b := HALL_MAX
	var h := 8.0
	B.wall_openings(self, Vector3(a.x, Y, a.z), Vector3(a.x, Y, b.z), h, 0.8, con, [])
	B.wall_openings(self, Vector3(b.x, Y, a.z), Vector3(b.x, Y, b.z), h, 0.8, con, [[11, 2.2, 0, 2.6]])   # utility tunnel door (z 615)
	B.wall_openings(self, Vector3(a.x, Y, b.z), Vector3(b.x, Y, b.z), h, 0.8, con, [[8.5, 3, 0, 3.4]])     # corridor A
	B.box(self, Vector3(20, 0.5, 28), Vector3(10, Y + h + 0.25, 618), con)
	# Concrete barrier the truck ends up pinned against
	B.box(self, Vector3(10, 1.3, 1.2), Vector3(10, Y + 0.65, 626), M.tinted("concrete", Color(0.75, 0.72, 0.65)))
	B.box(self, Vector3(10, 0.3, 1.25), Vector3(10, Y + 1.3, 626), M.get_mat("hazard"), false)
	# Crates, sandbag positions, drums, a jeep
	for cp in [Vector3(3, 0, 610), Vector3(4.4, 0, 611), Vector3(16, 0, 622), Vector3(3.5, 0, 628)]:
		var cb := StaticBody3D.new()
		cb.position = Vector3(cp.x, Y, cp.z)
		add_child(cb)
		if MD.place(cb, "crate", Vector3.ZERO, Vector3(0, rng.randf() * 30, 0)) == null:
			B.mesh(cb, BoxMesh.new(), Vector3(0, 0.55, 0), M.get_mat("wood"))
		var cs := BoxShape3D.new()
		cs.size = Vector3(1.1, 1.1, 1.1)
		B.add_shape(cb, cs, Vector3(0, 0.55, 0))
	for sp in [Vector3(6, 0, 630), Vector3(14, 0, 630)]:
		var sb := StaticBody3D.new()
		sb.position = Vector3(sp.x, Y, sp.z)
		add_child(sb)
		MD.place(sb, "sandbags", Vector3.ZERO, Vector3(0, 0, 0), Vector3(0.9, 1.0, 1.0))
		var ss := BoxShape3D.new()
		ss.size = Vector3(2.2, 0.6, 0.5)
		B.add_shape(sb, ss, Vector3(0, 0.3, 0))
	B.box(self, Vector3(2.0, 1.4, 4.0), Vector3(16.5, Y + 0.9, 609), M.tinted("rust", Color(0.3, 0.33, 0.25)))
	for lz in [610.0, 620.0, 629.0]:
		_fluoro(Vector3(10, Y + 7.2, lz), 1.4, 12.0)
	B.label3d(self, "SECTOR A", Vector3(10, Y + 4.4, 631.5), 64, Color(0.9, 0.85, 0.2), Vector3(0, 180, 0))
	# Corridor A (hall -> server room)
	B.wall_openings(self, Vector3(8.5, Y, 632), Vector3(8.5, Y, 660), 3.5, 0.4, con, [])
	B.wall_openings(self, Vector3(11.5, Y, 632), Vector3(11.5, Y, 660), 3.5, 0.4, con, [])
	B.box(self, Vector3(3.4, 0.4, 28), Vector3(10, Y + 3.7, 646), con)
	for lz in [638.0, 648.0, 656.0]:
		_fluoro(Vector3(10, Y + 3.2, lz), 0.9, 7.0)
	# Steel blast doors (open) in the corridor
	B.box(self, Vector3(0.3, 3.4, 1.4), Vector3(8.8, Y + 1.7, 645), M.tinted("metal", Color(0.3, 0.32, 0.3)))
	B.box(self, Vector3(0.3, 3.4, 1.4), Vector3(11.2, Y + 1.7, 645), M.tinted("metal", Color(0.3, 0.32, 0.3)))


# ------------------------------------------------------------------ utility tunnels

func _build_tunnels() -> void:
	var con := M.tinted("concrete", Color(0.55, 0.55, 0.52))
	var pipe := M.get_mat("rust")
	# East from the hall
	B.wall_openings(self, Vector3(20, Y, 614), Vector3(32, Y, 614), 2.8, 0.3, con, [])
	B.wall_openings(self, Vector3(20, Y, 617.4), Vector3(30, Y, 617.4), 2.8, 0.3, con, [])
	B.box(self, Vector3(12, 0.3, 3.6), Vector3(26, Y + 2.95, 615.7), con)
	# North to the server room
	B.wall_openings(self, Vector3(29.7, Y, 617.4), Vector3(29.7, Y, 660), 2.8, 0.3, con, [])
	B.wall_openings(self, Vector3(32.3, Y, 614), Vector3(32.3, Y, 660), 2.8, 0.3, con, [])
	B.box(self, Vector3(2.9, 0.3, 46), Vector3(31, Y + 2.95, 637), con)
	for k in 2:
		B.cyl(self, 0.12, 0.12, 44, Vector3(32.0, Y + 2.2 - k * 0.35, 638), pipe, false, Vector3(90, 0, 0), 8)
	for lz in [616.0, 628.0, 642.0, 654.0]:
		var l := B.omni(self, Vector3(31, Y + 2.4, lz), Color(1.0, 0.75, 0.45), 0.6, 6.0)
		l.set_meta("base", 0.6)
		flicker_lights.append(l)


# ------------------------------------------------------------------ server room

func _build_server_room() -> void:
	var con := M.get_mat("concrete")
	var a := SERVER_MIN
	var b := SERVER_MAX
	var h := 8.0
	B.wall_openings(self, Vector3(a.x, Y, a.z), Vector3(b.x, Y, a.z), h, 0.8, con, [[20.5, 3, 0, 3.4], [42, 2, 0, 2.6]])
	B.wall_openings(self, Vector3(a.x, Y, a.z), Vector3(a.x, Y, b.z), h, 0.8, con, [])
	B.wall_openings(self, Vector3(b.x, Y, a.z), Vector3(b.x, Y, b.z), h, 0.8, con, [])
	B.box(self, Vector3(44, 0.5, 32), Vector3(10, Y + h + 0.25, 676), con)
	# Rows of racks glowing blue
	var rack := M.get_mat("gear")
	var blue := M.emissive(Color(0.15, 0.45, 1.0), 3.0)
	for rx in [-8.0, -4.0, 0.0, 4.0, 18.0, 22.0, 26.0]:
		var rz := 664.0
		while rz < 688.0:
			if rng.randf() < 0.85:
				B.box(self, Vector3(1.0, 2.3, 2.6), Vector3(rx, Y + 1.15, rz), rack)
				for side in [-0.51, 0.51]:
					B.box(self, Vector3(0.02, 1.8, 0.06), Vector3(rx + side, Y + 1.2, rz - 0.6), blue, false)
					B.box(self, Vector3(0.02, 1.8, 0.06), Vector3(rx + side, Y + 1.2, rz + 0.6), blue, false)
			rz += 3.2
		B.omni(self, Vector3(rx, Y + 2.8, 676), Color(0.2, 0.45, 1.0), 1.4, 9.0)
	for lz in [666.0, 676.0, 686.0]:
		_fluoro(Vector3(10, Y + 7.2, lz), 0.8, 12.0)
	B.label3d(self, "DATA CORE", Vector3(10, Y + 5.5, 660.5), 72, Color(0.4, 0.7, 1.0))
	# Stairs up to the command center door (west side)
	B.stairs(self, Vector3(-9, Y, 676.5), Vector3(-9, CMD_FLOOR, 689.0), 2.2, con)
	B.box(self, Vector3(4, 0.4, 3.2), Vector3(-9, CMD_FLOOR - 0.2, 690.4), con)
	B.box(self, Vector3(0.1, 1.0, 13), Vector3(-7.85, CMD_FLOOR + 0.5 - 1.5, 683), M.get_mat("metal"), false)


# ------------------------------------------------------------------ command center

func _build_command_center() -> void:
	var con := M.get_mat("concrete")
	# Raised floor
	B.box(self, Vector3(44, 3.0, 14), Vector3(10, Y + 1.5, 699), con)
	# South wall: ballistic glass viewing window over the server room + the breach door
	var glass := M.tinted("glass", Color(0.45, 0.6, 0.65, 0.35))
	B.wall_openings(self, Vector3(-12, CMD_FLOOR, 692), Vector3(32, CMD_FLOOR, 692), 5.0, 0.5, con, [[2, 2, 0, 2.5], [8, 22, 0.9, 3.6]])
	B.box(self, Vector3(22, 2.7, 0.2), Vector3(9, CMD_FLOOR + 2.25, 692), glass)
	# Breach door (steel)
	breach_door = StaticBody3D.new()
	breach_door.position = Vector3(-9, CMD_FLOOR, 692)
	add_child(breach_door)
	var dm := BoxMesh.new()
	dm.size = Vector3(2.0, 2.5, 0.2)
	B.mesh(breach_door, dm, Vector3(0, 1.25, 0), M.tinted("metal", Color(0.3, 0.3, 0.28)))
	var ds := BoxShape3D.new()
	ds.size = Vector3(2.0, 2.5, 0.3)
	B.add_shape(breach_door, ds, Vector3(0, 1.25, 0))
	B.label3d(self, "COMMAND  -  AUTHORIZED ONLY", Vector3(-9, CMD_FLOOR + 2.9, 691.6), 28, Color(0.9, 0.2, 0.15), Vector3(0, 180, 0))
	# Consoles and the big map screen
	for cx in [-2.0, 4.0, 10.0, 16.0, 22.0]:
		B.box(self, Vector3(3.5, 1.0, 1.0), Vector3(cx, CMD_FLOOR + 0.5, 696), M.get_mat("gear"))
		B.box(self, Vector3(3.2, 0.5, 0.05), Vector3(cx, CMD_FLOOR + 1.3, 696.3), M.emissive(Color(0.9, 0.5, 0.15), 1.2), false)
	B.box(self, Vector3(14, 4.5, 0.2), Vector3(10, CMD_FLOOR + 3.2, 705.6), M.emissive(Color(0.15, 0.35, 0.3), 1.2), false)
	B.label3d(self, "HORIZON PROTOCOL  //  LAUNCH AUTHORITY: RASKOV", Vector3(10, CMD_FLOOR + 3.4, 705.4), 44, Color(0.6, 1.0, 0.8), Vector3(0, 180, 0))
	B.omni(self, Vector3(10, CMD_FLOOR + 4, 699), Color(1.0, 0.8, 0.6), 1.2, 16.0)
	B.box(self, Vector3(44, 0.4, 14), Vector3(10, CMD_FLOOR + 5.4, 699), con, false)


func blow_breach_door() -> void:
	S.play3d(self, "explosion", breach_door.global_position, 10.0)
	var l := B.omni(self, breach_door.global_position + Vector3(0, 1.5, -1), Color(1, 0.6, 0.3), 14.0, 20.0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.8)
	for c in breach_door.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	var tw2 := create_tween()
	tw2.tween_property(breach_door, "position", breach_door.position + Vector3(0.5, 0.2, 5.0), 0.35)
	tw2.parallel().tween_property(breach_door, "rotation_degrees", Vector3(-85, 20, 0), 0.35)


# ------------------------------------------------------------------ vault

func _build_vault() -> void:
	var con := M.get_mat("concrete")
	B.wall_openings(self, Vector3(-12, CMD_FLOOR, 706), Vector3(32, CMD_FLOOR, 706), 5.0, 1.0, con, [[20, 4, 0, 3.4]])
	B.wall_openings(self, Vector3(4, CMD_FLOOR, 706), Vector3(4, CMD_FLOOR, 718), 5.0, 1.0, con, [])
	B.wall_openings(self, Vector3(16, CMD_FLOOR, 706), Vector3(16, CMD_FLOOR, 718), 5.0, 1.0, con, [])
	B.wall_openings(self, Vector3(4, CMD_FLOOR, 718), Vector3(16, CMD_FLOOR, 718), 5.0, 1.0, con, [])
	B.box(self, Vector3(12, 3.0, 12), Vector3(10, Y + 1.5, 712), con)
	B.box(self, Vector3(12, 0.4, 12), Vector3(10, CMD_FLOOR + 5.2, 712), con, false)
	vault_door = StaticBody3D.new()
	vault_door.position = Vector3(10, CMD_FLOOR + 1.7, 706)
	add_child(vault_door)
	var cm := CylinderMesh.new()
	cm.top_radius = 1.9
	cm.bottom_radius = 1.9
	cm.height = 0.6
	B.mesh(vault_door, cm, Vector3.ZERO, M.get_mat("metal"), Vector3(90, 0, 0))
	var hub := CylinderMesh.new()
	hub.top_radius = 0.4
	hub.bottom_radius = 0.4
	hub.height = 0.8
	B.mesh(vault_door, hub, Vector3(0, 0, -0.1), M.get_mat("rust"), Vector3(90, 0, 0))
	var vs := BoxShape3D.new()
	vs.size = Vector3(4, 3.4, 0.6)
	B.add_shape(vault_door, vs, Vector3.ZERO)
	# The Horizon Protocol drive on a pedestal
	B.box(self, Vector3(0.8, 1.0, 0.8), Vector3(10, CMD_FLOOR + 0.5, 712), M.get_mat("gear"))
	drive = Node3D.new()
	drive.position = DRIVE_POS
	add_child(drive)
	var dmb := BoxMesh.new()
	dmb.size = Vector3(0.35, 0.12, 0.22)
	B.mesh(drive, dmb, Vector3.ZERO, M.emissive(Color(0.3, 0.9, 1.0), 3.0))
	B.omni(drive, Vector3(0, 0.3, 0), Color(0.3, 0.9, 1.0), 1.5, 5.0)


func open_vault() -> void:
	S.play3d(self, "door", vault_door.global_position, 6.0)
	for c in vault_door.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	var tw := create_tween()
	tw.tween_property(vault_door, "rotation_degrees:y", -100.0, 3.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(vault_door, "position:x", 8.0, 3.0)


var heli: Node3D
var _rotor: Node3D
var _tail_rotor: Node3D


func spawn_helicopter() -> void:
	heli = Node3D.new()
	heli.name = "Nightingale"
	add_child(heli)
	var paint := M.tinted("metal", Color(0.3, 0.34, 0.3))
	var glass := M.tinted("glass", Color(0.3, 0.4, 0.45, 0.5))
	var hull := MD.place(heli, "helicopter", Vector3.ZERO, Vector3.ZERO, Vector3.ONE, Color(0.28, 0.32, 0.27))
	if hull:
		_heli_rotors(true)
		return
	B.mesh(heli, _bm(Vector3(2.4, 2.2, 7.0)), Vector3(0, 1.6, 0), paint)
	B.mesh(heli, _bm(Vector3(2.2, 1.4, 1.6)), Vector3(0, 1.9, -4.0), glass)
	B.mesh(heli, _bm(Vector3(0.5, 0.6, 7.5)), Vector3(0, 2.2, 6.8), paint)
	B.mesh(heli, _bm(Vector3(0.12, 1.8, 1.2)), Vector3(0, 3.0, 10.3), paint)
	for side in [-1.2, 1.2]:
		B.mesh(heli, _bm(Vector3(0.12, 0.12, 5.0)), Vector3(side, 0.15, -0.5), M.get_mat("gun_metal"))
		B.mesh(heli, _bm(Vector3(0.1, 0.5, 0.1)), Vector3(side, 0.4, -2.0), M.get_mat("gun_metal"))
		B.mesh(heli, _bm(Vector3(0.1, 0.5, 0.1)), Vector3(side, 0.4, 1.0), M.get_mat("gun_metal"))
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 3.1, 0)
	heli.add_child(_rotor)
	for k in 4:
		var blade := B.mesh(_rotor, _bm(Vector3(0.35, 0.05, 7.5)), Vector3.ZERO, M.get_mat("gun_metal"))
		blade.rotation.y = k * PI / 2.0
		blade.position = Vector3(sin(k * PI / 2.0), 0, cos(k * PI / 2.0)) * 3.75
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.2, 3.0, 10.4)
	heli.add_child(_tail_rotor)
	for k in 2:
		var tb := B.mesh(_tail_rotor, _bm(Vector3(0.05, 1.8, 0.2)), Vector3.ZERO, M.get_mat("gun_metal"))
		tb.rotation.x = k * PI / 2.0
	var search := B.spot(heli, Vector3(0, 0.5, -3.5), Vector3(-60, 0, 0), Color(1, 0.97, 0.9), 12.0, 50.0, 18.0, true)
	search.light_volumetric_fog_energy = 3.0
	B.omni(heli, Vector3(0, 0.3, 3), Color(1, 0.1, 0.1), 1.0, 5.0)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = S.get_stream("engine")
	snd.pitch_scale = 1.8
	snd.volume_db = 6.0
	snd.unit_size = 20.0
	snd.max_distance = 200.0
	heli.add_child(snd)
	snd.play()
	var wind := AudioStreamPlayer3D.new()
	wind.stream = S.get_stream("wind")
	wind.pitch_scale = 3.0
	wind.volume_db = 4.0
	wind.unit_size = 15.0
	heli.add_child(wind)
	wind.play()
	# Fly in over the pass and settle just outside the gate
	heli.position = Vector3(40, Y + 40, 540)
	heli.rotation.y = PI * 0.8
	var tw := create_tween()
	tw.tween_property(heli, "position", Vector3(10, Y + 6.0, 592), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(heli, "rotation:y", PI, 6.0)
	tw.tween_property(heli, "position", Vector3(10, Y + 0.2, 594), 3.0).set_trans(Tween.TRANS_SINE)


func _heli_rotors(model: bool) -> void:
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 3.95, -0.3) if model else Vector3(0, 3.1, 0)
	heli.add_child(_rotor)
	for k in 4:
		var blade := B.mesh(_rotor, _bm(Vector3(0.35, 0.05, 7.5)), Vector3.ZERO, M.get_mat("gun_metal"))
		blade.rotation.y = k * PI / 2.0
		blade.position = Vector3(sin(k * PI / 2.0), 0, cos(k * PI / 2.0)) * 3.75
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.2, 3.0, 8.7) if model else Vector3(0.2, 3.0, 10.4)
	heli.add_child(_tail_rotor)
	for k in 2:
		var tb := B.mesh(_tail_rotor, _bm(Vector3(0.05, 1.8, 0.2)), Vector3.ZERO, M.get_mat("gun_metal"))
		tb.rotation.x = k * PI / 2.0
	var search := B.spot(heli, Vector3(0, 0.6, -3.5), Vector3(-60, 0, 0), Color(1, 0.97, 0.9), 12.0, 50.0, 18.0, true)
	search.light_volumetric_fog_energy = 3.0
	B.omni(heli, Vector3(0, 0.3, 3), Color(1, 0.1, 0.1), 1.0, 5.0)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = S.get_stream("engine")
	snd.pitch_scale = 1.8
	snd.volume_db = 6.0
	snd.unit_size = 20.0
	snd.max_distance = 200.0
	heli.add_child(snd)
	snd.play()
	var wind := AudioStreamPlayer3D.new()
	wind.stream = S.get_stream("wind")
	wind.pitch_scale = 3.0
	wind.volume_db = 4.0
	wind.unit_size = 15.0
	heli.add_child(wind)
	wind.play()
	heli.position = Vector3(40, Y + 40, 540)
	heli.rotation.y = PI * 0.8
	var tw := create_tween()
	tw.tween_property(heli, "position", Vector3(10, Y + 6.0, 592), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(heli, "rotation:y", PI, 6.0)
	tw.tween_property(heli, "position", Vector3(10, Y + 0.2, 594), 3.0).set_trans(Tween.TRANS_SINE)


func _bm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _physics_process(delta: float) -> void:
	if drive:
		drive.rotation.y += 0.02
	if _rotor:
		_rotor.rotation.y += delta * 28.0
		_tail_rotor.rotation.x += delta * 40.0
