extends SceneTree
var game
var n := 0
func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 5:
		game.god_mode = true
		game.mission._go("s2_download")
		game.mission._go("s3_blackout")
		game.mission._go("s3_down")
		game.mission._go("s3_catwalk")
	if n == 8:
		p.global_position = Vector3(38.0, 3.7, 111.5)
		p.rotation.y = PI * 0.5      # face west (-X), toward the window
		p.stance = 0
		p._apply_stance(true)
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_W; ev.pressed = true; Input.parse_input_event(ev)
	if n > 8:
		for e in game.alive_enemies():
			e.set_physics_process(false)
	if n == 300:
		print("during catwalk fight: x=", snappedf(p.global_position.x, 0.01), " (window at 36.0; blocked = x > 36)  step=", game.mission.step)
		p.global_position = Vector3(30, 1.0, 111)   # pretend the player got outside
	if n == 400:
		print("after being outside: step=", game.mission.step)
		quit()
	return false
