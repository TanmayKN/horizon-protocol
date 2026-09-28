extends SceneTree
## Walks the player from the admin block ground floor to the top floor along the stairwell.

var game
var n := 0
var wp_i := 0
var stuck_t := 0
var last_pos := Vector3.ZERO
const WPS := [
	Vector3(50.5, 0, 114.8), Vector3(48.1, 0, 114.9), Vector3(48.1, 0, 110.0), Vector3(47.2, 0, 107.8),
	Vector3(46.25, 0, 109.7), Vector3(46.25, 0, 115.2), Vector3(48.1, 0, 115.2), Vector3(48.1, 0, 110.0),
	Vector3(47.2, 0, 107.8), Vector3(46.25, 0, 109.7), Vector3(46.25, 0, 115.2), Vector3(44.4, 0, 115.3), Vector3(42.0, 0, 112.0)]


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game


func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 5:
		game.god_mode = true
		for e in game.alive_enemies():
			e.set_physics_process(false)
			e.global_position += Vector3(0, -200, 0)
		p.global_position = Vector3(50.5, 0.3, 114.8)
		p.stance = 0
		p._apply_stance(true)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if n > 8:
		var t: Vector3 = WPS[wp_i]
		var d := Vector2(t.x - p.global_position.x, t.z - p.global_position.z)
		p.rotation.y = atan2(-d.x, -d.y)
		if d.length() < 0.35:
			print("  reached wp ", wp_i, " at ", p.global_position.snapped(Vector3.ONE * 0.01))
			wp_i += 1
			if wp_i >= WPS.size():
				print("FLOOR ", game.seg2.floor_of(p.global_position), " pos ", p.global_position)
				print("RESULT ", "OK" if game.seg2.floor_of(p.global_position) == 2 else "FAILED")
				quit()
		if n % 60 == 0:
			if p.global_position.distance_to(last_pos) < 0.1:
				print("STUCK at wp ", wp_i, " pos ", p.global_position)
				print("RESULT FAILED")
				quit()
			last_pos = p.global_position
	if n > 6000:
		print("TIMEOUT wp ", wp_i, " pos ", p.global_position)
		quit()
	return false
