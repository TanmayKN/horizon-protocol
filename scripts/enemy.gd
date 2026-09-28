extends CharacterBody3D
## Vanguard Corp soldier AI: patrol -> suspicious -> combat -> dead.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const MD := preload("res://scripts/models.gd")

enum State { PATROL, SUSPICIOUS, SEARCH, COMBAT, DEAD }

signal died(enemy)

var game
var player
var patrol: Array = []          # Array of Vector3 waypoints
var is_sniper := false
var stationary := false
var health := 100.0
var armor := 1.0            # damage multiplier (bosses wear body armour)
var headshot_mult := 4.0
var state: State = State.PATROL
var awareness := 0.0            # 0..1 (1 = fully alerted)
var view_range := 42.0
var callsign := "Tango"
var gun_node: Node3D

var body: Node3D
var arm_r: Node3D
var gun_tip: Node3D
var laser: MeshInstance3D
var _wp := 0
var _wait := 0.0
var _think := 0.0
var _last_seen := Vector3.ZERO
var _sees_player := false
var _burst_left := 0
var _shot_timer := 1.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _aim_time := 0.0
var _search_timer := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _flash: OmniLight3D
# --- tactics (cover, peeking, flanking, grenades)
var _cap: CapsuleShape3D
var _cap_node: CollisionShape3D
var _cover = null           # Vector3 cover spot or null
var _cover_t := 0.0
var _cover_check := 0.0
var _crouch := 0.0          # 0 standing .. 1 crouched (visual + hitbox)
var _want_crouch := false
var _peek_t := 0.0
var _flank_target = null
var _grenades := 1
var _unseen_t := 0.0
var tactics := false        # cover/flank/grenade AI (off: Tanmay prefers the original enemies)
static var _last_grenade := -100.0
static var _last_flank := -100.0
const Grenade := preload("res://scripts/grenade.gd")


func _ready() -> void:
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.35
	_cap.height = 1.8
	_cap_node = B.add_shape(self, _cap, Vector3(0, 0.9, 0))
	_build_model()
	if is_sniper:
		view_range = 38.0
		health = 80.0


var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var torso: Node3D
var head_node: Node3D
var _walk := 0.0


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 4
	return B.mesh(parent, cm, pos, mat, rot)


var _torso_base := Vector3.ZERO


