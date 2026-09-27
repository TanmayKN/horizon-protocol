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


# ------------------------------------------------------------------ footsteps
# Each step = heel strike + toe roll, plus the surface texture (needles crackling,
# gravel crunching, mud squelching, boots on concrete, ringing steel grating).

static func _coef(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


## Band-limited noise hit: attack, then exponential decay
static func _band(b: PackedFloat32Array, start: float, length: float, decay: float, f_lo: float, f_hi: float, gain: float, attack := 0.003) -> void:
	# two-pole low-passes (12 dB/oct) so the band is well defined and not hissy
	var lo1 := 0.0
	var lo2 := 0.0
	var hi1 := 0.0
	var hi2 := 0.0
	var a_lo := _coef(f_lo)
	var a_hi := _coef(f_hi)
	var i0 := int(start * RATE)
	var n := int(length * RATE)
	for i in n:
		if i0 + i >= b.size() or i0 + i < 0:
			break
		var t := i / float(RATE)
		var x := randf_range(-1, 1)
		lo1 += a_lo * (x - lo1)
		lo2 += a_lo * (lo1 - lo2)
		hi1 += a_hi * (x - hi1)
		hi2 += a_hi * (hi1 - hi2)
		var env := minf(1.0, t / attack) * exp(-t * decay)
		b[i0 + i] += (hi2 - lo2) * gain * env * 1.6


## Lots of tiny clicks (needles, twigs, grit)
static func _crackle(b: PackedFloat32Array, start: float, length: float, count: int, f_lo: float, f_hi: float, gain: float) -> void:
	for k in count:
		var t := start + pow(randf(), 1.6) * length        # denser at the start of the step
		_band(b, t, 0.02, randf_range(180.0, 400.0), f_lo, f_hi, gain * randf_range(0.3, 1.0), 0.0005)


static func _step(surface: String) -> PackedFloat32Array:
	var b := _buf(0.42)
	var toe := randf_range(0.075, 0.11)                   # heel-to-toe gap
	var weight := randf_range(0.85, 1.1)
	match surface:
		"grass":        # forest floor: soft thud, needles and twigs crackling
			_band(b, 0.0, 0.12, 38.0, 50.0, 700.0, 0.9 * weight)
			_tone(b, 0.0, 0.08, 85, 55, 40.0, 0.35 * weight)
			_crackle(b, 0.005, 0.2, 22, 900.0, 3500.0, 0.14)
			_band(b, toe, 0.1, 45.0, 120.0, 1800.0, 0.35)
			_crackle(b, toe, 0.12, 10, 1000.0, 3800.0, 0.1)
			_band(b, 0.02, 0.3, 14.0, 1500.0, 4500.0, 0.03)     # leaves brushing
		"gravel":       # dense crunch of stones grinding
			_band(b, 0.0, 0.08, 45.0, 60.0, 900.0, 0.7 * weight)
			_crackle(b, 0.0, 0.22, 70, 700.0, 3500.0, 0.25)
			_crackle(b, toe, 0.16, 45, 800.0, 3800.0, 0.2)
			_band(b, 0.0, 0.3, 11.0, 600.0, 3500.0, 0.12)
		"mud":          # heavy wet squelch and suction as the boot pulls out
			_band(b, 0.0, 0.14, 26.0, 40.0, 450.0, 1.0 * weight)
			_tone(b, 0.0, 0.14, 110, 55, 22.0, 0.5 * weight)
			var lo := 0.0
			var a := _coef(900.0)
			var i0 := int((toe + 0.04) * RATE)
			var ph := 0.0
			for i in int(0.2 * RATE):
				if i0 + i >= b.size():
					break
				var t := i / float(RATE)
				lo += a * (randf_range(-1, 1) - lo)
				ph += TAU * lerpf(22.0, 9.0, t / 0.2) / RATE
				b[i0 + i] += lo * (0.5 + 0.5 * sin(ph)) * exp(-t * 11.0) * 0.8
			_tone(b, toe + 0.2, 0.05, 380, 900, 55.0, 0.18)       # little pop of air
			_crackle(b, 0.02, 0.15, 8, 400.0, 1500.0, 0.25)       # splash
		"hard":         # boots on concrete: crisp heel click, scuff, short room echo
			_band(b, 0.0, 0.05, 90.0, 200.0, 4500.0, 1.0 * weight, 0.0008)
			_tone(b, 0.0, 0.05, 140, 90, 70.0, 0.4 * weight)
			_band(b, toe, 0.07, 55.0, 500.0, 3500.0, 0.4)
			_band(b, 0.0, 0.35, 10.0, 250.0, 2500.0, 0.05)
			_band(b, 0.045, 0.05, 90.0, 300.0, 3000.0, 0.12, 0.0008)   # early reflection
		"metal":        # steel grating: clank with ringing partials and rattle
			_band(b, 0.0, 0.05, 80.0, 200.0, 4500.0, 0.8 * weight, 0.0008)
			for f in [410.0, 687.0, 1123.0, 1590.0, 2210.0]:
				var fr: float = f * randf_range(0.97, 1.03)
				_tone(b, 0.0, 0.4, fr, fr * 0.995, randf_range(9.0, 16.0), 0.22 * 400.0 / fr + 0.05)
			_crackle(b, 0.01, 0.12, 12, 1500.0, 4500.0, 0.15)
			_band(b, toe, 0.05, 80.0, 300.0, 4000.0, 0.4, 0.0008)
			for f in [520.0, 980.0]:
				_tone(b, toe, 0.25, f, f, 18.0, 0.1)
		_:
			_band(b, 0.0, 0.1, 40.0, 80.0, 2000.0, 1.0)
	# Final soft low-pass per surface (keeps steps warm instead of hissy)
	var cut: float = {"grass": 2600.0, "gravel": 3800.0, "mud": 2000.0, "hard": 4200.0, "metal": 5000.0}.get(surface, 3000.0)
	var ac := _coef(cut)
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		y1 += ac * (b[i] - y1)
		y2 += ac * (y1 - y2)
		b[i] = y2
	return b


static func _normalize(b: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	for i in b.size():
		b[i] = b[i] / m * peak
	return b


static func _make(name: String) -> AudioStreamWAV:
	var b: PackedFloat32Array
	if name.begins_with("step_"):
		return _wav(_normalize(_step(name.get_slice("_", 1)), 0.95))
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
		"pistol":
			b = _buf(0.45)
			_burst(b, 0.0, 0.45, 12.0, 0.8, 1.0)
			_tone(b, 0.0, 0.12, 180, 70, 25.0, 0.7)
		"swish":        # knife slash
			b = _buf(0.25)
			_burst(b, 0.0, 0.25, 14.0, 0.15, 0.6)
			_tone(b, 0.02, 0.18, 900, 400, 16.0, 0.12)
		"stab":
			b = _buf(0.2)
			_burst(b, 0.0, 0.2, 35.0, 0.2, 1.0)
			_tone(b, 0.0, 0.12, 120, 60, 30.0, 0.8)
		"swap":         # weapon draw / pick up: two metal clacks
			b = _buf(0.3)
			_burst(b, 0.0, 0.04, 110.0, 0.95, 0.8)
			_burst(b, 0.14, 0.05, 90.0, 0.9, 1.0)
			_tone(b, 0.14, 0.08, 1400, 1200, 50.0, 0.25)
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
