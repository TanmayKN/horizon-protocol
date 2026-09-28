extends Node
## Runs the soundtrack and the soundscape:
##  - music that follows the action (stealth -> combat, boss fight, stingers when you're spotted)
##  - ambience per place (forest + rain outside, rain on the roof inside, bunker drone underground)
##  - room reverb indoors, heartbeat when Vance is badly hurt, occasional thunder
const S := preload("res://scripts/sfx.gd")

var game
var _music := {}          # name -> AudioStreamPlayer
var _music_target := {}   # name -> target volume (linear 0..1)
var _amb := {}
var _amb_target := {}
var _heart: AudioStreamPlayer
var _heart_t := 0.0
var _check_t := 0.0
var _covered := false
var _combat_hold := 0.0
var _last_alert := -100.0
var _thunder_t := 20.0
var mode := "menu"        # menu | play | cutscene | ride | boss | silent
var _was_combat := false

const MUSIC_DB := -9.0


func _ready() -> void:
	S.ensure_buses()
	for m in ["music_menu", "music_stealth", "music_combat", "music_boss"]:
		var p := AudioStreamPlayer.new()
		p.stream = S.get_stream(m)
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music[m] = p
		_music_target[m] = 0.0
	for a in ["forest", "wind", "rain", "rain_roof", "hum", "bunker"]:
		var p := AudioStreamPlayer.new()
		p.stream = S.get_stream(a)
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		_amb[a] = p
		_amb_target[a] = 0.0
	_heart = AudioStreamPlayer.new()
	_heart.bus = "SFX"
	add_child(_heart)


func _vol(p: AudioStreamPlayer, target: float, rate: float, delta: float, base_db: float) -> void:
	var cur := db_to_linear(p.volume_db - base_db) if p.volume_db > -79.0 else 0.0
	cur = move_toward(cur, target, rate * delta)
	if cur <= 0.001:
		if p.playing:
			p.stop()
		p.volume_db = -80.0
	else:
		if not p.playing:
			p.play(randf() * 4.0 if p.stream and p.stream.get_length() > 8.0 else 0.0)
		p.volume_db = base_db + linear_to_db(cur)


func stinger(name: String, db := -4.0) -> void:
	S.play2d(self, name, db, 0.0)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	var step: String = game.mission.step if game.mission else ""
	# ---------------------------------------------------------------- music state
	var combat: bool = game.max_awareness() >= 1.0
	if combat:
		_combat_hold = 9.0          # keep combat music going a while after the last contact
	else:
		_combat_hold -= delta
	var in_combat := _combat_hold > 0.0
	if in_combat and not _was_combat and game.play_time - _last_alert > 30.0 and mode == "play":
		_last_alert = game.play_time
		stinger("sting_alert", -6.0)
	_was_combat = in_combat
	for k in _music_target:
		_music_target[k] = 0.0
	match mode:
		"menu":
			_music_target["music_menu"] = 1.0
		"play":
			if step == "s4_ride" or step == "s5_drive":
				_music_target["music_combat"] = 1.0
			elif step == "s5_raskov" or step.begins_with("s6_boss"):
				_music_target["music_boss"] = 1.0
			elif in_combat:
				_music_target["music_combat"] = 1.0
			else:
				_music_target["music_stealth"] = 0.75
		"cutscene":
			_music_target["music_menu"] = 0.55
		"silent":
			pass
	# duck the music while someone is talking
	var duck := 0.45 if preload("res://scripts/voice.gd").talking > 0 else 1.0
	for k in _music:
		var rate := 0.5 if _music_target[k] > 0.0 else 0.35
		_vol(_music[k], _music_target[k] * duck, rate * 2.0, delta, MUSIC_DB)

	# ---------------------------------------------------------------- ambience + reverb
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.25
		var from: Vector3 = p.global_position + Vector3(0, 2.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 25, 0))
		q.exclude = [p.get_rid()]
		_covered = not p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	var raining: bool = game._rain_on
	var bunker: bool = step.begins_with("s5") or step == "e_return"
	for k in _amb_target:
		_amb_target[k] = 0.0
	if bunker and _covered:
		_amb_target["bunker"] = 1.0
		_amb_target["hum"] = 0.25
	elif _covered:
		_amb_target["hum"] = 0.8 if not game.seg2.blackout or not game.seg2.in_admin(p.global_position) else 0.0
		_amb_target["rain_roof"] = 0.9 if raining else 0.0
	else:
		_amb_target["rain"] = 1.0 if raining else 0.0
		_amb_target["wind"] = 0.7
		_amb_target["forest"] = 0.8 if p.global_position.z < 30.0 and p.global_position.z > -130.0 else 0.0
	S.set_indoor(1.0 if _covered else 0.0)
	var amb_db := {"forest": -14.0, "wind": -18.0, "rain": -12.0, "rain_roof": -14.0, "hum": -20.0, "bunker": -12.0}
	for k in _amb:
		_vol(_amb[k], _amb_target[k], 0.6, delta, amb_db[k])

	# thunder now and then while it rains outside
	_thunder_t -= delta
	if _thunder_t <= 0.0:
		_thunder_t = randf_range(35.0, 80.0)
		if raining and mode == "play":
			S.play2d(self, "thunder", -12.0 if not _covered else -20.0, 0.1)

	# ---------------------------------------------------------------- heartbeat when low
	if not p.is_dead and p.health < 35.0:
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = lerpf(0.55, 0.9, p.health / 35.0)
			S.play2d(self, "heartbeat", lerpf(-4.0, -14.0, p.health / 35.0), 0.0)