func _build_model() -> void:
	var model_name := "soldier"
	if callsign == "Raskov":
		model_name = "raskov"
	elif callsign == "Hale":
		model_name = "hale"
	if MD.available(model_name):
		_build_blender_model(model_name)
		return
	body = Node3D.new()
	add_child(body)
	var uni := M.get_mat("uniform")
	var gear := M.get_mat("gear")
	var metal := M.get_mat("gun_metal")
	var boot := M.tinted("gear", Color(0.5, 0.45, 0.4))
	# Legs (hip -> knee -> boot), pivoting at the hips so they can walk
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.11 * side, 0.92, 0)
		body.add_child(hip)
		_capsule(hip, 0.085, 0.5, Vector3(0, -0.22, 0), uni)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.45, 0)
		hip.add_child(knee)
		_capsule(knee, 0.075, 0.48, Vector3(0, -0.2, 0), uni)
		B.box(knee, Vector3(0.12, 0.1, 0.26), Vector3(0, -0.42, -0.04), boot, false)
		B.box(knee, Vector3(0.1, 0.1, 0.06), Vector3(0, -0.02, -0.07), gear, false)   # knee pad
		if side < 0:
			leg_l = hip
			shin_l = knee
		else:
			leg_r = hip
			shin_r = knee
	B.box(body, Vector3(0.36, 0.2, 0.24), Vector3(0, 0.92, 0), uni, false)     # pelvis
	B.box(body, Vector3(0.38, 0.06, 0.26), Vector3(0, 1.0, 0), gear, false)    # belt
	torso = Node3D.new()
	torso.position = Vector3(0, 0.95, 0)
	body.add_child(torso)
	_capsule(torso, 0.19, 0.62, Vector3(0, 0.3, 0), uni)
	B.box(torso, Vector3(0.44, 0.42, 0.3), Vector3(0, 0.36, 0), gear, false)          # plate carrier
	for i in 3:
		B.box(torso, Vector3(0.09, 0.13, 0.07), Vector3(-0.12 + i * 0.12, 0.26, -0.18), M.tinted("gear", Color(0.8, 0.85, 0.7)), false)   # mag pouches
	B.box(torso, Vector3(0.34, 0.42, 0.16), Vector3(0, 0.36, 0.23), M.tinted("uniform", Color(0.8, 0.8, 0.75)), false)   # backpack
	B.box(torso, Vector3(0.05, 0.25, 0.04), Vector3(0.15, 0.62, -0.12), metal, false)  # radio antenna base
	B.cyl(torso, 0.006, 0.006, 0.5, Vector3(0.16, 0.9, 0.18), metal, false, Vector3.ZERO, 4)
	head_node = Node3D.new()
	head_node.position = Vector3(0, 0.72, 0)
	torso.add_child(head_node)
	var face := B.mesh(head_node, SphereMesh.new(), Vector3(0, 0.02, 0), M.tinted("gear", Color(0.3, 0.28, 0.25)))   # balaclava
	face.scale = Vector3(0.2, 0.24, 0.21)
	var helm := SphereMesh.new()
	helm.radius = 0.135
	helm.height = 0.17
	helm.is_hemisphere = true
	B.mesh(head_node, helm, Vector3(0, 0.06, 0.01), M.tinted("uniform", Color(0.9, 0.9, 0.85)))
	B.box(head_node, Vector3(0.28, 0.02, 0.29), Vector3(0, 0.055, 0.01), M.tinted("uniform", Color(0.8, 0.8, 0.75)), false)   # helmet rim
	B.box(head_node, Vector3(0.14, 0.05, 0.06), Vector3(0, 0.09, -0.14), metal, false)   # NVG mount
	B.box(head_node, Vector3(0.1, 0.02, 0.01), Vector3(0, 0.02, -0.108), M.emissive(Color(0.3, 1.0, 0.4), 2.0), false)   # goggle glow
	# Arms holding the rifle
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.24, 0.58, 0)
	torso.add_child(arm_r)
	_capsule(arm_r, 0.065, 0.4, Vector3(0, -0.12, -0.08), uni, Vector3(-50, 0, 0))
	_capsule(arm_r, 0.06, 0.36, Vector3(-0.06, -0.24, -0.3), uni, Vector3(-80, 25, 0))
	var arm_l := Node3D.new()
	arm_l.position = Vector3(-0.24, 0.58, 0)
	torso.add_child(arm_l)
	_capsule(arm_l, 0.065, 0.4, Vector3(0, -0.12, -0.12), uni, Vector3(-60, 0, 0))
	_capsule(arm_l, 0.06, 0.38, Vector3(0.12, -0.2, -0.42), uni, Vector3(-85, -40, 0))
	var gun := Node3D.new()
	gun.position = Vector3(0.05, 0.36, -0.42)
	torso.add_child(gun)
	B.box(gun, Vector3(0.055, 0.09, 0.62), Vector3.ZERO, metal, false)
	B.box(gun, Vector3(0.04, 0.15, 0.06), Vector3(0, -0.1, -0.02), metal, false)
	B.box(gun, Vector3(0.045, 0.06, 0.2), Vector3(0, -0.02, 0.36), M.get_mat("gun_polymer"), false)
	if is_sniper:
		B.cyl(gun, 0.025, 0.025, 0.28, Vector3(0, 0.08, 0.0), metal, false, Vector3(90, 0, 0), 8)
		B.cyl(gun, 0.012, 0.012, 0.4, Vector3(0, 0.0, -0.5), metal, false, Vector3(90, 0, 0), 8)
	gun_tip = Node3D.new()
	gun_tip.position = Vector3(0, 0, -0.34 if not is_sniper else -0.72)
	gun.add_child(gun_tip)
	_flash = B.omni(gun_tip, Vector3.ZERO, Color(1, 0.7, 0.35), 0.0, 8.0)
	# Sniper laser sight (telegraphs the shot)
	if is_sniper:
		laser = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.008, 0.008, 1.0)
		laser.mesh = lm
		var lmat := M.emissive(Color(1, 0.1, 0.05), 5.0).duplicate()
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat.albedo_color.a = 0.35
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser.material_override = lmat
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.visible = false
		add_child(laser)


