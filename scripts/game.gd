extends Node3D
## THE HORIZON PROTOCOL — main game node.
## Builds the world, spawns Vance, runs the HUD, enemies, checkpoints and atmosphere.

const B := preload("res://scripts/build.gd")
const S := preload("res://scripts/sfx.gd")
const PlayerScript := preload("res://scripts/player.gd")
const WeaponScript := preload("res://scripts/weapon.gd")
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
var intel_found := 0
var intel_total := 0
var _intel_near = null
var weapon_drops: Array = []     # guns lying on the ground (Node3D with meta gun_id / mag)
var _caches_at: Array = []
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
	setup_inputs()
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.use_debanding = true
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
	mission.auto_start = false
	add_child(mission)

	var pause := CanvasLayer.new()
	pause.set_script(PauseScript)
	pause.game = self
	add_child(pause)

	_intro()


const BRIEFING := [
	"THE HORIZON PROTOCOL",
	"KRANOR VALLEY  -  EASTERN BORDER  -  04:52",
	"Vanguard Corp, a private army commanded by General Viktor Raskov, has stolen THE HORIZON PROTOCOL: a military override that can seize control of every allied defence network.",
	"The encrypted launch logs have been traced to a logistics hub hidden in the valley below Timberline Outpost.",
	"Major Elena Vance goes in alone. Her spotter, Sgt. Marcus Reyes, watches from the ridge.",
	"No backup. No extraction until the logs are secured.",
]


func _intro() -> void:
	player.controls_enabled = false
	if OS.get_cmdline_user_args().size() == 0:
		await hud.briefing(BRIEFING)
	player.controls_enabled = true
	hud.fade_to(0.0, 3.0)
	mission.begin()


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


func on_player_shot(pos: Vector3, loud := false) -> void:
	shots_fired += 1
	# Suppressed carbine: only nearby enemies hear it. Captured guns are loud.
	for e in alive_enemies():
		e.hear(pos, 45.0 if loud else 16.0)


func on_enemy_alerted(enemy) -> void:
	for e in alive_enemies():
		if e != enemy and e.global_position.distance_to(enemy.global_position) < 32.0:
			e.alert(player.global_position)
	mission.on_alert(enemy)


## Collectible intel document: walk up and press F to read it
func spawn_intel(pos: Vector3, title: String, body: String) -> void:
	intel_total += 1
	var M := preload("res://scripts/mats.gd")
	var a := Area3D.new()
	a.position = pos
	var shape := SphereShape3D.new()
	shape.radius = 1.6
	B.add_shape(a, shape, Vector3.ZERO)
	const MD := preload("res://scripts/models.gd")
	# Red classified dossier with a cold blue glow and an INTEL tag
	if MD.place(a, "intel_folder", Vector3(0, -0.02, 0), Vector3(0, randf() * 360.0, 0), Vector3.ONE * 1.2) == null:
		B.box(a, Vector3(0.32, 0.03, 0.24), Vector3.ZERO, M.tinted("wood", Color(0.75, 0.6, 0.35)), false)
	B.omni(a, Vector3(0, 0.35, 0), Color(0.45, 0.7, 1.0), 0.9, 2.5)
	var tag := B.label3d(a, "INTEL", Vector3(0, 0.4, 0), 30, Color(0.55, 0.8, 1.0))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visibility_range_end = 10.0
	tag.outline_size = 6
	a.set_meta("title", title)
	a.set_meta("body", body)
	add_child(a)
	a.body_entered.connect(_intel_enter.bind(a))
	a.body_exited.connect(_intel_exit.bind(a))


func _intel_enter(b: Node, a: Area3D) -> void:
	if b == player:
		_intel_near = a


func _intel_exit(b: Node, a: Area3D) -> void:
	if b == player and _intel_near == a:
		_intel_near = null
		hud.prompt("")


func _check_intel() -> void:
	if _intel_near == null or not is_instance_valid(_intel_near):
		return
	hud.prompt("Press  F  to read intel")
	if Input.is_action_just_pressed("interact"):
		intel_found += 1
		hud.show_intel(_intel_near.get_meta("title"), _intel_near.get_meta("body"), intel_found, intel_total)
		S.play2d(self, "beep", -10.0)
		hud.prompt("")
		_intel_near.queue_free()
		_intel_near = null


