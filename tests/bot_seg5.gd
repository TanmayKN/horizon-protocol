extends SceneTree
## Bot plays segment 5 from the crash to the command-center door.
var game
var n := 0
var wp_i := 0
var last_pos := Vector3.ZERO
const WPS := [Vector3(4.0, 0, 622), Vector3(1.6, 0, 624), Vector3(1.6, 0, 630.9), Vector3(10, 0, 630.9), Vector3(10, 0, 634), Vector3(10, 0, 658),
	Vector3(10, 0, 662.2), Vector3(-9, 0, 662.2), Vector3(-9, 0, 676.0), Vector3(-9, 0, 689.2), Vector3(-9, 0, 691.0),
	Vector3(-9, 0, 691.0), Vector3(-9, 0, 694.5), Vector3(10, 0, 700), Vector3(10, 0, 704.4), Vector3(10, 0, 704.4), Vector3(10, 0, 708), Vector3(10, 0, 710.8), Vector3(10, 0, 710.8)]
# at these waypoints hold F until the mission step changes
const HOLD := {10: "s5_breach", 14: "s5_vault", 17: "s5_drive"}
var hold_n := 0

func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game

func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 5:
		game.god_mode = true
		game.start_segment4()
		game.seg4.s = game.seg4.s_end
		game.seg4.truck.visible = true
		game.seg4._place_truck()
		game.mission._go("s5_enter")
	if n > 8:
		for e in game.alive_enemies():
			e.take_hit(999.0, e.global_position + Vector3(0, 1, 0), Vector3.FORWARD)
	if n == 12:
		print("start ", p.global_position, " truck ", game.seg4.truck.global_position)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		p.stance = 0
		p._apply_stance(true)
	if n > 12:
		var t: Vector3 = WPS[wp_i]
		var d := Vector2(t.x - p.global_position.x, t.z - p.global_position.z)
		p.rotation.y = atan2(-d.x, -d.y)
		if HOLD.has(wp_i) and d.length() < 0.6:
			hold_n += 1
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_F
			ev.pressed = (hold_n % 40) < 36
			Input.parse_input_event(ev)
			if game.mission.step != HOLD[wp_i] and game.mission.step != "s5_raskov":
				print("  held F at wp ", wp_i, " -> step=", game.mission.step)
				wp_i += 1
				hold_n = 0
			elif hold_n > 3000:
				print("HOLD FAILED wp ", wp_i, " step=", game.mission.step, " prompt=", game.hud._prompt.text)
				quit()
			last_pos = Vector3.ZERO
			return false
		if d.length() < 0.45:
			print("  wp ", wp_i, " ", p.global_position.snapped(Vector3.ONE * 0.01), " step=", game.mission.step)
			wp_i += 1
			if wp_i >= WPS.size():
				print("RESULT end, step=", game.mission.step)
				quit()
		if n % 90 == 0:
			if p.global_position.distance_to(last_pos) < 0.15:
				print("STUCK wp ", wp_i, " at ", p.global_position, " step=", game.mission.step)
				quit()
			last_pos = p.global_position
	if n > 8000:
		print("TIMEOUT")
		quit()
	return false