func _build_blender_model(model_name: String) -> void:
	body = MD.place(self, model_name, Vector3.ZERO)
	leg_l = body.find_child("thigh_l", true, false)
	leg_r = body.find_child("thigh_r", true, false)
	shin_l = body.find_child("shin_l", true, false)
	shin_r = body.find_child("shin_r", true, false)
	torso = body.find_child("torso", true, false)
	head_node = body.find_child("head", true, false)
	arm_r = body.find_child("arm_r", true, false)
	var gun: Node3D = body.find_child("gun", true, false)
	gun_node = gun
	gun_tip = body.find_child("gun_tip", true, false)
	if gun_tip == null:
		gun_tip = Node3D.new()
		gun.add_child(gun_tip)
		gun_tip.position = Vector3(0, 0, -0.5)
	_torso_base = torso.position
	if is_sniper:
		B.cyl(gun, 0.022, 0.022, 0.26, Vector3(0, 0.07, 0.0), M.get_mat("gun_metal"), false, Vector3(90, 0, 0), 8)
		B.cyl(gun, 0.011, 0.011, 0.45, Vector3(0, 0.005, -0.62), M.get_mat("gun_metal"), false, Vector3(90, 0, 0), 8)
		gun_tip.position += Vector3(0, 0, -0.35)
	_flash = B.omni(gun_tip, Vector3.ZERO, Color(1, 0.7, 0.35), 0.0, 8.0)
	if is_sniper:
		laser = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.008, 0.008, 1.0)
		laser.mesh = lm
		var lmat := M.emissive(Color(1, 0.1, 0.05), 5.0).duplicate()
		lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat.albedo_color.a = 0.35
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser.material_override = lmat
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.visible = false
		add_child(laser)


## Walk cycle + aiming pose
func _animate(delta: float) -> void:
	if leg_l == null or state == State.DEAD:
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	_crouch = move_toward(_crouch, 1.0 if (_want_crouch and spd < 0.5) else 0.0, delta * 4.0)
	if _cap:
		_cap.height = 1.8 - 0.55 * _crouch
		_cap_node.position.y = _cap.height / 2.0
	_walk += delta * spd * 3.6
	var amt := clampf(spd / 1.8, 0.0, 1.0)
	var swing := sin(_walk) * amt * 0.75
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	# knees bend on the back-swing (negative = heel comes up behind)
	shin_l.rotation.x = -maxf(0.0, -sin(_walk + 0.6)) * amt * 1.1
	shin_r.rotation.x = -maxf(0.0, sin(_walk + 0.6)) * amt * 1.1
	if _crouch > 0.01:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 1.35, _crouch)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.5, _crouch)
		shin_l.rotation.x = lerpf(shin_l.rotation.x, -1.5, _crouch)
		shin_r.rotation.x = lerpf(shin_r.rotation.x, -2.0, _crouch)
	body.position.y = -0.5 * _crouch
	var bob := absf(cos(_walk)) * 0.04 * clampf(spd / 2.5, 0.0, 1.0)
	if _torso_base != Vector3.ZERO:
		torso.position = _torso_base + Vector3(0, bob * 0.5, 0)
	else:
		torso.position.y = 0.95 + bob
	# Lean into combat, crouch a little when aiming
	var target_lean := 0.18 if state == State.COMBAT else 0.04
	torso.rotation.x = lerpf(torso.rotation.x, -target_lean, clampf(delta * 5.0, 0.0, 1.0))
	if state == State.COMBAT and _sees_player and player:
		var to: Vector3 = player.eye_position() - head_node.global_position
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		torso.rotation.x = lerpf(torso.rotation.x, -target_lean + pitch * 0.5, clampf(delta * 6.0, 0.0, 1.0))


func reset_alert() -> void:
	if state == State.DEAD:
		return
	awareness = 0.0
	state = State.PATROL
	if laser:
		laser.visible = false


func dead() -> bool:
	return state == State.DEAD


func eye() -> Vector3:
	return global_position + Vector3(0, 1.65, 0)


# ------------------------------------------------------------------ perception

