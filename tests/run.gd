extends SceneTree
## Test harness: godot --path . -s tests/run.gd -- pos=0,5,-40 yaw=180 frames=120 shots=60,120 out=a skip=2 keys=w:30-90
## Loads the real main scene, optionally teleports/drives the player, saves screenshots to tests/out/.

var game
var n := 0
var args := {}
var shots: Array = []
var skips := 0
var key_plan: Array = []   # [key, start, end]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	if args.has("shots"):
		for s in args.shots.split(","):
			shots.append(int(s))
	skips = int(args.get("skip", "0"))
	if args.has("keys"):
		for k in args["keys"].split(";"):
			var parts: PackedStringArray = k.split(":")
			var rng: PackedStringArray = parts[1].split("-")
			key_plan.append([parts[0], int(rng[0]), int(rng[1])])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/out"))


func _key(name: String, pressed: bool) -> void:
	var codes := {"w": KEY_W, "a": KEY_A, "s": KEY_S, "d": KEY_D, "shift": KEY_SHIFT, "space": KEY_SPACE, "f": KEY_F, "c": KEY_C, "z": KEY_Z, "q": KEY_Q, "e": KEY_E, "r": KEY_R}
	if name == "lmb" or name == "rmb":
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT if name == "lmb" else MOUSE_BUTTON_RIGHT
		mb.pressed = pressed
		Input.parse_input_event(mb)
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = codes[name]
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 3:
		if args.has("god"):
			game.god_mode = true
		for i in skips:
			game.mission.skip()
			game.mission._process(0.016)
	if n == 6 and args.has("gun"):
		var gslot: int = p.weapon.slot_of(args.gun)
		if gslot >= 0:
			p.weapon.switch_to(gslot)
		else:
			p.weapon.take_gun(args.gun, 30)
		p.weapon._swap_t = 0.0
	if n == 6 and args.has("tp"):
		p.third_person = true
		p._tp_blend = 1.0
	if n == 6 and args.has("intel"):
		game.spawn_intel(p.global_position - p.global_transform.basis.z * 1.7 - p.global_transform.basis.x * 0.8 + Vector3(0, 0.25, 0), "Test", "Test")
	if n == 6 and args.has("drop"):
		game.spawn_weapon_drop(args.drop, p.global_position - p.global_transform.basis.z * 1.6, 20)
		game.spawn_ammo(p.global_position - p.global_transform.basis.z * 1.8 + Vector3(0.6, 0, 0), "7.62", 20)
	if n == 5 and args.has("pos"):
		var v: PackedStringArray = args.pos.split(",")
		p.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
		p.stance = 0
		p._apply_stance(true)
	if n >= 5 and n <= 8:
		if args.has("yaw"):
			p.rotation.y = deg_to_rad(float(args.yaw))
		if args.has("pitch"):
			p.head.rotation.x = deg_to_rad(float(args.pitch))
	if args.get("aim", "") == "sniper" and n > 8 and game.seg1.sniper:
		var target: Vector3 = game.seg1.sniper.eye() + Vector3(0, -0.4, 0)
		var d: Vector3 = target - p.camera.global_position
		p.rotation.y = atan2(-d.x, -d.z)
		p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	if args.has("ride") and n == 10:
		game.mission._go("s4_escape")
		game.seg4._leap_t = 0.99
	if args.has("ride") and n == 14:
		var key: String = args.ride
		game.seg4.s = game.seg4.get(key) if key.begins_with("s_") else float(key)
		game.seg4.s += float(args.get("ride_off", "0"))
	if args.has("bunker") and n == 10:
		game.seg4.visible = true
		game.seg5.visible = true
		game.seg4.s = game.seg4.s_end
		game.seg4.truck.visible = true
		game.seg4._place_truck()
		game.mission._go("s5_enter")
	if args.has("bunker") and args.has("pos") and n == 12:
		var v: PackedStringArray = args.pos.split(",")
		p.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if args.has("goto") and n == 10:
		for st in args.goto.split(","):
			game.mission._go(st)
	if args.has("goto") and args.has("pos") and n == 12:
		var v: PackedStringArray = args.pos.split(",")
		p.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if args.has("freeze") and n > 12:
		for e in game.alive_enemies():
			e.set_physics_process(false)
	if args.has("goto") and args.has("yaw") and n >= 12 and n <= 14:
		p.rotation.y = deg_to_rad(float(args.yaw))
	if args.has("heli") and n == 10:
		game.seg4.s = game.seg4.s_end
		game.seg4.truck.visible = true
		game.seg4._place_truck()
		game.seg5.visible = true
		game.seg4.visible = true
		game.set_atmosphere("mountain")
		game.seg5.spawn_helicopter()
		game.seg5.heli.position = Vector3(10, 25, 594)
		p.global_position = Vector3(12, 19.3, 612)
		p.rotation.y = 0.0
		p.stance = 0
		p._apply_stance(true)
	if args.has("dummy") and n == 14:
		var fwd: Vector3 = -p.global_transform.basis.z
		var e = game.spawn_enemy(p.global_position + fwd * 3.0, [], false, true, p.rotation.y + PI, args.get("dummy_name", "Tango"))
		e.set_physics_process(false)
		e.velocity = Vector3(0, 0, 1.5)
		e._animate(0.3)
	if args.has("look_truck") and n >= 13 and n <= 16:
		game.seg4.visible = true
		game.seg4.truck.visible = true
		var t: Node3D = game.seg4.truck
		var off: PackedStringArray = args.look_truck.split(",")
		var eye: Vector3 = t.global_transform * Vector3(float(off[0]), float(off[1]), float(off[2]))
		p.global_position = eye
		var d: Vector3 = t.global_position + Vector3(0, 1.5, 0) - p.camera.global_position
		p.rotation.y = atan2(-d.x, -d.z)
		p.head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
		p.velocity = Vector3.ZERO
	if args.has("drive") and n == 16:
		game.seg4.start_player_drive()
	if args.has("autoskip") and n > 10 and n % int(args.autoskip) == 0:
		print("  [", n, "] step=", game.mission.step, " -> skip")
		game.mission.skip()
	for k in key_plan:
		if n == k[1]:
			_key(k[0], true)
		if n == k[2]:
			_key(k[0], false)
	if n in shots:
		var img := root.get_viewport().get_texture().get_image()
		var path := "res://tests/out/%s_%d.png" % [args.get("out", "shot"), n]
		img.save_png(path)
		print("PERF draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		print("SHOT ", path, " pos=", p.global_position, " step=", game.mission.step, " hp=", p.health, " alive=", game.alive_enemies().size())
	if n >= int(args.get("frames", "60")):
		print("END pos=", p.global_position, " step=", game.mission.step, " hp=", p.health, " alive=", game.alive_enemies().size(), " fps=", Engine.get_frames_per_second())
		quit()
	return false
