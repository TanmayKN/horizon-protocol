extends Node3D
## THE HORIZON PROTOCOL — main game node.
## Builds the world, spawns Vance, runs the HUD, enemies, checkpoints and atmosphere.

const B := preload("res://scripts/build.gd")
const S := preload("res://scripts/sfx.gd")
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const HudScript := preload("res://scripts/hud.gd")
const MissionScript := preload("res://scripts/mission.gd")
const PauseScript := preload("res://scripts/pause_menu.gd")
const TerrainScript := preload("res://scripts/world/terrain.gd")
const Seg1Script := preload("res://scripts/world/seg1_timberline.gd")
const Seg2Script := preload("res://scripts/world/seg2_kranor.gd")
const Seg4Script := preload("res://scripts/world/seg4_pass.gd")
const Seg5Script := preload("res://scripts/world/seg5_bunker.gd")

const START_POS := Vector3(0, 0, -52)

var player
var hud
var mission
var terrain
var seg1
var seg2
var seg4
var seg5
var kills := 0
var headshots := 0
var shots_fired := 0
var play_time := 0.0
var enemies: Array = []
var env: Environment
var sun: DirectionalLight3D
var rain: GPUParticles3D
var checkpoint_pos := START_POS
var checkpoint_yaw := PI
var god_mode := false
var difficulty_mult := 1.0
var mouse_sens_mult := 1.0
var extra_surfaces: Array = []   # Callables returning "" or a surface name
var _amb_rain: AudioStreamPlayer
var _amb_wind: AudioStreamPlayer


func _ready() -> void:
	_setup_inputs()
	_build_environment()

	terrain = Node3D.new()
	terrain.set_script(TerrainScript)
	terrain.name = "Terrain"
	add_child(terrain)

	seg1 = Node3D.new()
	seg1.set_script(Seg1Script)
	seg1.name = "Seg1_Timberline"
	seg1.game = self
	seg1.terrain = terrain
	add_child(seg1)

	seg2 = Node3D.new()
	seg2.set_script(Seg2Script)
	seg2.name = "Seg2_Kranor"
	seg2.game = self
	add_child(seg2)
	extra_surfaces.append(seg2.surface_at)

	seg4 = Node3D.new()
	seg4.set_script(Seg4Script)
	seg4.name = "Seg4_Pass"
	seg4.game = self
	add_child(seg4)

	seg5 = Node3D.new()
	seg5.set_script(Seg5Script)
	seg5.name = "Seg5_Bunker"
	seg5.game = self
	add_child(seg5)
	extra_surfaces.append(seg5.surface_at)
	seg4.visible = false
	seg5.visible = false
	for seg in [seg1, seg2, seg4, seg5]:
		_optimize(seg)

	hud = CanvasLayer.new()
	hud.set_script(HudScript)
	hud.game = self
	add_child(hud)

	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	player.name = "Vance"
	player.game = self
	player.surface_check = surface_at
	add_child(player)
	checkpoint_pos = START_POS + Vector3(0, terrain.height_at(START_POS.x, START_POS.z) + 0.2, 0)
	player.global_position = checkpoint_pos
	player.rotation.y = checkpoint_yaw
	player.died.connect(_on_player_died)

	_build_rain()
	_amb_rain = S.loop2d(self, "rain", -14.0)
	_amb_wind = S.loop2d(self, "wind", -20.0)

	mission = Node.new()
	mission.set_script(MissionScript)
	mission.game = self
	add_child(mission)

	var pause := CanvasLayer.new()
	pause.set_script(PauseScript)
	pause.game = self
	add_child(pause)

	hud.fade_to(0.0, 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F9:
				mission.skip()
			KEY_F8:
				god_mode = not god_mode
				hud.hint("God mode " + ("ON" if god_mode else "OFF"))


## Distance culling: fog hides far objects anyway, so don't draw them.
## Small props get a shorter draw distance and no shadows.
func _optimize(root_node: Node) -> void:
	for n in root_node.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g is MultiMeshInstance3D:
			continue
		var size := 0.0
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			size = (g as MeshInstance3D).mesh.get_aabb().size.length() * g.global_transform.basis.get_scale().length() / 1.7
		if size < 1.2:
			g.visibility_range_end = 40.0
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif size < 5.0:
			g.visibility_range_end = 85.0
		else:
			g.visibility_range_end = 150.0
		g.visibility_range_end_margin = 8.0


# ------------------------------------------------------------------ queries

func surface_at(pos: Vector3) -> String:
	for c in extra_surfaces:
		var s: String = c.call(pos)
		if s != "":
			return s
	return terrain.surface_at(pos)


func player_in_light() -> bool:
	return seg1 != null and seg1.in_light(player.eye_position())


func max_awareness() -> float:
	var m := 0.0
	for e in enemies:
		if is_instance_valid(e) and not e.dead():
			m = maxf(m, e.awareness)
	return m


func alive_enemies() -> Array:
	return enemies.filter(func(e): return is_instance_valid(e) and not e.dead())


# ------------------------------------------------------------------ enemies

func spawn_enemy(pos: Vector3, patrol: Array = [], sniper := false, stationary := false, yaw := 0.0, name_tag := "Tango"):
	var e := CharacterBody3D.new()
	e.set_script(EnemyScript)
	e.game = self
	e.player = player
	e.patrol = patrol
	e.is_sniper = sniper
	e.stationary = stationary or sniper
	e.callsign = name_tag
	add_child(e)
	e.global_position = pos
	e.rotation.y = yaw
	enemies.append(e)
	return e


func on_player_shot(pos: Vector3) -> void:
	shots_fired += 1
	# Suppressed carbine: only nearby enemies hear it
	for e in alive_enemies():
		e.hear(pos, 16.0)


func on_enemy_alerted(enemy) -> void:
	for e in alive_enemies():
		if e != enemy and e.global_position.distance_to(enemy.global_position) < 32.0:
			e.alert(player.global_position)
	mission.on_alert(enemy)


func on_enemy_killed(enemy, headshot: bool) -> void:
	kills += 1
	if headshot:
		headshots += 1
		hud.hint("HEADSHOT", 1.2)
	# Nearby enemies who see the body become suspicious
	for e in alive_enemies():
		if e.global_position.distance_to(enemy.global_position) < 14.0:
			e.hear(enemy.global_position, 14.0)
	mission.on_enemy_killed(enemy)


# ------------------------------------------------------------------ segments

func start_segment4() -> void:
	seg4.visible = true
	seg5.visible = true
	seg4.start(player.global_position)


func _process(delta: float) -> void:
	play_time += delta


func drive_secured() -> void:
	player.controls_enabled = false
	S.play2d(self, "beep", 0.0)
	mission.say("Vance", "Overwatch, I have the Horizon Protocol. Raskov is finished.", 0.0, true)
	mission.say("Overwatch (Sgt. Reyes)", "Copy that, Major. ...Extraction is inbound. Let's go home.")
	await get_tree().create_timer(6.0).timeout
	hud.fade_to(1.0, 2.5)
	await get_tree().create_timer(2.6).timeout
	var mins := int(play_time) / 60
	var secs := int(play_time) % 60
	var acc := 0.0
	hud.end_card("MISSION COMPLETE", "THE HORIZON PROTOCOL\n\nTime  %d:%02d      Kills  %d      Headshots  %d      Shots fired  %d\n\nThanks for playing!\nA game by Tanmay" % [mins, secs, kills, headshots, shots_fired])


## Short slow-motion moment (used for the final breach)
func slow_motion(scale: float, real_seconds: float) -> void:
	Engine.time_scale = scale
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ checkpoints

func set_checkpoint(pos: Vector3, yaw: float, announce := true) -> void:
	checkpoint_pos = pos
	checkpoint_yaw = yaw
	if announce:
		hud.hint("CHECKPOINT", 2.0)


func _on_player_died() -> void:
	hud.fade_to(1.0, 1.4)
	hud.hint("VANCE IS DOWN", 3.0)
	await get_tree().create_timer(2.8).timeout
	for e in alive_enemies():
		e.reset_alert()
	if mission.step.begins_with("s4") and seg4.active:
		player.respawn(seg4.bed_anchor.global_position, player.rotation.y)
		seg4.rewind()
	else:
		player.respawn(checkpoint_pos, checkpoint_yaw)
	mission.on_respawn()
	hud.fade_to(0.0, 1.2)


# ------------------------------------------------------------------ atmosphere

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.26, 0.29, 0.33)
	sky_mat.sky_horizon_color = Color(0.46, 0.49, 0.52)
	sky_mat.ground_horizon_color = Color(0.4, 0.42, 0.44)
	sky_mat.ground_bottom_color = Color(0.16, 0.17, 0.18)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.45, 0.48)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.9
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.82
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_energy = 0.3
	sun.light_color = Color(0.78, 0.84, 0.92)
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.shadow_blur = 2.5
	sun.light_angular_distance = 4.0
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)


