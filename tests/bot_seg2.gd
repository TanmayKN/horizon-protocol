extends SceneTree
## Bot plays segment 2: walks from the yard road into the admin block, up to the terminal and downloads.
var game
var n := 0
var wp_i := 0
var last_pos := Vector3.ZERO
var holding := false
var hold_t := 0
const WPS2 := [
	Vector3(47.5, 0, 103.5), Vector3(42.5, 0, 103.5), Vector3(42.5, 0, 110.0), Vector3(44.4, 0, 115.3), Vector3(46.25, 0, 115.2),
	Vector3(46.25, 0, 109.7), Vector3(47.2, 0, 107.8), Vector3(48.1, 0, 110.0), Vector3(48.1, 0, 115.2), Vector3(44.4, 0, 115.3),
	Vector3(42.0, 0, 112.0), Vector3(40.0, 0, 111.5), Vector3(37.2, 0, 111.5)]
var phase := 1
const WPS := [
	Vector3(15, 0, 60), Vector3(15, 0, 103), Vector3(30, 0, 105), Vector3(35, 0, 105), Vector3(39, 0, 105),
	Vector3(49.5, 0, 105), Vector3(50.5, 0, 114.8), Vector3(48.1, 0, 114.9), Vector3(48.1, 0, 110.0), Vector3(47.2, 0, 107.8),
	Vector3(46.25, 0, 109.7), Vector3(46.25, 0, 115.2), Vector3(48.1, 0, 115.2), Vector3(48.1, 0, 110.0),
	Vector3(47.2, 0, 107.8), Vector3(46.25, 0, 109.7), Vector3(46.25, 0, 115.2), Vector3(44.4, 0, 115.3),
	Vector3(42.5, 0, 110.0), Vector3(42.5, 0, 103.5), Vector3(47.5, 0, 103.5), Vector3(49.9, 0, 103.6)]

func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 5:
		game.god_mode = true
		game.mission._go("s1_downhill")
	if n == 8:
		p.global_position = Vector3(15, 3, 50)
		p.stance = 0
		p._apply_stance(true)
	if n > 10:
		for e in game.alive_enemies():
			if phase == 2:
				e.take_hit(999.0, e.global_position + Vector3(0, 1, 0), Vector3.FORWARD)
			elif e.global_position.y > -50:
				e.set_physics_process(false)
				e.global_position += Vector3(0, -200, 0)
	if n == 12:
		key(KEY_W, true)
	if phase == 2:
		var t2: Vector3 = WPS2[wp_i]
		var d2 := Vector2(t2.x - p.global_position.x, t2.z - p.global_position.z)
		p.rotation.y = atan2(-d2.x, -d2.y)
		if d2.length() < 0.4:
			print("  s3 wp ", wp_i, " ", p.global_position.snapped(Vector3.ONE * 0.01), " step=", game.mission.step)
			if wp_i < WPS2.size() - 1:
				wp_i += 1
		if n % 90 == 0:
			if p.global_position.distance_to(last_pos) < 0.15 and game.mission.step != "s3_catwalk":
				print("STUCK s3 wp ", wp_i, " at ", p.global_position, " step=", game.mission.step)
				quit()
			last_pos = p.global_position
		if game.mission.step.begins_with("s4"):
			print("RESULT reached ", game.mission.step)
			quit()
		return false
	if n > 12 and not holding:
		var t: Vector3 = WPS[wp_i]
		var d := Vector2(t.x - p.global_position.x, t.z - p.global_position.z)
		p.rotation.y = atan2(-d.x, -d.y)
		if d.length() < 0.4:
			print("  wp ", wp_i, " ", p.global_position.snapped(Vector3.ONE * 0.01), " step=", game.mission.step)
			wp_i += 1
			if wp_i >= WPS.size():
				key(KEY_W, false)
				holding = true
				key(KEY_F, true)
		if n % 90 == 0:
			if p.global_position.distance_to(last_pos) < 0.15:
				print("STUCK wp ", wp_i, " at ", p.global_position, " step=", game.mission.step)
				quit()
			last_pos = p.global_position
	if holding:
		hold_t += 1
		if hold_t % 200 == 0:
			print("  holding F: step=", game.mission.step, " progress=", game.mission._dl_progress, " prompt=", game.hud._prompt.text)
		if game.mission.step != "s2_download" or hold_t > 2500:
			print("download done: step=", game.mission.step)
			key(KEY_F, false)
			holding = false
			phase = 2
			wp_i = 0
			key(KEY_W, true)
	if n > 9000:
		print("TIMEOUT wp ", wp_i, " step=", game.mission.step)
		quit()
	return false
