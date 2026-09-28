extends SceneTree
## Plays every cutscene for real (no auto-skip) and checks the game hands control back afterwards.
## godot --headless --path . -s tests/cine.gd -- cine

var game
var n := 0
var phase := 0
var t := 0.0
var ok := true
var saw_active := false


func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game


func check(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		ok = false


func wait_cutscene(label: String, limit: float, controls := true) -> bool:
	if game.cutscene_active:
		saw_active = true
	if saw_active and not game.cutscene_active:
		check(true, label + " played and finished (%.1fs)" % t)
		if controls:
			check(game.player.controls_enabled, label + ": controls back")
		check(game.get_viewport().get_camera_3d() == game.player.camera, label + ": player camera active")
		saw_active = false
		return true
	if t > limit:
		check(false, label + " never finished (active=%s)" % game.cutscene_active)
		return true
	return false


func _process(delta: float) -> bool:
	n += 1
	t += delta
	if n < 3:
		return false
	game.god_mode = true
	match phase:
		0:
			if wait_cutscene("intro", 40.0):
				phase = 1
				t = 0.0
				game.mission._go("end")
		1:
			if t > 1.0:
				game.player.global_position = game.seg4.truck.global_position + Vector3(2.5, 0.5, 0)
				for e in game.alive_enemies():
					e.take_hit(9999.0, e.global_position, Vector3.ZERO)
				phase = 2
				t = 0.0
				game.mission._go("e_extract")
		2:
			if wait_cutscene("twist", 80.0, false):
				phase = 3
				t = 0.0
		3:
			if game.mission.step == "s6_infil" or t > 10.0:
				check(game.player.controls_enabled, "controls back at the airfield")
				check(game.mission.step == "s6_infil", "arrived at the airfield (step=%s)" % game.mission.step)
				check(game.player.global_position.z > 990.0, "player is at Vostok (%s)" % game.player.global_position)
				check(game.player.visible, "player visible again")
				check(game.seg6.reyes_actor != null, "Reyes is held in the office")
				for e in game.alive_enemies():
					e.take_hit(9999.0, e.global_position, Vector3.ZERO)
				game.mission._go("s6_reyes")
				game.mission._free_reyes()
				phase = 4
				t = 0.0
		4:
			if wait_cutscene("reyes freed", 40.0):
				phase = 5
				t = 0.0
		5:
			# s6_hale starts its own cutscene
			if game.mission._hale != null:
				check(true, "hale intro done, Hale spawned (%.1fs)" % t)
				check(game.player.controls_enabled, "controls during the boss fight")
				game.mission._hale.take_hit(99999.0, game.mission._hale.eye(), Vector3.ZERO)
				phase = 6
				t = 0.0
		6:
			if wait_cutscene("finale", 60.0, false):
				phase = 7
				t = 0.0
		7:
			if t > 9.0:
				print("RESULT ", "OK" if ok else "FAILED")
				quit()
	return false
