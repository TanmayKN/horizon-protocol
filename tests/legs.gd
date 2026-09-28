extends SceneTree
var game
var n := 0
var e
func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	if n == 10:
		var base: Vector3 = p.global_position + Vector3(0, 0, 8)
		e = game.spawn_enemy(base, [base, base + Vector3(10, 0, 0)], false, false, 0.0, "Walker")
		print("thigh_l=", e.leg_l, " children=", e.leg_l.get_children() if e.leg_l else [])
		var t: Node3D = e.leg_l
		while t and t != e:
			print("  parent chain: ", t.name, " ", t.get_class())
			t = t.get_parent()
	if n > 10 and n % 30 == 0 and n < 400:
		print("vel=", Vector2(e.velocity.x, e.velocity.z).length(), " thigh_rot=", e.leg_l.rotation.x, " state=", e.state)
	if n == 400:
		quit()
	return false
