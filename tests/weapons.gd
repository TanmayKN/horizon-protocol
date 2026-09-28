extends SceneTree
## Weapon system test: kill a soldier, pick up his AK, fire it, switch to pistol & knife, knife a second soldier.

var game
var n := 0
var e1
var e2
var ok := true


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		ok = false


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func mouse(pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	Input.parse_input_event(mb)


func _process(_d: float) -> bool:
	n += 1
	var p = game.player
	var w = p.weapon
	if n == 5:
		game.god_mode = true
		p.global_position = Vector3(0, 6, -52)
	if n == 20:
		var fwd: Vector3 = -p.global_transform.basis.z
		e1 = game.spawn_enemy(p.global_position + fwd * 3.0, [], false, true, p.rotation.y + PI, "Test1")
		e1.set_physics_process(false)
	if n == 25:
		check(w.id() == "carbine", "start with carbine, reserve 5.56=%d" % w.reserves["5.56"])
		e1.take_hit(999.0, e1.global_position + Vector3(0, 1.2, 0), Vector3.FORWARD)
	if n == 30:
		check(game.weapon_drops.size() == 1, "enemy dropped a gun (%d drops)" % game.weapon_drops.size())
		if game.weapon_drops.size() > 0:
			var dr: Node3D = game.weapon_drops[0]
			check(dr.get_meta("gun_id") == "ak", "drop is an AK")
			p.global_position = dr.global_position + Vector3(0, 0.2, 0)
	if n == 36:
		key(KEY_F, true)
	if n == 38:
		key(KEY_F, false)
	if n == 45:
		check(w.id() == "ak", "picked up AK (holding %s)" % w.id())
		check(w.current == 3 and w.slot_of("carbine") == 0, "AK went into free slot 4, carbine kept in slot 1")
		var r0: int = w.ammo
		set_meta("r0", r0)
	if n == 200:
		mouse(true)
	if n == 230:
		print("DBG fire=", Input.is_action_pressed("fire"), " ctrl=", p.controls_enabled, " sprint=", p.sprinting, " swap=", w._swap_t, " cd=", w._cooldown, " reload=", w.reloading, " driving=", p.driving, " dead=", p.is_dead)
	if n == 260:
		mouse(false)
	if n == 270:
		check(w.ammo < int(get_meta("r0")), "AK fired (%d -> %d)" % [get_meta("r0"), w.ammo])
		key(KEY_2, true)
	if n == 272:
		key(KEY_2, false)
	if n == 400:
		check(w.id() == "pistol", "switched to pistol")
		key(KEY_3, true)
	if n == 402:
		key(KEY_3, false)
	if n == 520:
		check(w.id() == "knife", "switched to knife")
		var fwd: Vector3 = -p.global_transform.basis.z
		e2 = game.spawn_enemy(p.global_position + fwd * 1.3, [], false, true, p.rotation.y + PI, "Test2")
		e2.set_physics_process(false)
	if n == 600:
		mouse(true)
	if n == 602:
		mouse(false)
	if n == 700:
		check(e2.dead(), "knifed the second soldier")
		print("RESERVES ", w.reserves, " slots ", w.slots)
		print("RESULT ", "OK" if ok else "FAILED")
		quit()
	return false
