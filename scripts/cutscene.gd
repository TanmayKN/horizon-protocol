extends Node
## In-engine cinematic player: moving camera shots, letterbox, subtitles, skippable (hold SPACE).
##
##   await game.cutscene.play([
##       {"t": 4.0, "cam": [from, to], "look": [from, to], "fov": 45,
##        "lines": [[0.5, "Hale", "Nothing personal, Elena."]], "call": func(): ...},
##   ])
## Every state change goes in a shot's "call" so that skipping still runs them all, in order.

const S := preload("res://scripts/sfx.gd")
const Voice := preload("res://scripts/voice.gd")

var game
var active := false
var cam: Camera3D
var _skip_hold := 0.0
var _skipping := false
var _shake := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not active:
		return
	if Input.is_action_pressed("jump") or Input.is_key_pressed(KEY_ENTER):
		_skip_hold += delta
		game.hud.cine_skip(clampf(_skip_hold / 0.8, 0.0, 1.0))
		if _skip_hold > 0.8:
			_skipping = true
	else:
		_skip_hold = 0.0
		game.hud.cine_skip(0.0)
	if cam and _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.5)
		cam.h_offset = randf_range(-1, 1) * _shake * 0.05
		cam.v_offset = randf_range(-1, 1) * _shake * 0.05


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func play(shots: Array) -> void:
	if game.auto_skip_cutscenes:
		for sh in shots:
			if sh.has("call"):
				(sh["call"] as Callable).call()
			_flush_events(sh.get("events", []))
		return
	active = true
	game.cutscene_active = true
	_skipping = false
	_skip_hold = 0.0
	var p = game.player
	var was_enabled: bool = p.controls_enabled
	p.controls_enabled = false
	var prev_mode: String = game.audio.mode
	game.audio.mode = "cutscene"
	game.hud.cinema(true)
	cam = Camera3D.new()
	cam.far = 1500.0
	game.add_child(cam)
	cam.current = true
	for sh in shots:
		if sh.has("call"):
			(sh["call"] as Callable).call()
		if _skipping:
			_flush_events(sh.get("events", []))
			continue
		await _run_shot(sh)
	game.hud.subtitle("", "")
	Voice.stop()
	game.hud.cinema(false)
	cam.queue_free()
	cam = null
	p.camera.current = true
	p.controls_enabled = was_enabled or p.controls_enabled
	game.audio.mode = prev_mode if prev_mode != "cutscene" else "play"
	game.cutscene_active = false
	active = false
	if p.has_method("capture_mouse") and DisplayServer.window_is_focused():
		p.capture_mouse()


func _run_shot(sh: Dictionary) -> void:
	var dur: float = sh.get("t", 3.0)
	var c0 = sh["cam"][0]
	var c1 = sh["cam"][1] if sh["cam"].size() > 1 else c0
	var l0 = sh["look"][0]
	var l1 = sh["look"][1] if sh["look"].size() > 1 else l0
	cam.fov = sh.get("fov", 50.0)
	var lines: Array = sh.get("lines", []).duplicate(true)
	var events: Array = sh.get("events", []).duplicate(true)
	var t := 0.0
	var ease_fn := func(x: float) -> float: return x * x * (3.0 - 2.0 * x)
	while t < dur and not _skipping:
		var k: float = ease_fn.call(clampf(t / dur, 0.0, 1.0)) if sh.get("ease", true) else t / dur
		cam.global_position = _pt(c0).lerp(_pt(c1), k)
		var la: Vector3 = _pt(l0)
		var lb: Vector3 = _pt(l1)
		var look := la.lerp(lb, k)
		if cam.global_position.distance_to(look) > 0.01:
			cam.look_at(look, Vector3.UP)
		while not lines.is_empty() and t >= float(lines[0][0]):
			var ln: Array = lines.pop_front()
			game.hud.subtitle(String(ln[1]), String(ln[2]))
			var vlen: float = Voice.play(game, String(ln[1]), String(ln[2]))
			# give the actor time to finish: push the rest of the shot back if the line runs long
			var need := t + vlen + 0.25
			var nxt: float = float(lines[0][0]) if not lines.is_empty() else dur
			if vlen > 0.0 and need > nxt:
				var push := need - nxt
				for l2 in lines:
					l2[0] = float(l2[0]) + push
				for e2 in events:
					if float(e2[0]) > t:
						e2[0] = float(e2[0]) + push
				dur += push
		while not events.is_empty() and t >= float(events[0][0]):
			var ev: Array = events.pop_front()
			(ev[1] as Callable).call()
		await get_tree().process_frame
		t += get_process_delta_time()
	_flush_events(events)
	if sh.get("clear", false):
		game.hud.subtitle("", "")


func _flush_events(events: Array) -> void:
	for ev in events:
		(ev[1] as Callable).call()
	events.clear()


## A look-at / camera point can be a Vector3, a Node3D (its head height) or a Callable returning a Vector3
func _pt(v) -> Vector3:
	if v is Callable:
		return (v as Callable).call()
	if v is Node3D:
		return (v as Node3D).global_position + Vector3(0, 1.6, 0)
	return v
