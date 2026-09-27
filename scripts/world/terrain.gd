extends Node3D
## The valley terrain shared by Segment 1 (forest slope + logging yard) and Segment 2 (Kranor yard).
## Mountains rise at the edges so the valley closes itself off naturally.

const M := preload("res://scripts/mats.gd")

const X_MIN := -130.0
const X_MAX := 130.0
const Z_MIN := -120.0
const Z_MAX := 210.0
const SPACING := 2.0
const ROAD_X := 20.0
const ROAD_HALF := 4.0
const FENCE_Z := -30.0
const YARD_Z := 36.0      # Kranor perimeter

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()


func _init() -> void:
	noise.seed = 1337
	noise.frequency = 0.028
	detail.seed = 99
	detail.frequency = 0.12


func road_x_at(z: float) -> float:
	# The access road snakes gently down the slope
	if z < -10.0:
		return ROAD_X + sin(z * 0.045) * 6.0
	return ROAD_X


## The creek winds across the forest slope from west to east
func creek_z(x: float) -> float:
	return -74.0 + sin(x * 0.05) * 7.0 + sin(x * 0.013 + 1.0) * 5.0


func creek_dist(x: float, z: float) -> float:
	return absf(z - creek_z(x))


func height_at(x: float, z: float) -> float:
	return _base_height(x, z) - _creek_cut(x, z)


func _creek_cut(x: float, z: float) -> float:
	var d := creek_dist(x, z)
	if d > 3.5:
		return 0.0
	var t := 1.0 - d / 3.5
	return t * t * 1.3


func water_level(x: float) -> float:
	return _base_height(x, creek_z(x)) - 0.75


func _base_height(x: float, z: float) -> float:
	var h := 0.0
	var forest := 0.0
	if z < -10.0:
		h = (-10.0 - z) * 0.2
		forest = clampf((-10.0 - z) / 18.0, 0.0, 1.0)
	var road_d := absf(x - road_x_at(z))
	var road_flat := clampf((road_d - ROAD_HALF) / 5.0, 0.0, 1.0)
	h += noise.get_noise_2d(x, z) * 2.6 * forest * road_flat
	h += detail.get_noise_2d(x, z) * 0.25 * forest
	# Road is cut slightly into the hillside
	if road_d < ROAD_HALF + 1.0:
		h -= 0.15 * forest
	# Mountains around the valley
	var edge_x := maxf(0.0, absf(x) - 85.0) / 45.0
	var edge_z := maxf(0.0, Z_MIN + 40.0 - z) / 40.0 + maxf(0.0, z - (Z_MAX - 30.0)) / 30.0
	var edge := clampf(maxf(edge_x, edge_z), 0.0, 1.0)
	# The exit road cuts a pass through the northern mountains
	if z > 150.0:
		edge *= clampf((absf(x - 15.0) - 9.0) / 12.0, 0.0, 1.0)
	h += edge * edge * (32.0 + noise.get_noise_2d(x * 0.5, z * 0.5) * 10.0)
	return h


func surface_at(pos: Vector3) -> String:
	if pos.z < -50.0 and creek_dist(pos.x, pos.z) < 2.2:
		return "mud"   # wading through the creek
	if pos.z > YARD_Z - 2.0 and pos.y < 1.0:
		return "hard"
	if absf(pos.x - road_x_at(pos.z)) < ROAD_HALF and pos.z < YARD_Z:
		return "mud"
	if absf(pos.x) < 4.0 and absf(pos.z - FENCE_Z) < 4.0:
		return "mud"
	return "grass"


func _ready() -> void:
	var nx := int((X_MAX - X_MIN) / SPACING) + 1
	var nz := int((Z_MAX - Z_MIN) / SPACING) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var x := X_MIN + i * SPACING
			var z := Z_MIN + j * SPACING
			var h := height_at(x, z)
			heights[j * nx + i] = h
			st.set_color(_color_at(x, z, h))
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()
	st.generate_tangents()

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _terrain_material()
	body.add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(SPACING, 1, SPACING)
	# HeightMapShape3D is centred on its origin
	cs.position = Vector3((X_MIN + X_MAX) / 2.0, 0, (Z_MIN + Z_MAX) / 2.0)
	body.add_child(cs)
	_build_creek()


