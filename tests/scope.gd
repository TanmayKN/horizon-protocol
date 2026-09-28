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
	if n == 10:
		# kill the tower sniper and walk to his rifle like a player would
		var s = game.seg1.sniper
		print("sniper is_sniper=", s.is_sniper, " weapon=", s.weapon_id())
		s.take_hit(999.0, s.global_position + Vector3(0, 1.2, 0), Vector3.FORWARD)
	if n == 20:
		print("drops=", game.weapon_drops.size())
		for d in game.weapon_drops:
			print("  drop ", d.get_meta("gun_id"), " at ", d.global_position)
		var dr = game.weapon_drops[0]
		p.global_position = dr.global_position + Vector3(0, 0.3, 0)
	if n == 30:
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_F; ev.pressed = true; Input.parse_input_event(ev)
	if n == 32:
		var ev := InputEventKey.new(); ev.physical_keycode = KEY_F; ev.pressed = false; Input.parse_input_event(ev)
	if n == 200:
		print("holding ", p.weapon.id())
		var mb := InputEventMouseButton.new(); mb.button_index = MOUSE_BUTTON_RIGHT; mb.pressed = true; Input.parse_input_event(mb)
	if n == 400:
		print("aiming=", p.aiming, " can_aim=", p.weapon.can_aim(), " blend=", p.weapon._ads_blend, " scoped=", p.weapon.scoped, " fov=", p.camera.fov, " overlay=", game.hud._scope.visible)
		quit()
	return false
