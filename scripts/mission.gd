extends Node
## Story director for THE HORIZON PROTOCOL.
## The narrative only ever moves forward: no cutscenes, no loading screens.

const S := preload("res://scripts/sfx.gd")

const OVERWATCH := "Overwatch (Sgt. Reyes)"
const VANCE := "Vance"

var game
var step := ""
var _radio_queue: Array = []
var _radio_wait := 0.0
var _cut_progress := 0.0
var _alert_lines := 0
var _kill_lines := 0
var _t := 0.0
var _step_t := 0.0


func _ready() -> void:
	_go("s1_intro")


func _process(delta: float) -> void:
	_t += delta
	_step_t += delta
	_process_radio(delta)
	var p = game.player
	match step:
		"s1_intro":
			if _near(game.seg1.WIRE_POS, 3.2):
				_go("s1_cut")
		"s1_cut":
			_do_cut(delta)
		"s1_sniper":
			if game.seg1.sniper and game.seg1.sniper.dead():
				_go("s1_downhill")
		"s1_downhill":
			if p.global_position.z > game.terrain.YARD_Z + 2.0:
				_go("s2_enter")
		_:
			pass


# ------------------------------------------------------------------ steps

func _go(new_step: String) -> void:
	step = new_step
	_step_t = 0.0
	var hud = game.hud
	var seg1 = game.seg1
	match step:
		"s1_intro":
			_spawn_segment1()
			get_tree().create_timer(1.5).timeout.connect(func():
				hud.title("THE HORIZON PROTOCOL", "Segment 1  —  The Perimeter Breach     |     Timberline Outpost, 04:52"))
			say(OVERWATCH, "Vance, comms check. I have you prone, forty metres off the wire. Stay low.", 2.0)
			say(VANCE, "Copy, Overwatch. Soaked but in position.")
			say(OVERWATCH, "Fence is torn right in front of you. One strand still holds. Cut it and you're in.")
			say(OVERWATCH, "Mind the searchlight on the central tower. If it lights you up, the sniper up there won't miss.")
			say(OVERWATCH, "Controls check: C to crouch, Z to go prone, Q and E to lean. Stay in the dark.", 1.0)
			hud.set_objective("Reach the torn section of the perimeter fence", _marker(seg1.WIRE_POS, 1.0))
		"s1_cut":
			hud.set_objective("Cut the perimeter wire", _marker(seg1.WIRE_POS, 1.0))
		"s1_sniper":
			hud.prompt("")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(OVERWATCH, "You're through. Tower sniper is your priority. Once he's down, the yard is blind.", 0.5)
			say(OVERWATCH, "Right-click to aim. That light is a target too if you want to keep it simple.")
			hud.set_objective("Neutralize the guard tower sniper", seg1.sniper)
		"s1_downhill":
			seg1.stop_searchlight()
			say(OVERWATCH, "Sniper down. Tower's dark. Nice work, Major.", 0.8)
			say(OVERWATCH, "Kranor Logistics is at the bottom of the slope. Follow the access road to the gate.")
			say(VANCE, "Moving down.")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			hud.set_objective("Move down the slope into Kranor Logistics Yard", Vector3(20, 2, game.terrain.YARD_Z))
		"s2_enter":
			game.set_atmosphere("yard")
			hud.title("SEGMENT 2", "The Logistics Hub Infiltration     |     Kranor Logistics Yard")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			say(OVERWATCH, "You're inside Kranor. The target terminal is in the admin office, dead centre of the yard.", 1.0)
			say(OVERWATCH, "Container stacks will box you in. Watch every corner.")
			hud.set_objective("Find the admin office terminal (coming next)")


func skip() -> void:
	match step:
		"s1_intro":
			game.player.global_position = game.seg1.WIRE_POS + Vector3(0, game.terrain.height_at(0, -32) + 0.3, -2.0)
		"s1_cut":
			_cut_progress = 99.0
		"s1_sniper":
			if game.seg1.sniper:
				game.seg1.sniper.take_hit(999, game.seg1.sniper.eye(), Vector3.ZERO)
		"s1_downhill":
			game.player.global_position = Vector3(20, 0.5, game.terrain.YARD_Z + 4.0)


