@tool
extends Node3D
## THE HORIZON PROTOCOL - Segment 1: The Perimeter Breach
## Map: The Timberline Outpost (greybox, built entirely in code)
## Layout: forest slope (z < -30) -> broken fence (z = -30) -> logging yard (z > -10)

const PlayerScript := preload("res://scripts/player.gd")

const SIZE := 200.0          # terrain is SIZE x SIZE metres
const RES := 101             # height samples per side
const FENCE_Z := -30.0
const GAP_HALF := 2.0        # broken section of fence: x in [-2, 2]
const ROAD_X := 20.0         # muddy access road runs along z at this x
const ROAD_HALF := 4.0
const TOWER_POS := Vector3(0, 0, 20)

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var player  # Vance (player.gd); untyped so its custom members resolve at runtime
var search_pivot: Node3D
var search_light: SpotLight3D
var hud_radio: Label
var hud_objective: Label
var hud_alert: Label
var hud_stance: Label
var hud_click: Label
var _log_timer := 0.0
var _time := 0.0
var _radio_index := 0
var _radio_hide_at := 0.0
var _breached := false

# Spotter "Overwatch" chatter: [seconds after start, line]
var radio_script := [
	[1.0, "OVERWATCH: Vance, comms check. You're sitting forty metres off the wire. Stay low."],
	[7.0, "OVERWATCH: Searchlight in the central tower is on a slow sweep. Time your move between passes."],
	[14.0, "OVERWATCH: Fence is broken dead ahead, right where the old post fell. That's your way in."],
	[21.0, "OVERWATCH: Mud on the access road will slow you down. Use the log stacks for cover."],
]


func _ready() -> void:
	noise.seed = 1337
	noise.frequency = 0.03
	rng.seed = 2026
	_build_environment()
	_build_terrain()
	_build_trees()
	_build_fence()
	_build_tower()
	_build_logs()
	if Engine.is_editor_hint():
		return   # in the editor: show the map only (no player, rain or HUD)
	_build_bounds()
	_spawn_player()
	_build_rain()
	_build_hud()
	if FileAccess.file_exists("res://autotest.on"):
		var tester := Node.new()
		tester.set_script(load("res://scripts/autotest.gd"))
		tester.set("level", self)
		add_child(tester)


func _process(delta: float) -> void:
	_time += delta
	# Searchlight sweep
	search_pivot.rotation.y = sin(_time * 0.35) * 1.3
	if Engine.is_editor_hint():
		return

	# Radio chatter
	if _radio_index < radio_script.size() and _time >= radio_script[_radio_index][0]:
		_say(radio_script[_radio_index][1])
		_radio_index += 1
	if _time > _radio_hide_at:
		hud_radio.modulate.a = move_toward(hud_radio.modulate.a, 0.0, delta * 2.0)

	# Perimeter breach trigger
	if not _breached and player.global_position.z > FENCE_Z + 1.0:
		_breached = true
		hud_objective.text = "OBJECTIVE: Neutralize the guard tower sniper"
		_say("OVERWATCH: You're through. Tower's straight ahead. Take out that sniper.")

	# Mud indicator
	var status := "MUD - movement slowed" if player.in_mud else ""
	hud_alert.text = "SEARCHLIGHT - YOU'VE BEEN SPOTTED" if _is_spotted() else status
	hud_alert.modulate = Color(1, 0.25, 0.2) if _is_spotted() else Color(0.85, 0.75, 0.55)

	var stance_names := ["STANDING", "CROUCHED", "PRONE - press SPACE to stand up"]
	hud_stance.text = "STANCE: " + stance_names[player.stance]
	hud_click.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

	# Diagnostics log (overwritten every 3 s) so problems can be checked from outside
	_log_timer += delta
	if _log_timer > 3.0:
		_log_timer = 0.0
		var f := FileAccess.open("res://play_log.txt", FileAccess.WRITE)
		if f:
			f.store_string("time=%.1f pos=%s stance=%s keys_received=%d mouse_captured=%s window_focused=%s fps=%d\n" % [
				_time, player.global_position, player.stance, player.key_events,
				Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, DisplayServer.window_is_focused(),
				Engine.get_frames_per_second()])
			f.close()


