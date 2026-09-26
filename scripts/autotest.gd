extends Node
## Self-test: runs only when res://autotest.on exists.
## Presses keys through Godot's real input pipeline and logs what happened
## to res://autotest_log.txt, then quits.

var level
var player
var log_lines := PackedStringArray()
var t := 0.0
var step := 0
var mark := Vector3.ZERO
var real_key_events := 0

func _log(s: String) -> void:
	log_lines.append("[%.2f] %s" % [t, s])
	print("AUTOTEST ", s)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		real_key_events += 1

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _physics_process(delta: float) -> void:
	t += delta
	player = level.player
	match step:
		0:
			if t > 1.0:
				_log("start pos=%s stance=%s floor=%s focused=%s mouse_mode=%s" % [player.global_position, player.stance, player.is_on_floor(), DisplayServer.window_is_focused(), Input.mouse_mode])
				mark = player.global_position
				_key(KEY_W, true)
				step = 1
		1:
			if t > 3.0:
				_key(KEY_W, false)
				_log("PRONE crawl W 2s: moved %.2f m" % Vector2(player.global_position.x - mark.x, player.global_position.z - mark.z).length())
				_key(KEY_SPACE, true)
				step = 2
		2:
			if t > 3.2:
				_key(KEY_SPACE, false)
				_log("after SPACE stance=%s (0=stand)" % player.stance)
				mark = player.global_position
				_key(KEY_W, true)
				step = 3
		3:
			if t > 12.0:
				_key(KEY_W, false)
				_log("STAND walk W 2s: moved %.2f m" % Vector2(player.global_position.x - mark.x, player.global_position.z - mark.z).length())
				mark = player.global_position
				_key(KEY_SHIFT, true)
				_key(KEY_W, true)
				step = 4
		4:
			if t > 14.0:
				_key(KEY_W, false)
				_key(KEY_SHIFT, false)
				_log("breached=%s objective=%s" % [level._breached, level.hud_objective.text])
				_log("SPRINT W 2s: moved %.2f m" % Vector2(player.global_position.x - mark.x, player.global_position.z - mark.z).length())
				var yaw: float = player.rotation.y
				var mm := InputEventMouseMotion.new()
				mm.relative = Vector2(200, 0)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				Input.parse_input_event(mm)
				await get_tree().physics_frame
				_log("mouse look: yaw changed %.2f rad (mouse_mode=%s)" % [absf(player.rotation.y - yaw), Input.mouse_mode])
				_log("real (OS) key events seen: %d" % real_key_events)
				step = 5
		5:
			var f := FileAccess.open("res://autotest_log.txt", FileAccess.WRITE)
			if f:
				f.store_string("\n".join(log_lines) + "\n")
				f.close()
			step = 6
			get_tree().quit()