# ------------------------------------------------------------------ segment 1

func _spawn_segment1() -> void:
	var t = game.terrain
	var seg1 = game.seg1
	var tp: Vector3 = seg1.TOWER_POS
	seg1.sniper = game.spawn_enemy(tp + Vector3(0.6, 9.2, -0.6), [], true, true, 0.0, "Tower")
	# Fence patrol just inside the wire
	game.spawn_enemy(Vector3(-24, t.height_at(-24, -24), -24), [Vector3(-24, 0, -24), Vector3(16, 0, -23)], false, false, 0.0)
	# Road patrol
	game.spawn_enemy(Vector3(22, 0, 26), [Vector3(22, 0, 26), Vector3(21, 0, -6)], false, false, PI)
	# Guard at the tower base, and one by the sawmill
	game.spawn_enemy(tp + Vector3(3, 0, 4), [tp + Vector3(3, 0, 4), tp + Vector3(-5, 0, 5), tp + Vector3(-4, 0, -3)], false, false, PI)
	game.spawn_enemy(Vector3(-24, 0, 12), [], false, true, PI * 0.8)


func _do_cut(delta: float) -> void:
	var hud = game.hud
	if not _near(game.seg1.WIRE_POS, 3.2):
		hud.prompt("")
		_cut_progress = 0.0
		return
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		var before := _cut_progress
		_cut_progress += delta / 2.4
		if int(before * 4) != int(_cut_progress * 4):
			S.play3d(game, "cut", game.seg1.WIRE_POS + Vector3(0, 1, 0), -6.0)
		hud.prompt("Cutting the wire...", _cut_progress)
	else:
		_cut_progress = maxf(0.0, _cut_progress - delta)
		hud.prompt("Hold  F  to cut the wire", _cut_progress if _cut_progress > 0 else -1.0)
	if _cut_progress >= 1.0:
		game.seg1.cut_wire()
		_go("s1_sniper")


# ------------------------------------------------------------------ events

func on_alert(_enemy) -> void:
	if _alert_lines < 3 and _t > 5.0:
		var lines := ["You've been made! Put them down or break line of sight!", "Contact! They know you're there, Vance!", "More movement, they're converging on you!"]
		say(OVERWATCH, lines[_alert_lines], 0.0, true)
		_alert_lines += 1


func on_enemy_killed(enemy) -> void:
	if enemy == game.seg1.sniper:
		return
	if _kill_lines < 4 and randf() < 0.6:
		var lines := ["Tango down.", "Good kill.", "He's down. Keep moving.", "Clean. Nobody saw that."]
		say(OVERWATCH, lines[_kill_lines], 0.3, true)
		_kill_lines += 1


func on_respawn() -> void:
	say(OVERWATCH, "Vance, you still with me? ...Okay. Take it slower this time.", 1.0, true)


# ------------------------------------------------------------------ radio

func say(speaker: String, text: String, delay := 0.4, priority := false) -> void:
	var entry := {"speaker": speaker, "text": text, "delay": delay}
	if priority:
		_radio_queue.push_front(entry)
	else:
		_radio_queue.append(entry)


func _process_radio(delta: float) -> void:
	_radio_wait -= delta
	if _radio_wait > 0.0 or _radio_queue.is_empty():
		return
	var e: Dictionary = _radio_queue[0]
	e.delay -= delta
	if e.delay > 0.0:
		return
	_radio_queue.pop_front()
	var duration := clampf(1.5 + e.text.length() * 0.055, 2.5, 8.0)
	game.hud.radio(e.speaker, e.text, duration)
	S.play2d(game, "radio", -16.0)
	_radio_wait = duration + 0.2


# ------------------------------------------------------------------ helpers

func _near(pos: Vector3, dist: float) -> bool:
	var p: Vector3 = game.player.global_position
	return Vector2(p.x - pos.x, p.z - pos.z).length() < dist


func _marker(pos: Vector3, up: float) -> Vector3:
	return Vector3(pos.x, game.terrain.height_at(pos.x, pos.z) + up, pos.z)