func _can_see_player() -> bool:
	if player == null or player.is_dead:
		return false
	var to: Vector3 = player.eye_position() - eye()
	var dist := to.length()
	var range_mult := 1.0
	if player.stance == 1:      # crouched
		range_mult = 0.7
	elif player.stance == 2:    # prone
		range_mult = 0.4
	# The dark forest hides you well until you reach the wire
	if player.global_position.z < -32.0:
		range_mult *= 0.6
	if game and game.player_in_light():
		range_mult = maxf(range_mult, 2.2)
	if state == State.COMBAT:
		range_mult = maxf(range_mult, 1.3)
	if dist > view_range * range_mult:
		return false
	var fwd := -global_transform.basis.z
	var fov := 75.0 if state != State.COMBAT else 170.0
	if fwd.angle_to(Vector3(to.x, 0, to.z)) > deg_to_rad(fov) and dist > 3.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye(), player.eye_position())
	q.exclude = [get_rid()]
	q.collision_mask = 0xFFFFFFFF & ~512   # invisible player-only walls don't block their view
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == player


func hear(pos: Vector3, radius: float) -> void:
	if state == State.DEAD:
		return
	if global_position.distance_to(pos) < radius:
		awareness = maxf(awareness, 0.7)
		_last_seen = pos
		if state == State.PATROL:
			state = State.SUSPICIOUS


func alert(pos: Vector3) -> void:
	if state == State.DEAD:
		return
	awareness = 1.0
	_last_seen = pos
	if state != State.COMBAT:
		_enter_combat()


func _enter_combat() -> void:
	var was := state
	state = State.COMBAT
	_shot_timer = randf_range(0.6, 1.2) if not is_sniper else 1.5
	if was != State.COMBAT and game:
		game.on_enemy_alerted(self)


# ------------------------------------------------------------------ brain

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if game and game.cutscene_active:
		velocity = Vector3.ZERO
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	_think -= delta
	if _think <= 0.0:
		_think = 0.1
		_sees_player = _can_see_player()
		if _sees_player:
			_last_seen = player.global_position
			var dist := global_position.distance_to(player.global_position)
			var rate := 0.9 * clampf(1.4 - dist / view_range, 0.25, 1.4)
			if game and game.player_in_light():
				rate *= 2.5
			awareness = minf(1.0, awareness + rate * 0.1)
		else:
			# Footstep noise
			if player and not player.is_dead:
				var d := global_position.distance_to(player.global_position)
				if player.noise_level * 14.0 > d:
					awareness = minf(1.0, awareness + 0.06)
					_last_seen = player.global_position
			if state != State.COMBAT:
				awareness = maxf(0.0, awareness - 0.025)

	match state:
		State.PATROL:
			_do_patrol(delta)
			if awareness > 0.35:
				state = State.SUSPICIOUS
		State.SUSPICIOUS:
			_face(_last_seen, delta, 3.0)
			if not stationary and global_position.distance_to(_last_seen) > 3.0 and awareness > 0.55:
				_move_toward(_last_seen, 1.6)
			else:
				_stop()
			if awareness >= 1.0:
				_enter_combat()
			elif awareness <= 0.05:
				state = State.PATROL
		State.COMBAT:
			_do_combat(delta)
		State.SEARCH:
			_search_timer -= delta
			if not stationary:
				_move_toward(_last_seen, 2.5)
			if _sees_player:
				_enter_combat()
			elif _search_timer <= 0.0:
				state = State.PATROL
				awareness = 0.3

	move_and_slide()
	_animate(delta)
	_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 60.0)


func _do_patrol(delta: float) -> void:
	if stationary or patrol.is_empty():
		_stop()
		if is_sniper:
			# Scan slowly with the searchlight direction
			rotation.y += delta * 0.25 * sin(Time.get_ticks_msec() * 0.0003)
		return
	if _wait > 0.0:
		_wait -= delta
		_stop()
		return
	var target: Vector3 = patrol[_wp]
	if Vector2(global_position.x - target.x, global_position.z - target.z).length() < 0.8:
		_wp = (_wp + 1) % patrol.size()
		_wait = randf_range(1.5, 4.0)
		return
	_move_toward(target, 1.4)
	_face(target, delta, 4.0)