func height_at(x: float, z: float) -> float:
	var slope := 0.0
	var forest := 0.0
	if z < -10.0:
		slope = (-10.0 - z) * 0.18
		forest = clampf((-10.0 - z) / 20.0, 0.0, 1.0)
	var road_flat := clampf((absf(x - ROAD_X) - ROAD_HALF) / 4.0, 0.0, 1.0)
	return slope + noise.get_noise_2d(x, z) * 2.2 * forest * road_flat


func is_mud(pos: Vector3) -> bool:
	return absf(pos.x - ROAD_X) < ROAD_HALF or (absf(pos.x) < 4.0 and absf(pos.z - FENCE_Z) < 4.0)


# ---------------------------------------------------------------- building

func _mat(color: Color, roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _box(size: Vector3, pos: Vector3, material: Material, solid := true) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	if not solid:
		mesh.position = pos
		add_child(mesh)
		return mesh
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(mesh)
	add_child(body)
	return body


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.35, 0.39)
	sky_mat.sky_horizon_color = Color(0.52, 0.55, 0.58)
	sky_mat.ground_horizon_color = Color(0.45, 0.47, 0.49)
	sky_mat.ground_bottom_color = Color(0.2, 0.21, 0.22)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.47, 0.5, 0.53)
	env.fog_density = 0.028
	env.fog_sky_affect = 0.85
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.light_color = Color(0.8, 0.85, 0.9)
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # overcast: no sun disc
	add_child(sun)


func _build_terrain() -> void:
	var spacing := SIZE / float(RES - 1)
	var half := (RES - 1) / 2.0
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in RES:
		for i in RES:
			var x := (i - half) * spacing
			var z := (j - half) * spacing
			var h := height_at(x, z)
			heights[j * RES + i] = h
			var c := Color(0.22, 0.26, 0.16)                      # wet forest floor
			if z > -10.0:
				c = Color(0.33, 0.31, 0.27)                       # gravel yard
			if absf(x - ROAD_X) < ROAD_HALF or (absf(x) < 4.0 and absf(z - FENCE_Z) < 4.0):
				c = Color(0.25, 0.18, 0.11)                       # mud
			st.set_color(c)
			st.set_uv(Vector2(i, j) / 8.0)
			st.add_vertex(Vector3(x, h, z))
	for j in RES - 1:
		for i in RES - 1:
			var a := j * RES + i
			var b := a + 1
			var c2 := a + RES
			var d := c2 + 1
			st.add_index(a); st.add_index(b); st.add_index(c2)
			st.add_index(b); st.add_index(d); st.add_index(c2)
	st.generate_normals()

	var ground_mat := _mat(Color.WHITE, 0.55)   # low roughness = rain-soaked sheen
	ground_mat.vertex_color_use_as_albedo = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = ground_mat

	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(spacing, 1, spacing)

	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.add_child(cs)
	body.add_child(mesh)
	add_child(body)


func _build_trees() -> void:
	var bark := _mat(Color(0.25, 0.18, 0.12))
	var needles := _mat(Color(0.09, 0.2, 0.11))
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-95, 95)
		var z := rng.randf_range(-95, -34)
		if absf(x - ROAD_X) < ROAD_HALF + 2.5:
			continue
		if Vector2(x, z).distance_to(Vector2(0, -45)) < 3.0:   # spawn point
			continue
		if absf(x) < 3.0 and z > -40.0:                           # keep the gap approach clear
			continue
		_add_tree(Vector3(x, height_at(x, z) - 0.2, z), rng.randf_range(10, 17), bark, needles)
		placed += 1
	# Tree line around the yard edges
	for k in 30:
		var side := -1.0 if k % 2 == 0 else 1.0
		var x2 := side * rng.randf_range(65, 95)
		var z2 := rng.randf_range(-10, 95)
		_add_tree(Vector3(x2, height_at(x2, z2) - 0.2, z2), rng.randf_range(10, 17), bark, needles)


