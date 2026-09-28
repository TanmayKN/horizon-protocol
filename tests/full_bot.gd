extends SceneTree
## Plays the WHOLE game start to finish with real movement and key presses (god mode, enemies are
## removed as they appear except the tower sniper, who gets shot for real).
## godot --headless --path . -s tests/full_bot.gd -- seed=3

var game
var n := 0
var ai := 0
var last_pos := Vector3.ZERO
var stuck_frames := 0
var t := 0
var log_step := ""

const Y5 := 0.0   # heights are ignored (only x/z used)
var ACTIONS := [
	["go", Vector3(0, 0, -31.6)], ["hold", "s1_cut"], ["shoot_sniper"],
	["go", Vector3(0, 0, -26)], ["go", Vector3(6, 0, -10)], ["go", Vector3(12, 0, 5)], ["go", Vector3(18.5, 0, 10)], ["go", Vector3(18.5, 0, 40)],
	["go", Vector3(15, 0, 60)], ["go", Vector3(15, 0, 103)], ["go", Vector3(30, 0, 105)], ["go", Vector3(35, 0, 105)], ["go", Vector3(39, 0, 105)],
	["go", Vector3(49.5, 0, 105)], ["go", Vector3(50.5, 0, 114.8)], ["go", Vector3(48.1, 0, 114.9)], ["go", Vector3(48.1, 0, 110.0)], ["go", Vector3(47.2, 0, 107.8)],
	["go", Vector3(46.25, 0, 109.7)], ["go", Vector3(46.25, 0, 115.2)], ["go", Vector3(48.1, 0, 115.2)], ["go", Vector3(48.1, 0, 110.0)],
	["go", Vector3(47.2, 0, 107.8)], ["go", Vector3(46.25, 0, 109.7)], ["go", Vector3(46.25, 0, 115.2)], ["go", Vector3(44.4, 0, 115.3)],
	["go", Vector3(42.5, 0, 110.0)], ["go", Vector3(42.5, 0, 103.5)], ["go", Vector3(47.5, 0, 103.5)], ["go", Vector3(49.9, 0, 103.6)], ["hold", "s2_download"],
	["wait_not", "s3_blackout"],
	["go", Vector3(47.5, 0, 103.5)], ["go", Vector3(42.5, 0, 103.5)], ["go", Vector3(42.5, 0, 110.0)], ["go", Vector3(44.4, 0, 115.3)], ["go", Vector3(46.25, 0, 115.2)],
	["go", Vector3(46.25, 0, 109.7)], ["go", Vector3(47.2, 0, 107.8)], ["go", Vector3(48.1, 0, 110.0)], ["go", Vector3(48.1, 0, 115.2)], ["go", Vector3(44.4, 0, 115.3)],
	["go", Vector3(42.0, 0, 112.0)], ["go", Vector3(40.0, 0, 111.5)], ["go", Vector3(37.4, 0, 111.5)], ["wait_step", "s3_window"], ["tap", "s3_window"],
	["drive"],
	["go", Vector3(4.0, 0, 622)], ["go", Vector3(1.6, 0, 624)], ["go", Vector3(1.6, 0, 630.9)], ["go", Vector3(10, 0, 630.9)], ["go", Vector3(10, 0, 634)],
	["go", Vector3(10, 0, 658)], ["go", Vector3(10, 0, 662.2)], ["go", Vector3(-9, 0, 662.2)], ["go", Vector3(-9, 0, 676.0)], ["go", Vector3(-9, 0, 689.2)],
	["go", Vector3(-9, 0, 691.0)], ["hold", "s5_breach"], ["wait_not", "s5_raskov"],
	["go", Vector3(-9, 0, 694.5)], ["go", Vector3(10, 0, 700)], ["go", Vector3(10, 0, 704.4)], ["hold", "s5_vault"],
	["go", Vector3(10, 0, 708)], ["go", Vector3(10, 0, 710.8)], ["tap", "s5_drive"],
	["go", Vector3(10, 0, 704.4)], ["go", Vector3(10, 0, 700)], ["go", Vector3(-9, 0, 694.5)], ["go", Vector3(-9, 0, 690.5)], ["go", Vector3(-9, 0, 676.0)],
	["go", Vector3(-9, 0, 662.2)], ["go", Vector3(10, 0, 662.2)], ["go", Vector3(10, 0, 634)], ["go", Vector3(10, 0, 630.9)], ["go", Vector3(1.6, 0, 630.9)],
	["go", Vector3(1.6, 0, 624)], ["go", Vector3(3.6, 0, 622.8)], ["wait_step", "s6_infil"],
	# SEGMENT 6: Vostok airfield
	["go", Vector3(-75, 0, 1025)], ["go", Vector3(-84, 0, 1060)], ["go", Vector3(-84, 0, 1074)], ["go", Vector3(-101, 0, 1076)], ["go", Vector3(-101, 0, 1086)],
	["wait_step", "s6_tower"], ["go", Vector3(-40, 0, 1090)], ["go", Vector3(80, 0, 1090)], ["go", Vector3(105.6, 0, 1087)],
	["go", Vector3(105.6, 0, 1099.6)], ["go", Vector3(107.4, 0, 1099.9)], ["go", Vector3(107.4, 0, 1091.4)], ["go", Vector3(105.6, 0, 1091.2)],
	["go", Vector3(105.6, 0, 1099.6)], ["go", Vector3(104.6, 0, 1099.0)], ["go", Vector3(102.5, 0, 1099.0)], ["go", Vector3(101.5, 0, 1097.5)], ["hold", "s6_tower"],
	["go", Vector3(102.5, 0, 1099.0)], ["go", Vector3(104.8, 0, 1099.3)], ["go", Vector3(105.6, 0, 1099.9)], ["go", Vector3(105.6, 0, 1091.2)], ["go", Vector3(107.4, 0, 1091.2)],
	["go", Vector3(107.4, 0, 1099.9)], ["go", Vector3(105.6, 0, 1099.9)], ["go", Vector3(105.6, 0, 1087)], ["go", Vector3(80, 0, 1095)],
	["go", Vector3(-40, 0, 1095)], ["go", Vector3(-60, 0, 1100)], ["go", Vector3(-60, 0, 1107)], ["go", Vector3(-60, 0, 1110.5)], ["go", Vector3(-64.8, 0, 1109)],
	["hold_door"], ["go", Vector3(-68, 0, 1108.9)], ["go", Vector3(-70.3, 0, 1108.4)], ["hold", "s6_reyes"], ["wait_step", "s6_hale"], ["wait_step", "s6_end"], ["done"],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed(int(a.split("=")[1]))
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


func fail(msg: String) -> void:
	print("FAIL ", msg, "  action=", ai, " ", ACTIONS[ai], " step=", game.mission.step, " pos=", game.player.global_position, " prompt='", game.hud._prompt.text, "'")
	quit(1)


func next() -> void:
	ai += 1
	t = 0
	stuck_frames = 0


func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	var m = game.mission
	if n == 5:
		game.god_mode = true
		p.stance = 1
		p._apply_stance(true)
	if n < 10:
		return false
	if m.step != log_step:
		log_step = m.step
		print("  [", n, "] step -> ", m.step, "   hp=", int(p.health), " kills=", game.kills)
	# Clear enemies (keep the tower sniper alive until the bot shoots him)
	for e in game.alive_enemies():
		if e == game.seg1.sniper and m.step.begins_with("s1"):
			continue
		e.take_hit(999.0, e.global_position + Vector3(0, 1, 0), Vector3.FORWARD)
	var a: Array = ACTIONS[ai]
	t += 1
	match a[0]:
		"go":
			key(KEY_W, true)
			if p.stance != 0:
				p.stance = 0
				p._apply_stance(false)
			var tg: Vector3 = a[1]
			var d := Vector2(tg.x - p.global_position.x, tg.z - p.global_position.z)
			p.rotation.y = atan2(-d.x, -d.y)
			p.head.rotation.x = 0.0
			if d.length() < 0.5:
				next()
			else:
				if p.global_position.distance_to(last_pos) < 0.004:
					stuck_frames += 1
				else:
					stuck_frames = 0
				last_pos = p.global_position
				if stuck_frames > 150:
					fail("stuck walking")
		"hold":
			key(KEY_W, false)
			key(KEY_F, true)
			if m.step != a[1]:
				key(KEY_F, false)
				next()
			elif t > 2500:
				fail("holding F did nothing")
		"tap":
			key(KEY_W, false)
			key(KEY_F, (t % 10) < 3)
			if m.step != a[1]:
				key(KEY_F, false)
				next()
			elif t > 2000:
				fail("pressing F did nothing")
		"hold_door":
			key(KEY_W, false)
			key(KEY_F, true)
			if m._door_open:
				key(KEY_F, false)
				next()
			elif t > 2500:
				fail("could not open the door")
		"wait_step":
			key(KEY_W, false)
			if m.step == a[1]:
				next()
			elif t > 4000:
				fail("waited too long")
		"wait_not":
			key(KEY_W, false)
			if m.step != a[1]:
				next()
			elif t > 6000:
				fail("waited too long")
		"shoot_sniper":
			key(KEY_W, false)
			var s = game.seg1.sniper
			var target: Vector3 = s.eye() + Vector3(0, -0.4, 0)
			var dv: Vector3 = target - p.camera.global_position
			p.rotation.y = atan2(-dv.x, -dv.z)
			p.head.rotation.x = atan2(dv.y, Vector2(dv.x, dv.z).length())
			if t == 10:
				mouse(MOUSE_BUTTON_RIGHT, true)
			if t > 50:
				mouse(MOUSE_BUTTON_LEFT, (t % 20) < 3)
			if s.dead():
				mouse(MOUSE_BUTTON_LEFT, false)
				mouse(MOUSE_BUTTON_RIGHT, false)
				print("  sniper shot down with ", game.shots_fired, " shots")
				next()
			elif t > 3000:
				fail("could not shoot the sniper")
		"drive":
			key(KEY_W, false)
			if m._wheel_offered:
				key(KEY_F, true)
				if not has_meta("offered"):
					set_meta("offered", true)
					print("  wheel offered at frame ", n)
			if game.seg4.player_driving:
				if not has_meta("drv"):
					set_meta("drv", true)
					print("  Vance took the wheel at frame ", n)
				key(KEY_F, false)
				key(KEY_W, true)
			if m.step == "s5_enter" or m.step.begins_with("s5"):
				key(KEY_W, false)
				print("  reached the bunker; Vance was driving: ", game.seg4.player_driving)
				next()
			elif t > 30000:
				fail("truck section never finished")
		"done":
			print("RESULT FINISHED  time=", int(game.play_time), "s kills=", game.kills, " intel=", game.intel_found, " hp=", int(p.health))
			quit(0)
	if n > 90000:
		fail("timeout")
	return false