func _do_combat(delta: float) -> void:
	_face(_last_seen if not _sees_player else player.global_position, delta, 7.0)
	if not _sees_player:
		_aim_time = 0.0
		if laser:
			laser.visible = false
		_unseen_t += delta
		_want_crouch = _cover != null
		# Vance is hiding: flush her out with a grenade
		if tactics and not is_sniper and _grenades > 0 and _unseen_t > 2.5 and game:
			var gd := global_position.distance_to(_last_seen)
			var now := Time.get_ticks_msec() / 1000.0
			if gd > 7.0 and gd < 26.0 and now - _last_grenade > 9.0:
				_last_grenade = now
				_grenades -= 1
				_throw_grenade(_last_seen)
		if _cover != null and _search_timer < 4.0:
			_search_timer += delta
			_move_toward(_cover, 3.4)
			return
		_search_timer += delta
		if _search_timer > 6.0:
			state = State.SEARCH
			_search_timer = 10.0
		elif not stationary:
			_move_toward(_last_seen, 3.2)
		return
	_search_timer = 0.0
	_unseen_t = 0.0

	# Movement: take cover and peek, or flank; otherwise hold a distance and strafe
	var dist := global_position.distance_to(player.global_position)
	if not stationary and tactics and not is_sniper and _tactics(delta, dist):
		pass
	elif not stationary:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = randf_range(1.0, 2.5)
			_strafe_dir = [-1.0, 1.0, 0.0].pick_random()
		var side := global_transform.basis.x * _strafe_dir
		var fwd := -global_transform.basis.z
		var mv := side * 1.8
		if dist > 26.0:
			mv += fwd * 2.5
		elif dist < 8.0:
			mv -= fwd * 2.0
		velocity.x = mv.x
		velocity.z = mv.z
	else:
		_stop()

	# Shooting
	if is_sniper:
		_aim_time += delta
		_update_laser()
		if _aim_time > 1.6:
			_aim_time = 0.0
			_shoot(45.0, 0.75, "sniper")
		return
	_shot_timer -= delta
	if _crouch > 0.6 and _cover != null:
		return          # ducked behind cover
	if _shot_timer <= 0.0:
		if _burst_left <= 0:
			_burst_left = randi_range(3, 5)
		_shoot(8.0, 0.5, "enemy_rifle")
		_burst_left -= 1
		_shot_timer = 0.11 if _burst_left > 0 else randf_range(0.9, 1.8)


func _update_laser() -> void:
	if laser == null:
		return
	var from := gun_tip.global_position
	var to: Vector3 = player.eye_position() + Vector3(0, -0.3, 0)
	var length := from.distance_to(to)
	laser.visible = true
	laser.global_position = from.lerp(to, 0.5)
	laser.look_at(to, Vector3.UP)
	laser.scale = Vector3(1, 1, length)


func _shoot(damage: float, base_chance: float, sound: String) -> void:
	_flash.light_energy = 3.0
	S.play3d(self, sound, gun_tip.global_position, 2.0 if is_sniper else 0.0)
	var dist := global_position.distance_to(player.global_position)
	var chance := base_chance - dist * 0.006
	if player.stance == 1:
		chance *= 0.75
	elif player.stance == 2:
		chance *= 0.5
	var pspeed := Vector2(player.velocity.x, player.velocity.z).length()
	chance *= clampf(1.2 - pspeed * 0.08, 0.4, 1.0)
	if game and game.difficulty_mult:
		chance *= game.difficulty_mult
	if randf() < chance:
		player.take_damage(damage, global_position)
	elif randf() < 0.5:
		S.play3d(self, "whiz", player.global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), -4.0)
	else:
		# near miss kicks up dirt / chips concrete next to Vance
		var miss: Vector3 = player.global_position + Vector3(randf_range(-2, 2), 0.1, randf_range(-2, 2))
		S.play3d(self, "impact_dirt" if game and game.surface_at(miss) in ["grass", "mud", "gravel"] else "impact_concrete", miss, -6.0)
	# Visible tracer
	var to: Vector3 = player.eye_position() + Vector3(randf_range(-0.6, 0.6), randf_range(-0.5, 0.3), randf_range(-0.6, 0.6))
	_tracer(gun_tip.global_position, to)


func _tracer(from: Vector3, to: Vector3) -> void:
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, 2.0)
	t.mesh = bm
	t.material_override = M.emissive(Color(1, 0.75, 0.4), 4.0)
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(t)
	t.global_position = from
	t.look_at(to, Vector3.UP)
	var tw := t.create_tween()
	tw.tween_property(t, "global_position", to, maxf(0.05, from.distance_to(to) / 250.0))
	tw.tween_callback(t.queue_free)


