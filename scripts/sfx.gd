extends RefCounted
## Procedural sound effects — synthesised in code, no audio files needed.
## Usage: const S := preload("res://scripts/sfx.gd")   S.play3d(node, "rifle", pos)

const RATE := 22050
static var _cache := {}


static func get_stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		_cache[name] = _make(name)
	return _cache[name]


static func play3d(parent: Node, name: String, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.08, max_dist := 120.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	var host: Node = parent.get_tree().current_scene
	if host == null:
		host = parent.get_tree().root
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


static func play2d(parent: Node, name: String, volume_db := 0.0, pitch_jitter := 0.05) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Looping ambience player (not freed)
static func loop2d(parent: Node, name: String, volume_db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	parent.add_child(p)
	p.play()
	return p


# ------------------------------------------------------------------ synthesis

static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples.size()
	return s


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Noise burst with exponential decay, low-passed by `lp` (0..1, lower = darker)
static func _burst(b: PackedFloat32Array, start: float, length: float, decay: float, lp: float, gain: float) -> void:
	var y := 0.0
	var i0 := int(start * RATE)
	var n := int(length * RATE)
	for i in n:
		if i0 + i >= b.size():
			break
		var t := i / float(RATE)
		y += lp * (randf_range(-1, 1) - y)
		b[i0 + i] += y * gain * exp(-t * decay)


static func _tone(b: PackedFloat32Array, start: float, length: float, f0: float, f1: float, decay: float, gain: float) -> void:
	var i0 := int(start * RATE)
	var n := int(length * RATE)
	var ph := 0.0
	for i in n:
		if i0 + i >= b.size():
			break
		var t := i / float(RATE)
		var f := lerpf(f0, f1, t / length)
		ph += TAU * f / RATE
		b[i0 + i] += sin(ph) * gain * exp(-t * decay)


static func _normalize(b: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	for i in b.size():
		b[i] = b[i] / m * peak
	return b


static func _make(name: String) -> AudioStreamWAV:
	var b: PackedFloat32Array
	match name:
		"rifle":        # suppressed rifle: dull thump + mechanical clack
			b = _buf(0.35)
			_burst(b, 0.0, 0.3, 28.0, 0.25, 1.0)
			_tone(b, 0.0, 0.12, 140, 60, 30.0, 0.8)
			_burst(b, 0.05, 0.05, 90.0, 0.9, 0.35)
		"enemy_rifle":  # unsuppressed crack
			b = _buf(0.6)
			_burst(b, 0.0, 0.6, 9.0, 0.7, 1.0)
			_tone(b, 0.0, 0.2, 110, 45, 18.0, 0.9)
		"sniper":
			b = _buf(1.4)
			_burst(b, 0.0, 0.08, 60.0, 1.0, 1.0)
			_burst(b, 0.0, 1.4, 3.5, 0.18, 0.7)
			_tone(b, 0.0, 0.3, 90, 35, 10.0, 0.8)
		"step_grass":
			b = _buf(0.12)
			_burst(b, 0.0, 0.12, 40.0, 0.35, 1.0)
		"step_mud":
			b = _buf(0.22)
			_burst(b, 0.0, 0.22, 18.0, 0.12, 1.0)
			_tone(b, 0.02, 0.15, 180, 90, 25.0, 0.4)
		"step_hard":
			b = _buf(0.1)
			_burst(b, 0.0, 0.1, 60.0, 0.6, 1.0)
			_tone(b, 0.0, 0.05, 220, 150, 60.0, 0.3)
		"step_metal":
			b = _buf(0.3)
			_burst(b, 0.0, 0.08, 70.0, 0.7, 0.6)
			_tone(b, 0.0, 0.3, 620, 600, 14.0, 0.35)
			_tone(b, 0.0, 0.3, 910, 890, 18.0, 0.2)
		"rain":
			b = _buf(3.0)
			var y := 0.0
			var prev := 0.0
			for i in b.size():
				var x := randf_range(-1, 1)
				y = 0.9 * (y + x - prev)   # high-pass
				prev = x
				b[i] = y * 0.3
				if randf() < 0.0015:
					b[i] += randf_range(0.3, 0.7)   # individual drops
		"radio":
			b = _buf(0.45)
			for k in 7:
				_burst(b, k * 0.06 + randf() * 0.02, 0.05, 30.0, 0.95, randf_range(0.4, 1.0))
			_tone(b, 0.0, 0.45, 1400, 1400, 3.0, 0.08)
		"hum":
			b = _buf(2.0)
			for i in b.size():
				var t := i / float(RATE)
				b[i] = sin(TAU * 50 * t) * 0.5 + sin(TAU * 100 * t) * 0.3 + sin(TAU * 150 * t) * 0.15 + randf_range(-0.05, 0.05)
		"alarm":
			b = _buf(1.2)
			_tone(b, 0.0, 0.6, 880, 880, 0.0, 0.5)
			_tone(b, 0.6, 0.6, 660, 660, 0.0, 0.5)
		"reload":
			b = _buf(0.9)
			_burst(b, 0.0, 0.05, 80.0, 0.9, 0.8)
			_tone(b, 0.0, 0.05, 900, 700, 60.0, 0.4)
			_burst(b, 0.55, 0.06, 70.0, 0.9, 1.0)
			_tone(b, 0.55, 0.08, 1200, 800, 50.0, 0.5)
			_burst(b, 0.75, 0.05, 80.0, 0.95, 0.9)
		"cut":
			b = _buf(0.25)
			_tone(b, 0.0, 0.1, 2400, 1800, 40.0, 0.6)
			_burst(b, 0.0, 0.2, 25.0, 0.9, 0.6)
			_tone(b, 0.02, 0.25, 700, 650, 12.0, 0.3)
		"impact":
			b = _buf(0.15)
			_burst(b, 0.0, 0.15, 45.0, 0.5, 1.0)
		"hit":
			b = _buf(0.18)
			_burst(b, 0.0, 0.18, 30.0, 0.3, 1.0)
			_tone(b, 0.0, 0.1, 160, 80, 30.0, 0.6)
		"hurt":
			b = _buf(0.3)
			_tone(b, 0.0, 0.3, 90, 50, 12.0, 1.0)
			_burst(b, 0.0, 0.1, 40.0, 0.2, 0.5)
		"empty":
			b = _buf(0.08)
			_burst(b, 0.0, 0.03, 120.0, 0.95, 1.0)
		"engine":
			b = _buf(1.0)
			for i in b.size():
				var t := i / float(RATE)
				b[i] = sin(TAU * 40 * t) * 0.4 + sign(sin(TAU * 80 * t)) * 0.15 + randf_range(-0.15, 0.15)
		"vent":
			b = _buf(3.0)
			var y2 := 0.0
			for i in b.size():
				y2 += 0.04 * (randf_range(-1, 1) - y2)
				b[i] = y2 * 3.0 + sin(TAU * 60 * i / float(RATE)) * 0.08
		"wind":
			b = _buf(4.0)
			var y3 := 0.0
			for i in b.size():
				var t := i / float(RATE)
				y3 += 0.02 * (randf_range(-1, 1) - y3)
				b[i] = y3 * 4.0 * (0.6 + 0.4 * sin(TAU * t / 4.0))
		"whiz":         # bullet snapping past
			b = _buf(0.2)
			_burst(b, 0.0, 0.2, 25.0, 0.9, 0.7)
			_tone(b, 0.0, 0.2, 3000, 1200, 20.0, 0.3)
		"door":
			b = _buf(0.8)
			_burst(b, 0.0, 0.8, 5.0, 0.08, 1.0)
			_tone(b, 0.0, 0.8, 70, 40, 4.0, 0.7)
		"beep":
			b = _buf(0.15)
			_tone(b, 0.0, 0.15, 1500, 1500, 10.0, 0.6)
		"explosion":
			b = _buf(2.0)
			_burst(b, 0.0, 2.0, 2.5, 0.1, 1.0)
			_tone(b, 0.0, 0.8, 70, 25, 4.0, 1.0)
		"glass":
			b = _buf(0.8)
			for k in 12:
				_tone(b, randf() * 0.3, 0.4, randf_range(2500, 6000), randf_range(2000, 5000), 12.0, 0.3)
			_burst(b, 0.0, 0.3, 15.0, 0.95, 0.6)
		_:
			push_warning("Unknown sound: " + name)
			b = _buf(0.05)
	var loop := name in ["rain", "hum", "alarm", "engine", "vent", "wind"]
	return _wav(_normalize(b, 0.8 if loop else 0.95), loop)