const AMMO_COLORS := {"5.56": Color(0.35, 0.95, 0.35), "7.62": Color(1.0, 0.65, 0.15), ".308": Color(1.0, 0.25, 0.2), "9mm": Color(0.75, 0.4, 1.0)}


## An ammo pouch. kind "" = ammo for whatever gun the player is holding (supply boxes).
func spawn_ammo(pos: Vector3, kind := "", amount := 30) -> void:
	var a := Area3D.new()
	a.position = pos + Vector3(0.4, 0.15, 0.3)
	var shape := SphereShape3D.new()
	shape.radius = 1.1
	B.add_shape(a, shape, Vector3.ZERO)
	var M := preload("res://scripts/mats.gd")
	const MD := preload("res://scripts/models.gd")
	var c: Color = AMMO_COLORS.get(kind, Color(0.32, 0.36, 0.25))
	# Arcade-style ammo pickup: a colour-coded ammo can that floats, spins and glows (colour = calibre)
	var holder := Node3D.new()
	a.add_child(holder)
	var can_tint := c.lerp(Color(0.3, 0.33, 0.24), 0.45)
	if MD.place(holder, "ammo_can", Vector3(0, -0.12, 0), Vector3.ZERO, Vector3.ONE * 1.4, can_tint) == null:
		B.box(holder, Vector3(0.3, 0.16, 0.2), Vector3.ZERO, M.tinted("uniform", c), false)
	B.omni(a, Vector3(0, 0.25, 0), c, 1.2, 2.2)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.32
	tm.outer_radius = 0.36
	ring.mesh = tm
	ring.material_override = M.emissive(c, 3.0)
	ring.position = Vector3(0, -0.13, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(ring)
	var spin := holder.create_tween().set_loops()
	spin.tween_property(holder, "rotation:y", TAU, 2.5).from(0.0)
	var bob := holder.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(holder, "position:y", 0.12, 0.8).from(0.0)
	bob.tween_property(holder, "position:y", 0.0, 0.8)
	var tag := B.label3d(a, ("AMMO  " + kind) if kind != "" else "AMMO", Vector3(0, 0.5, 0), 28, c.lightened(0.3))
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visibility_range_end = 12.0
	tag.outline_size = 6
	add_child(a)
	a.body_entered.connect(func(b):
		if b == player and is_instance_valid(a):
			var k: String = kind if kind != "" else player.weapon.ammo_type()
			if k == "":
				k = "5.56"
			player.weapon.add_ammo(k, amount)
			hud.hint("+%d  %s AMMO" % [amount, k], 1.4)
			S.play2d(self, "reload", -12.0)
			a.queue_free())


## Supply cache at a checkpoint: carbine + pistol ammo
func spawn_supply_cache(pos: Vector3) -> void:
	for c in _caches_at:
		if (c as Vector3).distance_to(pos) < 20.0:
			return
	_caches_at.append(pos)
	spawn_ammo(pos + Vector3(1.0, 0.0, 0.6), "5.56", 60)
	spawn_ammo(pos + Vector3(1.4, 0.0, 0.2), "9mm", 30)


## A gun lying on the ground that the player can pick up (F)
func spawn_weapon_drop(gun_id: String, pos: Vector3, mag: int) -> void:
	const MD := preload("res://scripts/models.gd")
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	root.set_meta("gun_id", gun_id)
	root.set_meta("mag", mag)
	var g := MD.place(root, String(WeaponScript.GUNS[gun_id]["model"]), Vector3.ZERO)
	if g:
		g.rotation_degrees = Vector3(0, randf() * 360.0, 90)   # lying on its side
	# settle it on the ground
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.0, 0), pos + Vector3(0, -6.0, 0))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		root.global_position = hit.position + Vector3(0, 0.05, 0)
	# faint glint so it can be spotted
	B.omni(root, Vector3(0, 0.4, 0), Color(1, 0.85, 0.5), 0.6, 2.0)
	weapon_drops.append(root)