func _move_toward(target: Vector3, speed: float) -> void:
	var d := target - global_position
	d.y = 0
	if d.length() < 0.3:
		_stop()
		return
	d = d.normalized()
	velocity.x = d.x * speed
	velocity.z = d.z * speed
	if get_real_velocity().length() < 0.2 and speed > 0.0:
		# Stuck against something: sidestep
		var side := d.cross(Vector3.UP)
		velocity.x += side.x * speed
		velocity.z += side.z * speed


func _stop() -> void:
	velocity.x = move_toward(velocity.x, 0, 0.5)
	velocity.z = move_toward(velocity.z, 0, 0.5)


func _face(target: Vector3, delta: float, speed: float) -> void:
	var d := target - global_position
	d.y = 0
	if d.length() < 0.1:
		return
	var want := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(speed * delta, 0.0, 1.0))


## Shouted tactical command, shown above the soldier's head
func shout(text: String) -> void:
	if state == State.DEAD:
		return
	preload("res://scripts/voice.gd").shout3d(self, text)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.004
	l.modulate = Color(1, 0.55, 0.4)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 2.3, 0)
	add_child(l)
	hand_signal()
	var tw := l.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## Arm raised hand signal (used during the ambush)
func hand_signal() -> void:
	if state == State.DEAD:
		return
	var tw := create_tween()
	tw.tween_property(arm_r, "rotation_degrees", Vector3(120, 0, 0), 0.25)
	tw.tween_interval(0.6)
	tw.tween_property(arm_r, "rotation_degrees", Vector3.ZERO, 0.25)


# ------------------------------------------------------------------ damage

func take_hit(damage: float, hit_pos: Vector3, _dir: Vector3) -> void:
	if state == State.DEAD:
		return
	var headshot := hit_pos.y - global_position.y > 1.52 - 0.42 * _crouch
	health -= damage * (headshot_mult if headshot else 1.0) * armor
	S.play3d(self, "impact_flesh", hit_pos, -2.0)
	if health <= 0.0:
		_die(headshot)
		return
	# Getting shot means you know where the player is (and it's time to find cover)
	alert(player.global_position)
	_cover_check = 0.0
	if _cover != null and global_position.distance_to(_cover) < 1.0:
		_cover_t += 2.5
	var tw := create_tween()
	tw.tween_property(body, "rotation_degrees:x", 8.0, 0.06)
	tw.tween_property(body, "rotation_degrees:x", 0.0, 0.15)


## The gun this soldier carries (dropped when he dies)
func weapon_id() -> String:
	return "dmr" if is_sniper else "ak"