func _build_creek() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev := []
	var x := X_MIN + 8.0
	var u := 0.0
	while x < X_MAX - 8.0:
		var cz := creek_z(x)
		var wl := water_level(x)
		var cur := [Vector3(x, wl, cz - 2.6), Vector3(x, wl, cz + 2.6), u]
		if not prev.is_empty():
			for v in [[prev[0], Vector2(prev[2], 0)], [cur[0], Vector2(u, 0)], [cur[1], Vector2(u, 1)], [prev[0], Vector2(prev[2], 0)], [cur[1], Vector2(u, 1)], [prev[1], Vector2(prev[2], 1)]]:
				st.set_normal(Vector3.UP)
				st.set_uv(v[1])
				st.add_vertex(v[0])
		prev = cur
		x += 2.0
		u += 0.4
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var tex := M.tex("mud_normal")
	if tex:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/water.gdshader")
		sm.set_shader_parameter("normal_a", tex)
		mi.material_override = sm
	else:
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.07, 0.1, 0.09, 0.8)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.roughness = 0.05
		mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Low mist hanging over the water (volumetric fog volumes)
	for mx in [-70.0, -30.0, 10.0, 50.0, 90.0]:
		var fv := FogVolume.new()
		fv.size = Vector3(36, 3.0, 12)
		fv.position = Vector3(mx, water_level(mx) + 1.0, creek_z(mx))
		var fm := FogMaterial.new()
		fm.density = 0.06
		fm.albedo = Color(0.8, 0.83, 0.85)
		fm.height_falloff = 0.8
		fv.material = fm
		add_child(fv)
	# Water sound along the creek
	for sx in [-60.0, 0.0, 60.0]:
		var snd := AudioStreamPlayer3D.new()
		snd.stream = load("res://scripts/sfx.gd").get_stream("wind")
		snd.pitch_scale = 2.6
		snd.volume_db = -6.0
		snd.unit_size = 5.0
		snd.max_distance = 45.0
		snd.position = Vector3(sx, water_level(sx), creek_z(sx))
		snd.autoplay = true
		add_child(snd)


func _terrain_material() -> Material:
	if M.tex("forest_floor_albedo") == null:
		return M.get_mat("ground")
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/terrain.gdshader")
	for pair in [["forest", "forest_floor"], ["mud", "mud"], ["gravel", "gravel"], ["conc", "concrete"], ["rock", "rock"]]:
		sm.set_shader_parameter(pair[0] + "_a", M.tex(pair[1] + "_albedo"))
		sm.set_shader_parameter(pair[0] + "_n", M.tex(pair[1] + "_normal"))
		sm.set_shader_parameter(pair[0] + "_r", M.tex(pair[1] + "_rough"))
	return sm


## Splat weights for the terrain shader: r = mud, g = gravel, b = concrete, a = rock
func _weights_at(x: float, z: float, h: float) -> Color:
	var w := Color(0, 0, 0, 0)
	if z > -10.0:
		w.g = clampf((z + 10.0) / 6.0, 0.0, 1.0)
	if z > YARD_Z - 2.0:
		w.b = 1.0
		w.g = 0.0
	var road_d := absf(x - road_x_at(z))
	if z < YARD_Z:
		w.r = clampf((ROAD_HALF + 0.8 - road_d) / 1.6, 0.0, 1.0)
		if absf(x) < 5.0 and absf(z - FENCE_Z) < 5.0:
			w.r = maxf(w.r, clampf((5.0 - Vector2(x, z - FENCE_Z).length()) / 2.0, 0.0, 1.0))
	if z < -50.0:
		w.r = maxf(w.r, clampf((3.8 - creek_dist(x, z)) / 1.5, 0.0, 1.0))
	# Steep ground and the mountains are bare rock
	var dx := height_at(x + 1.0, z) - height_at(x - 1.0, z)
	var dz := height_at(x, z + 1.0) - height_at(x, z - 1.0)
	var slope := Vector2(dx, dz).length() / 2.0
	w.a = clampf((slope - 0.45) * 2.5, 0.0, 1.0)
	if h > 12.0:
		w.a = maxf(w.a, clampf((h - 12.0) / 8.0, 0.0, 0.9))
	return w


func _color_at(x: float, z: float, h: float) -> Color:
	if M.tex("forest_floor_albedo") != null:
		return _weights_at(x, z, h)
	var n := noise.get_noise_2d(x * 3.0, z * 3.0)
	var c := Color(0.2, 0.25, 0.14).lerp(Color(0.27, 0.24, 0.15), 0.5 + n * 0.5)   # forest floor + needles
	if z > -10.0:
		c = Color(0.34, 0.32, 0.28).lerp(Color(0.28, 0.26, 0.22), 0.5 + n * 0.5)   # gravel yard
	if z > YARD_Z - 2.0:
		c = Color(0.36, 0.36, 0.35).lerp(Color(0.3, 0.3, 0.3), 0.5 + n * 0.5)      # concrete apron
	var road_d := absf(x - road_x_at(z))
	if z < YARD_Z and (road_d < ROAD_HALF or (absf(x) < 4.0 and absf(z - FENCE_Z) < 4.0)):
		c = Color(0.22, 0.16, 0.1).lerp(Color(0.17, 0.12, 0.08), 0.5 + n * 0.5)   # mud
		if road_d > ROAD_HALF - 0.8 and road_d < ROAD_HALF:
			c = c.lightened(0.08)
	if h > 14.0 and (absf(x) > 85.0 or z < -80.0 or z > 180.0):
		c = c.lerp(Color(0.36, 0.36, 0.36), clampf((h - 14.0) / 12.0, 0.0, 0.8))  # rocky mountain
	return c
