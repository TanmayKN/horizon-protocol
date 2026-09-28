extends SceneTree
## Bot plays segment 1: crawl to the fence, cut it, shoot the tower sniper, walk down to the yard.
var game
var n := 0
var phase := "walk1"
var wp_i := 0
var last_pos := Vector3.ZERO
var t := 0
const WALK1 := [Vector3(0, 0, -31.6)]
const WALK2 := [Vector3(0, 0, -26), Vector3(6, 0, -10), Vector3(12, 0, 5), Vector3(18.5, 0, 10), Vector3(18.5, 0, 40)]

func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func mouse(button: MouseButton, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	mb.pressed = pressed
	Input.parse_input_event(mb)

func follow(p, wps: Array) -> bool:
	var tg: Vector3 = wps[wp_i]
	var d := Vector2(tg.x - p.global_position.x, tg.z - p.global_position.z)
	p.rotation.y = atan2(-d.x, -d.y)
	if d.length() < 0.5:
		print("  ", phase, " wp ", wp_i, " ", p.global_position.snapped(Vector3.ONE * 0.01), " step=", game.mission.step)
		wp_i += 1
		if wp_i >= wps.size():
			return true
	if n % 120 == 0:
		if p.global_position.distance_to(last_pos) < 0.15:
			print("STUCK ", phase, " wp ", wp_i, " at ", p.global_position, " step=", game.mission.step)
			quit()
		last_pos = p.global_position
	return false

func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 5:
		game.god_mode = true
		p.stance = 1
		p._apply_stance(true)
	if n == 10:
		key(KEY_W, true)
	if n < 10:
		return false
	match phase:
		"walk1":
			if follow(p, WALK1):
				key(KEY_W, false)
				key(KEY_F, true)
				phase = "cut"
		"cut":
			t += 1
			if game.mission.step == "s1_sniper":
				key(KEY_F, false)
				print("  fence cut after ", t, " frames")
				phase = "shoot"
				t = 0
			elif t > 3000:
				print("FAILED cutting: prompt=", game.hud._prompt.text, " step=", game.mission.step)
				quit()
		"shoot":
			t += 1
			var s = game.seg1.sniper
			var target: Vector3 = s.eye() + Vector3(0, -0.4, 0)
			var dv: Vector3 = target - p.camera.global_position
			p.rotation.y = atan2(-dv.x, -dv.z)
			p.head.rotation.x = atan2(dv.y, Vector2(dv.x, dv.z).length())
			if t == 20:
				mouse(MOUSE_BUTTON_RIGHT, true)
			if t > 60:
				mouse(MOUSE_BUTTON_LEFT, (t % 20) < 3)
			if s.dead() or game.mission.step != "s1_sniper":
				mouse(MOUSE_BUTTON_LEFT, false)
				mouse(MOUSE_BUTTON_RIGHT, false)
				print("  sniper down after ", t, " frames, shots=", game.shots_fired, " step=", game.mission.step)
				phase = "walk2"
				wp_i = 0
				p.head.rotation.x = 0.0
				key(KEY_W, true)
			elif t > 4000:
				print("FAILED shooting sniper, ammo=", p.weapon.ammo, " step=", game.mission.step)
				quit()
		"walk2":
			if follow(p, WALK2) or game.mission.step == "s2_enter":
				print("RESULT step=", game.mission.step, " hp=", p.health)
				quit()
	if n > 20000:
		print("TIMEOUT ", phase)
		quit()
	return false
