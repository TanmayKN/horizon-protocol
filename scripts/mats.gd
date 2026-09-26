extends RefCounted
## Procedural materials and textures — everything generated in code, no image files needed.
## Usage: const M := preload("res://scripts/mats.gd")   then   M.get_mat("bark")

static var _cache := {}


static func get_mat(name: String) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]
	var m: StandardMaterial3D = _make(name)
	_cache[name] = m
	return m


## Tinted copy of a base material (cached per colour)
static func tinted(base: String, color: Color) -> StandardMaterial3D:
	var key := "%s_%s" % [base, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D = get_mat(base).duplicate()
	m.albedo_color = color
	_cache[key] = m
	return m


static func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "emit_%s_%f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


# ------------------------------------------------------------------ textures

static func noise_tex(seed: int, freq: float, w: int, h: int, colors: Array, normal := false, bump := 4.0, noise_type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH, octaves := 5) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = noise_type
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = w
	t.height = h
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	elif colors.size() > 0:
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var cols := PackedColorArray()
		for i in colors.size():
			offs.append(float(i) / maxf(1.0, colors.size() - 1))
			cols.append(colors[i])
		g.offsets = offs
		g.colors = cols
		t.color_ramp = g
	return t


## Corrugated metal: vertical ridges -> normal map
static func corrugated_normal() -> ImageTexture:
	var w := 128
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for x in w:
		var v := 0.5 + 0.5 * sin(x / float(w) * TAU * 8.0)
		for y in h:
			img.set_pixel(x, y, Color(v, v, v))
	img.bump_map_to_normal_map(6.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Chain-link diamond pattern with alpha
static func chainlink_tex() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for x in s:
		for y in s:
			var a := absf(fposmod(x + y, 32.0) - 16.0)
			var b := absf(fposmod(x - y, 32.0) - 16.0)
			var wire := a < 1.6 or b < 1.6
			img.set_pixel(x, y, Color(0.62, 0.64, 0.66, 1.0) if wire else Color(0, 0, 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Grass tuft sprite (blades with alpha)
static func grass_tex() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.36, 0.2, 0.0))   # transparent but grass-coloured (no dark mip fringes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for blade in 34:
		var x0 := rng.randf_range(10, w - 10)
		var lean := rng.randf_range(-26, 26)
		var height := rng.randf_range(0.4, 1.0) * h
		var col := Color(0.27, 0.34, 0.17).lerp(Color(0.45, 0.46, 0.26), rng.randf())
		for i in int(height):
			var t := i / height
			var x := x0 + lean * t * t
			var y := h - 1 - i
			var half := lerpf(1.8, 0.3, t)
			for xi in range(int(x - half - 1), int(x + half + 2)):
				if xi < 0 or xi >= w:
					continue
				var a := clampf(half + 0.5 - absf(xi - x), 0.0, 1.0)
				if a <= 0.0:
					continue
				var c := col.darkened(0.3 * (1.0 - t))
				var prev := img.get_pixel(xi, y)
				c.a = maxf(prev.a, a)
				img.set_pixel(xi, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Hazard stripes (yellow/black)
static func hazard_tex() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for x in s:
		for y in s:
			var on := fposmod(x + y, 32.0) < 16.0
			img.set_pixel(x, y, Color(0.85, 0.7, 0.1) if on else Color(0.08, 0.08, 0.08))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ materials

static func _base(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _make(name: String) -> StandardMaterial3D:
	match name:
		"ground":
			# Detail texture multiplied by per-vertex colour (forest / mud / gravel)
			var m := _base(Color.WHITE, 0.62)
			m.vertex_color_use_as_albedo = true
			m.albedo_texture = noise_tex(11, 0.02, 512, 512, [Color(0.62, 0.62, 0.6), Color(1, 1, 1), Color(0.8, 0.78, 0.72)])
			m.normal_enabled = true
			m.normal_texture = noise_tex(12, 0.05, 512, 512, [], true, 6.0)
			m.normal_scale = 0.8
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.18, 0.18, 0.18)
			return m
		"bark":
			var m := _base(Color(0.9, 0.85, 0.8), 0.95)
			m.albedo_texture = noise_tex(21, 0.09, 64, 512, [Color(0.16, 0.11, 0.08), Color(0.33, 0.24, 0.17), Color(0.24, 0.17, 0.12)], false, 0, FastNoiseLite.TYPE_CELLULAR, 3)
			m.normal_enabled = true
			m.normal_texture = noise_tex(22, 0.09, 64, 512, [], true, 10.0, FastNoiseLite.TYPE_CELLULAR, 3)
			m.uv1_scale = Vector3(3, 2, 1)
			return m
		"needles":
			var m := _base(Color(1, 1, 1), 0.9)
			m.albedo_texture = noise_tex(31, 0.2, 128, 128, [Color(0.05, 0.12, 0.07), Color(0.11, 0.22, 0.12), Color(0.07, 0.16, 0.09)])
			m.normal_enabled = true
			m.normal_texture = noise_tex(32, 0.25, 128, 128, [], true, 3.0)
			m.uv1_scale = Vector3(4, 3, 1)
			return m
		"log":
			var m := _base(Color.WHITE, 0.9)
			m.albedo_texture = noise_tex(41, 0.12, 64, 512, [Color(0.3, 0.21, 0.13), Color(0.45, 0.33, 0.2), Color(0.36, 0.26, 0.16)], false, 0, FastNoiseLite.TYPE_CELLULAR, 2)
			m.normal_enabled = true
			m.normal_texture = noise_tex(42, 0.12, 64, 512, [], true, 8.0, FastNoiseLite.TYPE_CELLULAR, 2)
			m.uv1_scale = Vector3(2, 1, 1)
			return m
		"wood":
			var m := _base(Color.WHITE, 0.85)
			m.albedo_texture = noise_tex(45, 0.03, 256, 32, [Color(0.28, 0.2, 0.13), Color(0.4, 0.3, 0.2)])
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			return m
		"metal":
			var m := _base(Color(0.55, 0.57, 0.6), 0.35, 0.8)
			m.albedo_texture = noise_tex(51, 0.04, 256, 256, [Color(0.75, 0.75, 0.75), Color(1, 1, 1)])
			m.uv1_triplanar = true
			return m
		"rust":
			var m := _base(Color.WHITE, 0.75, 0.4)
			m.albedo_texture = noise_tex(52, 0.05, 256, 256, [Color(0.35, 0.18, 0.1), Color(0.45, 0.45, 0.45), Color(0.5, 0.28, 0.14), Color(0.38, 0.38, 0.4)])
			m.normal_enabled = true
			m.normal_texture = noise_tex(53, 0.08, 256, 256, [], true, 3.0)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			return m
		"corrugated":
			var m := _base(Color(0.6, 0.62, 0.63), 0.5, 0.55)
			m.albedo_texture = noise_tex(54, 0.03, 256, 256, [Color(0.7, 0.68, 0.66), Color(1, 1, 1), Color(0.8, 0.7, 0.62)])
			m.normal_enabled = true
			m.normal_texture = corrugated_normal()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.35, 0.35, 0.35)
			return m
		"concrete":
			var m := _base(Color(0.62, 0.62, 0.6), 0.85)
			m.albedo_texture = noise_tex(61, 0.08, 256, 256, [Color(0.7, 0.7, 0.68), Color(1, 1, 1), Color(0.82, 0.82, 0.8)])
			m.normal_enabled = true
			m.normal_texture = noise_tex(62, 0.2, 256, 256, [], true, 2.0)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.25, 0.25, 0.25)
			return m
		"asphalt":
			var m := _base(Color(0.2, 0.2, 0.21), 0.45)
			m.albedo_texture = noise_tex(63, 0.3, 256, 256, [Color(0.7, 0.7, 0.7), Color(1, 1, 1)])
			m.normal_enabled = true
			m.normal_texture = noise_tex(64, 0.4, 256, 256, [], true, 3.0)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.3, 0.3, 0.3)
			return m
		"chainlink":
			var m := _base(Color.WHITE, 0.4, 0.7)
			m.albedo_texture = chainlink_tex()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.2, 1.2, 1.2)
			return m
		"grass":
			var m := _base(Color.WHITE, 0.9)
			m.albedo_texture = grass_tex()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.35
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"hazard":
			var m := _base(Color.WHITE, 0.6)
			m.albedo_texture = hazard_tex()
			m.uv1_triplanar = true
			return m
		"glass":
			var m := _base(Color(0.5, 0.6, 0.65, 0.3), 0.05, 0.2)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			return m
		"uniform":
			var m := _base(Color.WHITE, 0.9)
			m.albedo_texture = noise_tex(71, 0.15, 128, 128, [Color(0.16, 0.18, 0.15), Color(0.24, 0.26, 0.2), Color(0.12, 0.13, 0.12)], false, 0, FastNoiseLite.TYPE_CELLULAR, 2)
			return m
		"gear":
			return _base(Color(0.08, 0.09, 0.08), 0.8)
		"gun_metal":
			return _base(Color(0.1, 0.1, 0.11), 0.35, 0.8)
		"gun_polymer":
			var m := _base(Color(0.42, 0.36, 0.26), 0.8)
			m.albedo_texture = noise_tex(81, 0.4, 64, 64, [Color(0.85, 0.85, 0.85), Color(1, 1, 1)])
			return m
		"mud":
			var m := _base(Color(0.2, 0.14, 0.08), 0.35)
			return m
		"black":
			return _base(Color(0.02, 0.02, 0.02), 0.9)
	push_warning("Unknown material: " + name)
	return _base(Color.MAGENTA, 0.5)
