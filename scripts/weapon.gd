extends Node3D
## Vance's suppressed carbine (first-person viewmodel + shooting).

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")

const MAG_SIZE := 30
const FIRE_INTERVAL := 0.09
const RELOAD_TIME := 2.1
const DAMAGE := 34.0
const RANGE := 250.0
const HIP_POS := Vector3(0.2, -0.205, -0.38)
const ADS_POS := Vector3(0.0, -0.0664, -0.27)
const SPRINT_POS := Vector3(0.12, -0.24, -0.3)

var player
var model: Node3D
var muzzle: Node3D
var flash_light: OmniLight3D
var flash_mesh: MeshInstance3D
var ammo := MAG_SIZE
var reserve := 150
var reloading := false
var spread := 0.0

var _cooldown := 0.0
var _reload_t := 0.0
var _sway := Vector2.ZERO
var _kick := 0.0
var _flash_t := 0.0
var _bob := 0.0
var _mud_spots: Array = []
var _holes: Array = []
var _ads_blend := 0.0


func _ready() -> void:
	model = Node3D.new()
	model.position = HIP_POS
	model.scale = Vector3.ONE * 0.82
	add_child(model)
	var metal := M.get_mat("gun_metal")
	var poly := M.get_mat("gun_polymer")
	var glove := M.get_mat("gear")
	var parts: Array = [
		B.box(model, Vector3(0.058, 0.08, 0.32), Vector3(0, 0, 0), metal, false),
		B.box(model, Vector3(0.056, 0.062, 0.26), Vector3(0, -0.003, -0.29), poly, false),
		B.cyl(model, 0.012, 0.012, 0.12, Vector3(0, 0.006, -0.47), metal, false, Vector3(90, 0, 0), 10),
		B.cyl(model, 0.021, 0.021, 0.19, Vector3(0, 0.006, -0.62), metal, false, Vector3(90, 0, 0), 12),
		B.box(model, Vector3(0.034, 0.15, 0.068), Vector3(0, -0.105, -0.05), poly, false, Vector3(12, 0, 0)),
		B.box(model, Vector3(0.034, 0.1, 0.042), Vector3(0, -0.085, 0.1), poly, false, Vector3(-18, 0, 0)),
		B.box(model, Vector3(0.048, 0.07, 0.2), Vector3(0, -0.012, 0.27), poly, false),
		B.box(model, Vector3(0.022, 0.012, 0.3), Vector3(0, 0.046, -0.1), metal, false),   # top rail
		B.box(model, Vector3(0.03, 0.012, 0.07), Vector3(0, 0.058, -0.03), metal, false),   # optic base
		B.box(model, Vector3(0.04, 0.004, 0.03), Vector3(0, 0.099, -0.05), metal, false),   # optic hood top
		B.box(model, Vector3(0.004, 0.04, 0.03), Vector3(-0.02, 0.08, -0.05), metal, false),
		B.box(model, Vector3(0.004, 0.04, 0.03), Vector3(0.02, 0.08, -0.05), metal, false),
		B.box(model, Vector3(0.04, 0.004, 0.03), Vector3(0, 0.063, -0.05), metal, false),   # optic bottom
		B.box(model, Vector3(0.075, 0.055, 0.11), Vector3(-0.005, -0.045, -0.3), glove, false),  # left hand
		B.box(model, Vector3(0.06, 0.06, 0.08), Vector3(0.012, -0.075, 0.09), glove, false),     # right hand
	]
	for p in parts:
		(p as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Red dot
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0016
	sm.height = 0.0032
	dot.mesh = sm
	dot.material_override = M.emissive(Color(1, 0.1, 0.05), 6.0)
	dot.position = Vector3(0, 0.081, -0.05)
	model.add_child(dot)

	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.006, -0.72)
	model.add_child(muzzle)
	flash_light = B.omni(muzzle, Vector3.ZERO, Color(1, 0.75, 0.4), 0.0, 6.0)
	var fm := QuadMesh.new()
	fm.size = Vector2(0.09, 0.09)
	flash_mesh = B.mesh(muzzle, fm, Vector3(0, 0, -0.03), M.emissive(Color(1, 0.7, 0.3), 4.0), Vector3.ZERO, false)
	var fmat: StandardMaterial3D = flash_mesh.material_override.duplicate()
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(1, 0.7, 0.3, 0.8)
	flash_mesh.material_override = fmat
	flash_mesh.visible = false


func ads_fov() -> float:
	return 52.0


func refill() -> void:
	ammo = MAG_SIZE
	reserve = max(reserve, 120)
	reloading = false


func add_sway(rel: Vector2) -> void:
	_sway += rel * 0.00012 * (0.3 if player.aiming else 1.0)
	_sway = _sway.limit_length(0.05)


func add_mud() -> void:
	if _mud_spots.size() > 16:
		return
	var q := QuadMesh.new()
	var s := randf_range(0.01, 0.028)
	q.size = Vector2(s, s * randf_range(0.6, 1.2))
	var mat: StandardMaterial3D = M.get_mat("mud").duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spot := MeshInstance3D.new()
	spot.mesh = q
	spot.material_override = mat
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stick it on the right side / top of the receiver and handguard
	var side := randi() % 2
	if side == 0:
		spot.position = Vector3(0.03, randf_range(-0.03, 0.03), randf_range(-0.4, 0.1))
		spot.rotation_degrees = Vector3(0, 90, randf() * 360)
	else:
		spot.position = Vector3(randf_range(-0.02, 0.02), 0.041, randf_range(-0.4, 0.1))
		spot.rotation_degrees = Vector3(-90, 0, randf() * 360)
	model.add_child(spot)
	_mud_spots.append({"node": spot, "life": 40.0})