func _build_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 5000
	rain.lifetime = 1.1
	rain.local_coords = false
	rain.position = Vector3(0, 11, 0)
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 17.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	rain.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.42)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.72, 0.77, 0.82, 0.22)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	drop.material = dm
	rain.draw_pass_1 = drop
	player.add_child(rain)


## Change the mood for each segment
func set_atmosphere(mode: String) -> void:
	var tw := create_tween().set_parallel(true)
	match mode:
		"forest":
			tw.tween_property(env, "fog_density", 0.018, 3.0)
			tw.tween_property(env, "ambient_light_energy", 0.75, 3.0)
		"yard":
			tw.tween_property(env, "fog_density", 0.012, 4.0)
			tw.tween_property(env, "ambient_light_energy", 0.6, 4.0)
		"blackout":
			tw.tween_property(env, "ambient_light_energy", 0.08, 0.3)
			tw.tween_property(sun, "light_energy", 0.05, 0.3)
		"mountain":
			tw.tween_property(env, "fog_density", 0.01, 3.0)
			tw.tween_property(env, "ambient_light_energy", 0.8, 3.0)
			tw.tween_property(sun, "light_energy", 0.4, 3.0)
		"bunker":
			tw.tween_property(env, "fog_density", 0.004, 1.0)
			tw.tween_property(env, "ambient_light_energy", 0.25, 1.0)
			tw.tween_property(sun, "light_energy", 0.0, 1.0)
	if rain:
		rain.emitting = mode in ["forest", "yard", "blackout", "mountain"]
	if _amb_rain:
		_amb_rain.volume_db = -14.0 if rain.emitting else -80.0


# ------------------------------------------------------------------ input map

func _setup_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "prone": [KEY_Z],
		"jump": [KEY_SPACE], "lean_left": [KEY_Q], "lean_right": [KEY_E],
		"interact": [KEY_F], "reload": [KEY_R],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)