func _die(headshot: bool) -> void:
	state = State.DEAD
	collision_layer = 0
	collision_mask = 1
	velocity = Vector3.ZERO
	if laser:
		laser.visible = false
	var tw := create_tween()
	tw.tween_property(body, "rotation_degrees:x", 90.0 if randf() < 0.5 else -90.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(body, "position:y", 0.15, 0.45)
	if game:
		game.on_enemy_killed(self, headshot)
	died.emit(self)


# ------------------------------------------------------------------ tactics

## Cover-to-cover fighting. Returns true when it handled movement this frame.
func _tactics(delta: float, dist: float) -> bool:
	_cover_check -= delta
	_cover_t += delta
	# Flanker: swing wide around Vance while the others keep her pinned
	if _flank_target != null:
		var ft: Vector3 = _flank_target
		_want_crouch = false
		if global_position.distance_to(ft) < 1.2 or _cover_t > 9.0:
			_flank_target = null
			_cover = null
			_cover_check = 0.0
		else:
			_move_toward(ft, 4.0)
			return true
	if _cover_check <= 0.0:
		_cover_check = 0.6
		var exposed := _cover == null or _visible_from_player(_cover + Vector3(0, 0.8, 0))
		if exposed or _cover_t > randf_range(7.0, 11.0) or (_cover != null and (_cover as Vector3).distance_to(player.global_position) < 4.0):
			var now := Time.get_ticks_msec() / 1000.0
			if _cover != null and dist > 10.0 and now - _last_flank > 12.0 and randf() < 0.3 and game and game.alive_enemies().size() >= 3:
				_last_flank = now
				_flank_target = _flank_spot()
				_cover_t = 0.0
				shout(["FLANKING LEFT!", "FLANKING RIGHT!", "I'M GOING AROUND!"].pick_random())
				return true
			var c = _find_cover()
			if c != null:
				if _cover == null and randf() < 0.35:
					shout(["TAKE COVER!", "COVER ME!", "MOVING!"].pick_random())
				_cover = c
				_cover_t = 0.0
	if _cover == null:
		return false
	var cv: Vector3 = _cover
	if Vector2(global_position.x - cv.x, global_position.z - cv.z).length() > 0.6:
		_want_crouch = false
		_move_toward(cv, 3.8)
		return true
	# At cover: duck, then pop up and shoot
	_stop()
	_peek_t -= delta
	if _peek_t <= 0.0:
		_want_crouch = not _want_crouch
		_peek_t = randf_range(1.0, 1.6) if _want_crouch else randf_range(1.6, 2.6)
		if not _want_crouch:
			_shot_timer = minf(_shot_timer, 0.25)
		elif randf() < 0.12:
			shout("RELOADING!")
	return true


func _visible_from_player(point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(player.eye_position(), point)
	q.exclude = [player.get_rid(), get_rid()]
	q.collision_mask = 0xFFFFFFFF & ~512
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


## Nearest spot within ~10 m that hides a crouching body from Vance but lets a standing one see her
func _find_cover():
	var space := get_world_3d().direct_space_state
	var best = null
	var best_score := 1e9
	var eye: Vector3 = player.eye_position()
	for i in 16:
		var a := i / 16.0 * TAU + randf() * 0.3
		for r in [3.0, 5.5, 8.5]:
			var p: Vector3 = global_position + Vector3(sin(a), 0, cos(a)) * r
			var dq := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -2.5, 0))
			dq.exclude = [get_rid()]
			dq.collision_mask = 1
			var floor_hit := space.intersect_ray(dq)
			if floor_hit.is_empty():
				continue
			var fp: Vector3 = floor_hit.position
			if absf(fp.y - global_position.y) > 0.8 or fp.distance_to(player.global_position) < 6.0:
				continue
			# can we walk there in a straight line?
			var pq := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.6, 0), fp + Vector3(0, 0.6, 0))
			pq.exclude = [get_rid(), player.get_rid()]
			pq.collision_mask = 1
			if not space.intersect_ray(pq).is_empty():
				continue
			# hidden when crouched?
			var hq := PhysicsRayQueryParameters3D.create(eye, fp + Vector3(0, 0.8, 0))
			hq.exclude = [player.get_rid(), get_rid()]
			hq.collision_mask = 1
			var h := space.intersect_ray(hq)
			if h.is_empty() or (h.position as Vector3).distance_to(fp) > 3.0:
				continue      # nothing close in front of the spot
			# can shoot when standing?
			var sq := PhysicsRayQueryParameters3D.create(eye, fp + Vector3(0, 1.6, 0))
			sq.exclude = [player.get_rid(), get_rid()]
			sq.collision_mask = 1
			var peek_ok := space.intersect_ray(sq).is_empty()
			var score: float = r + (0.0 if peek_ok else 6.0) + absf(fp.distance_to(player.global_position) - 16.0) * 0.15
			if score < best_score:
				best_score = score
				best = fp
	return best


func _flank_spot() -> Vector3:
	var to: Vector3 = global_position - player.global_position
	to.y = 0
	var side: Vector3 = to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	return player.global_position + side * 11.0 + to.normalized() * 6.0


func _throw_grenade(target: Vector3) -> void:
	shout("GRENADE OUT!")
	arm_raise()
	var g := Node3D.new()
	g.set_script(Grenade)
	g.game = game
	get_tree().current_scene.add_child(g)
	g.global_position = global_position + Vector3(0, 1.7, 0)
	g.throw_at(target + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))


func arm_raise() -> void:
	if arm_r:
		var tw := create_tween()
		tw.tween_property(arm_r, "rotation_degrees:x", -150.0, 0.2)
		tw.tween_property(arm_r, "rotation_degrees:x", 0.0, 0.4)