func _process(delta: float) -> void:
	if player == null:
		return
	_cooldown -= delta
	var can_act: bool = player.controls_enabled and not player.is_dead

	# Reload
	if reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			var need := MAG_SIZE - ammo
			var take: int = min(need, reserve)
			ammo += take
			reserve -= take
			reloading = false
	elif can_act and Input.is_action_just_pressed("reload") and ammo < MAG_SIZE and reserve > 0:
		_start_reload()

	# Fire
	if can_act and not reloading and Input.is_action_pressed("fire") and not player.sprinting:
		if _cooldown <= 0.0:
			if ammo > 0:
				_fire()
			elif Input.is_action_just_pressed("fire"):
				S.play2d(self, "empty", -6.0)
				if reserve > 0:
					_start_reload()

	# Spread: grows while moving / firing, shrinks when aiming
	var move_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var base_spread := 0.8 + move_speed * 0.35
	if player.stance == 1:
		base_spread *= 0.7
	elif player.stance == 2:
		base_spread *= 0.45
	if player.aiming:
		base_spread *= 0.12
	spread = lerpf(spread, base_spread, clampf(8.0 * delta, 0.0, 1.0))

	# Viewmodel pose
	_ads_blend = lerpf(_ads_blend, 1.0 if player.aiming else 0.0, clampf(14.0 * delta, 0.0, 1.0))
	var target := HIP_POS.lerp(ADS_POS, _ads_blend)
	var rot := Vector3.ZERO
	if player.sprinting and move_speed > 3.0:
		target = SPRINT_POS
		rot = Vector3(-12, 35, 8)
	if reloading:
		var t := 1.0 - _reload_t / RELOAD_TIME
		var dip := sin(t * PI)
		target += Vector3(0, -0.08, 0.04) * dip
		rot += Vector3(-25, 10, 30) * dip
	_bob += delta * move_speed * 1.8
	var bob_amt := clampf(move_speed / 4.0, 0.0, 1.4) * (1.0 - _ads_blend * 0.85)
	target += Vector3(sin(_bob) * 0.008, absf(cos(_bob)) * 0.01, 0) * bob_amt
	_sway = _sway.lerp(Vector2.ZERO, clampf(6.0 * delta, 0.0, 1.0))
	target += Vector3(-_sway.x, _sway.y, 0)
	_kick = lerpf(_kick, 0.0, clampf(16.0 * delta, 0.0, 1.0))
	target.z += _kick * 0.05
	rot.x += _kick * 4.0
	model.position = model.position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	model.rotation_degrees = model.rotation_degrees.lerp(rot, clampf(12.0 * delta, 0.0, 1.0))

	# Muzzle flash
	_flash_t -= delta
	flash_mesh.visible = _flash_t > 0.0
	flash_light.light_energy = 1.6 if _flash_t > 0.0 else 0.0

	# Mud washes off slowly in the rain
	for i in range(_mud_spots.size() - 1, -1, -1):
		var m: Dictionary = _mud_spots[i]
		m.life -= delta
		var mat: StandardMaterial3D = m.node.material_override
		mat.albedo_color.a = clampf(m.life / 10.0, 0.0, 1.0)
		if m.life <= 0.0:
			m.node.queue_free()
			_mud_spots.remove_at(i)


func _start_reload() -> void:
	reloading = true
	_reload_t = RELOAD_TIME
	S.play2d(self, "reload", -6.0)


func _fire() -> void:
	ammo -= 1
	_cooldown = FIRE_INTERVAL
	_kick = 1.0
	_flash_t = 0.04
	S.play2d(self, "rifle", -3.0)
	var r: float = randf_range(0.9, 1.25) * (0.55 if player.aiming else 1.0)
	player.add_recoil(r, randf_range(-0.35, 0.35))
	if player.game:
		player.game.on_player_shot(player.global_position)

	var cam: Camera3D = player.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var spread_rad := deg_to_rad(spread)
	var dir := (fwd + cam.global_transform.basis.x * randf_range(-1, 1) * spread_rad * 0.5 + cam.global_transform.basis.y * randf_range(-1, 1) * spread_rad * 0.5).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * RANGE
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c and c.has_method("take_hit"):
			c.take_hit(DAMAGE, hit.position, dir)
			if player.game:
				player.game.hud.hitmarker()
		elif c and c.has_method("on_shot"):
			c.on_shot(hit.position)
		else:
			_impact(hit.position, hit.normal)
	_tracer(muzzle.global_position, end)


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var host := get_tree().current_scene
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, minf(length, 12.0))
	t.mesh = bm
	var mat := M.emissive(Color(1.0, 0.8, 0.5), 3.0).duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.5
	t.material_override = mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(t)
	var mid := from.lerp(to, minf(6.0, length * 0.5) / length)
	t.global_position = mid
	t.look_at_from_position(mid, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := t.create_tween()
	tw.tween_property(t, "global_position", to, 0.06)
	tw.tween_callback(t.queue_free)


func _impact(pos: Vector3, normal: Vector3) -> void:
	var host := get_tree().current_scene
	# Dirt / spark puff
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9, 0)
	var pm := BoxMesh.new()
	pm.size = Vector3(0.02, 0.02, 0.02)
	p.mesh = pm
	p.material_override = M.get_mat("mud")
	host.add_child(p)
	p.global_position = pos
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	# Bullet hole
	var hole := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	hole.mesh = q
	hole.material_override = M.get_mat("black")
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(hole)
	hole.global_position = pos + normal * 0.01
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	hole.look_at(pos + normal * 2.0, up)
	hole.rotate_object_local(Vector3.UP, PI)
	_holes.append(hole)
	if _holes.size() > 80:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	S.play3d(self, "impact", pos, -10.0)