func _add_tree(pos: Vector3, h: float, bark: Material, needles: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18
	tm.bottom_radius = 0.35
	tm.height = h
	trunk.mesh = tm
	trunk.material_override = bark
	trunk.position.y = h / 2.0
	body.add_child(trunk)
	for layer in 3:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 2.6 - layer * 0.7
		cm.height = h * 0.35
		cone.mesh = cm
		cone.material_override = needles
		cone.position.y = h * (0.45 + layer * 0.18)
		body.add_child(cone)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = h
	cs.shape = shape
	cs.position.y = h / 2.0
	body.add_child(cs)
	add_child(body)


func _build_fence() -> void:
	var post_mat := _mat(Color(0.45, 0.46, 0.47), 0.5)
	post_mat.metallic = 0.6
	var mesh_mat := _mat(Color(0.6, 0.62, 0.64, 0.35), 0.4)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var x := -99.0
	while x < 99.0:
		var mid := x + 1.5
		var h := height_at(mid, FENCE_Z)
		if absf(x) > GAP_HALF:   # no post in the middle of the broken gap
			_box(Vector3(0.1, 2.6, 0.1), Vector3(x, height_at(x, FENCE_Z) + 1.1, FENCE_Z), post_mat)
		if absf(mid) > GAP_HALF:
			_box(Vector3(3.0, 2.2, 0.05), Vector3(mid, h + 1.2, FENCE_Z), mesh_mat)
		x += 3.0
	# The broken panel, peeled back and lying in the mud
	var broken := _box(Vector3(3.0, 2.2, 0.05), Vector3(0, height_at(0, FENCE_Z + 1.2) + 0.35, FENCE_Z + 1.2), mesh_mat, false)
	broken.rotation_degrees = Vector3(-75, 12, 0)


func _build_tower() -> void:
	var wood := _mat(Color(0.35, 0.27, 0.18))
	var metal := _mat(Color(0.3, 0.31, 0.32), 0.45)
	var p := TOWER_POS
	for sx in [-1.5, 1.5]:
		for sz in [-1.5, 1.5]:
			_box(Vector3(0.3, 9.0, 0.3), p + Vector3(sx, 4.5, sz), wood)
	_box(Vector3(4.2, 0.3, 4.2), p + Vector3(0, 9.0, 0), wood)          # platform
	for s in [-1, 1]:
		_box(Vector3(4.2, 1.0, 0.1), p + Vector3(0, 9.65, s * 2.05), wood)  # rails
		_box(Vector3(0.1, 1.0, 4.2), p + Vector3(s * 2.05, 9.65, 0), wood)
	_box(Vector3(4.8, 0.2, 4.8), p + Vector3(0, 12.0, 0), metal)        # roof
	# Ladder
	for rung in 18:
		_box(Vector3(0.8, 0.06, 0.06), p + Vector3(0, 0.4 + rung * 0.5, 2.2), metal, false)

	# Rotating searchlight
	search_pivot = Node3D.new()
	search_pivot.position = p + Vector3(0, 10.4, 0)
	add_child(search_pivot)
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -14.0
	search_pivot.add_child(tilt)
	var housing := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.35
	hm.bottom_radius = 0.3
	hm.height = 0.7
	housing.mesh = hm
	housing.material_override = metal
	housing.rotation_degrees.x = 90
	tilt.add_child(housing)

	search_light = SpotLight3D.new()
	search_light.light_energy = 10.0
	search_light.light_color = Color(1.0, 0.96, 0.85)
	search_light.spot_range = 70.0
	search_light.spot_angle = 11.0
	search_light.shadow_enabled = true
	tilt.add_child(search_light)

	# Visible beam cutting through the drizzle
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.3
	bm.bottom_radius = tan(deg_to_rad(11.0)) * 55.0
	bm.height = 55.0
	beam.mesh = bm
	var beam_mat := _mat(Color(1, 0.97, 0.85, 0.05))
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.rotation_degrees.x = 90
	beam.position.z = -27.5
	tilt.add_child(beam)


func _build_logs() -> void:
	var log_mat := _mat(Color(0.42, 0.3, 0.19))
	var z := -2.0
	while z < 90.0:
		for side in [-1, 1]:
			if rng.randf() < 0.75:
				var x: float = ROAD_X + side * (ROAD_HALF + 2.5)
				_log_stack(Vector3(x, height_at(x, z), z + rng.randf_range(-2, 2)), log_mat)
		z += 11.0
	# A few stacks between the fence gap and the tower for cover
	_log_stack(Vector3(-4, 0, 2), log_mat)
	_log_stack(Vector3(5, 0, 9), log_mat)


func _log_stack(base: Vector3, material: Material) -> void:
	var r := 0.35
	var length := 6.0
	var body := StaticBody3D.new()
	body.position = base
	body.rotation.y = PI / 2.0      # logs run parallel to the road
	for row in 3:
		var count := 3 - row
		for n in count:
			var offset_x := (n - (count - 1) / 2.0) * r * 2.0
			var pos := Vector3(offset_x, r + row * r * 1.75, 0)
			var m := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = length
			m.mesh = cm
			m.material_override = material
			m.position = pos
			m.rotation_degrees.x = 90
			body.add_child(m)
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = r
			shape.height = length
			cs.shape = shape
			cs.position = pos
			cs.rotation_degrees.x = 90
			body.add_child(cs)
	add_child(body)


func _build_bounds() -> void:
	# Invisible walls at the map edge
	for s in [-1, 1]:
		for sz in [Vector3(1, 60, SIZE), Vector3(SIZE, 60, 1)]:
			var body := StaticBody3D.new()
			body.position = Vector3(s * SIZE / 2.0, 20, 0) if sz.x == 1 else Vector3(0, 20, s * SIZE / 2.0)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = sz
			cs.shape = shape
			body.add_child(cs)
			add_child(body)


func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.name = "Vance"
	player.position = Vector3(0, height_at(0, -45) + 0.3, -45)
	player.rotation.y = PI    # face downhill toward the fence and tower
	add_child(player)
	player.mud_check = is_mud


func _build_rain() -> void:
	var rain := GPUParticles3D.new()
	rain.amount = 3500
	rain.lifetime = 1.2
	rain.local_coords = false
	rain.position = Vector3(0, 12, 0)
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25, 1, 25)
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.015, 0.45)
	var dm := _mat(Color(0.75, 0.8, 0.85, 0.35))
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	rain.draw_pass_1 = drop
	player.add_child(rain)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_objective = _label(layer, "OBJECTIVE: Reach the broken section of the perimeter fence", 20, Color(0.9, 0.9, 0.85))
	hud_objective.position = Vector2(24, 20)
	var hint := _label(layer, "WASD move | Shift sprint | C crouch | Z prone | Space stand/jump | Esc mouse", 14, Color(0.7, 0.7, 0.7))
	hint.position = Vector2(24, 50)
	hud_alert = _label(layer, "", 22, Color.WHITE)
	_place(hud_alert, Control.PRESET_CENTER_TOP, -260, 90, 260, 124)
	hud_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_radio = _label(layer, "", 18, Color(0.55, 0.95, 0.6))
	_place(hud_radio, Control.PRESET_CENTER_BOTTOM, -450, -100, 450, -30)
	hud_radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_radio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_stance = _label(layer, "", 16, Color(0.8, 0.85, 0.9))
	_place(hud_stance, Control.PRESET_BOTTOM_LEFT, 24, -40, 600, -14)
	hud_click = _label(layer, "CLICK HERE TO PLAY", 40, Color(1, 1, 1))
	_place(hud_click, Control.PRESET_CENTER, -300, 40, 300, 100)
	hud_click.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cross := _label(layer, "+", 22, Color(1, 1, 1, 0.7))
	_place(cross, Control.PRESET_CENTER, -10, -16, 10, 16)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _place(c: Control, preset: Control.LayoutPreset, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


func _say(line: String) -> void:
	hud_radio.text = line
	hud_radio.modulate.a = 1.0
	_radio_hide_at = _time + 5.5


func _is_spotted() -> bool:
	var eye: Vector3 = player.eye_position()
	var origin := search_light.global_position
	var to_player := eye - origin
	var dist := to_player.length()
	if dist > search_light.spot_range:
		return false
	# Going prone makes you much harder to pick out at range
	if player.stance == PlayerScript.Stance.PRONE and dist > 25.0:
		return false
	var forward := -search_light.global_transform.basis.z
	if forward.angle_to(to_player) > deg_to_rad(search_light.spot_angle):
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, eye)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == player
