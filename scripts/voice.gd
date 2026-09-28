extends RefCounted
## Voice acting: plays the generated line for (speaker, text) if it exists (see tools/gen_voice.py).
## Radio calls go through the "Radio" bus (band-passed, crunchy), the PA through a big echoey bus,
## everything else is clean. The music ducks while someone talks.

const DIR := "res://assets/voice/"
static var talking := 0          # how many voice lines are playing right now (for music ducking)
static var _current: AudioStreamPlayer


static func path_for(speaker: String, text: String) -> String:
	return DIR + ("%s|%s" % [speaker, text]).md5_text().substr(0, 12) + ".ogg"


static func bus_for(speaker: String) -> String:
	var s := speaker.to_lower()
	if s.contains("(pa)"):
		return "PA" if AudioServer.get_bus_index("PA") >= 0 else "Master"
	if s.contains("overwatch") or s.contains("command") or s.contains("nightingale") or s.contains("intercept"):
		return "Radio" if AudioServer.get_bus_index("Radio") >= 0 else "Master"
	return "Voice" if AudioServer.get_bus_index("Voice") >= 0 else "Master"


## Plays the line (interrupting the previous one) and returns its length in seconds (0 if none)
static func play(host: Node, speaker: String, text: String, volume_db := 0.0) -> float:
	var path := path_for(speaker, text)
	if host == null or not ResourceLoader.exists(path):
		return 0.0
	stop()
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = bus_for(speaker)
	p.volume_db = volume_db + (2.0 if p.bus == "Radio" else 0.0)
	host.add_child(p)
	talking += 1
	p.finished.connect(func():
		talking = maxi(0, talking - 1)
		p.queue_free())
	p.play()
	_current = p
	return p.stream.get_length()


static func stop() -> void:
	if _current and is_instance_valid(_current):
		if _current.playing:
			talking = maxi(0, talking - 1)
		_current.stop()
		_current.queue_free()
	_current = null


## A shout from a soldier, positioned in the world
static func shout3d(node: Node3D, text: String) -> void:
	var path := path_for("Shout", text)
	if node == null or not node.is_inside_tree() or not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.unit_size = 8.0
	p.volume_db = 4.0
	p.max_distance = 70.0
	p.pitch_scale = randf_range(0.92, 1.08)
	node.add_child(p)
	p.position = Vector3(0, 1.7, 0)
	p.finished.connect(p.queue_free)
	p.play()
