extends SceneTree
## Enemy tactics check on the airfield apron: do they take cover, peek, flank and throw grenades?
## godot --headless --path . -s tests/ai.gd -- t=1

var game
var n := 0
var t := 0.0
var enemies: Array = []
var covered := {}
var crouched := {}
var grenades := 0
var flanks := 0
var shots_at_player := 0
var hp_lost := 0.0


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game


func _process(delta: float) -> bool:
	n += 1
	if n < 5:
		return false
	t += delta
	var p = game.player
	if n == 5:
		for e in game.alive_enemies():
			e.set_physics_process(false)
			e.global_position += Vector3(0, -300, 0)
		game.seg6.visible = true
		p.global_position = Vector3(0, 0.3, 1138.5)
		p.rotation.y = PI       # face north toward the jet
		for pos in [Vector3(-12, 0.3, 1165), Vector3(-2, 0.3, 1170), Vector3(8, 0.3, 1168), Vector3(18, 0.3, 1163)]:
			var e = game.spawn_enemy(pos, [], false, false, 0.0, "Merc")
			e.alert(p.global_position)
			enemies.append(e)
	if n > 5:
		# the player hides behind the sandbags half the time (so they lose sight and throw grenades)
		p.stance = 1 if fmod(t, 8.0) > 3.0 else 0
		p._apply_stance(false)
		if p.health < 100.0:
			hp_lost += 100.0 - p.health
			p.health = 100.0
		for e in enemies:
			if not is_instance_valid(e) or e.dead():
				continue
			if e._cover != null:
				covered[e] = true
			if e._crouch > 0.8:
				crouched[e] = true
			if e._flank_target != null:
				flanks += 1
		for c in game.get_children():
			if c.get_script() == preload("res://scripts/grenade.gd") and not c.has_meta("counted"):
				c.set_meta("counted", true)
				grenades += 1
	if t > 40.0:
		print("took cover: %d / %d   crouched: %d   grenades: %d   flank frames: %d   damage dealt to Vance: %d" % [covered.size(), enemies.size(), crouched.size(), grenades, flanks, int(hp_lost)])
		var ok := covered.size() >= 2 and crouched.size() >= 1 and hp_lost > 0.0
		print("RESULT ", "OK" if ok else "FAILED")
		quit()
	return false