func on_enemy_killed(enemy, headshot: bool) -> void:
	kills += 1
	# They drop their gun and a pouch of ammo for it
	var gid: String = enemy.weapon_id()
	var gpos: Vector3 = enemy.global_position + Vector3(0, 0.5, 0)
	if enemy.gun_node and is_instance_valid(enemy.gun_node):
		gpos = enemy.gun_node.global_position
		enemy.gun_node.visible = false
	spawn_weapon_drop(gid, gpos + enemy.global_transform.basis.x * 0.4, randi_range(6, int(WeaponScript.GUNS[gid]["mag"])))
	spawn_ammo(enemy.global_position, String(WeaponScript.GUNS[gid]["ammo"]), 10 if gid == "dmr" else 20)
	if randf() < 0.3:
		spawn_ammo(enemy.global_position + Vector3(-0.6, 0, 0.2), "9mm", 15)
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


var _indoor_t := 0.0
var clouds: MeshInstance3D
var _rain_on := true


func _process(delta: float) -> void:
	play_time += delta
	_check_intel()
	if clouds and player:
		clouds.global_position = Vector3(player.global_position.x, player.global_position.y + 95.0, player.global_position.z)
	# No rain under roofs: check what is above Vance's head a few times a second
	_indoor_t -= delta
	if _indoor_t <= 0.0 and player and rain:
		_indoor_t = 0.2
		var from: Vector3 = player.global_position + Vector3(0, 2.0, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, 25, 0))
		q.exclude = [player.get_rid()]
		var covered := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
		rain.amount_ratio = 0.0 if (covered or not _rain_on) else 1.0
		if _amb_rain:
			_amb_rain.volume_db = -80.0 if not _rain_on else (-26.0 if covered else -14.0)


func drive_secured() -> void:
	S.play2d(self, "beep", 0.0)


## Final scene: the helicopter has landed; fade out to the epilogue and credits
func finish_game() -> void:
	player.controls_enabled = false
	await get_tree().create_timer(5.0).timeout
	hud.fade_to(1.0, 2.5)
	await get_tree().create_timer(2.8).timeout
	var mins := int(play_time / 60.0)
	var secs := int(play_time) % 60
	var acc := 0
	if shots_fired > 0:
		acc = int(100.0 * float(kills * 3) / float(shots_fired))
	hud.end_card("MISSION COMPLETE", "THE HORIZON PROTOCOL\n\nThe Horizon Protocol was recovered at 06:31.\nWithout Raskov, the Vanguard Corp network collapsed within the week.\nMajor Elena Vance and Sgt. Marcus Reyes were extracted from Site 9 by Nightingale 2-1.\nThe buyer, known only as 'H', was never found.\n\nTime  %d:%02d      Kills  %d      Headshots  %d      Intel  %d / %d\n\n- - -\n\nA game by Tanmay\nBuilt in Godot with Claude\n\nThanks for playing." % [mins, secs, kills, headshots, intel_found, intel_total])


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
		spawn_supply_cache(pos)
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
	env.fog_density = 0.011
	env.fog_sky_affect = 0.9
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.8, 0.82, 0.85)
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.0
	env.ssr_enabled = true            # wet reflections on puddles, asphalt and metal
	env.ssr_max_steps = 48
	env.ssil_enabled = true
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
	# Overcast cloud layer that drifts slowly (follows Vance so it never ends)
	var M := preload("res://scripts/mats.gd")
	if M.tex("clouds_albedo") != null:
		clouds = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1400, 1400)
		clouds.mesh = pm
		var cm := ShaderMaterial.new()
		cm.shader = load("res://shaders/clouds.gdshader")
		cm.set_shader_parameter("clouds", M.tex("clouds_albedo"))
		clouds.material_override = cm
		clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clouds.position = Vector3(0, 95, 0)
		add_child(clouds)

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
			tw.tween_property(env, "fog_density", 0.011, 3.0)
			tw.tween_property(env, "ambient_light_energy", 0.75, 3.0)
		"yard":
			tw.tween_property(env, "fog_density", 0.009, 4.0)
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
	_rain_on = mode in ["forest", "yard", "blackout", "mountain"]


# ------------------------------------------------------------------ input map

func setup_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "prone": [KEY_Z],
		"jump": [KEY_SPACE], "lean_left": [KEY_Q], "lean_right": [KEY_E],
		"interact": [KEY_F], "reload": [KEY_R],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "toggle_view": [KEY_V],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	# Trackpad-friendly: X also aims (hold)
	if not InputMap.has_action("aim"):
		InputMap.add_action("aim")
	var xk := InputEventKey.new()
	xk.physical_keycode = KEY_X
	InputMap.action_add_event("aim", xk)
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)
