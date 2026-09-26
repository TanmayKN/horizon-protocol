extends CharacterBody3D
## Vanguard Corp soldier AI: patrol -> suspicious -> combat -> dead.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")

enum State { PATROL, SUSPICIOUS, SEARCH, COMBAT, DEAD }

signal died(enemy)

var game
var player
var patrol: Array = []          # Array of Vector3 waypoints
var is_sniper := false
var stationary := false
var health := 100.0
var state: State = State.PATROL
var awareness := 0.0            # 0..1 (1 = fully alerted)
var view_range := 42.0
var callsign := "Tango"

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


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	B.add_shape(self, cap, Vector3(0, 0.9, 0))
	_build_model()
	if is_sniper:
		view_range = 38.0
		health = 80.0


func _build_model() -> void:
	body = Node3D.new()
	add_child(body)
	var uni := M.get_mat("uniform")
	var gear := M.get_mat("gear")
	var metal := M.get_mat("gun_metal")
	B.box(body, Vector3(0.16, 0.85, 0.2), Vector3(-0.12, 0.43, 0), uni, false)   # legs
	B.box(body, Vector3(0.16, 0.85, 0.2), Vector3(0.12, 0.43, 0), uni, false)
	B.box(body, Vector3(0.5, 0.62, 0.28), Vector3(0, 1.17, 0), uni, false)       # torso
	B.box(body, Vector3(0.54, 0.44, 0.34), Vector3(0, 1.22, 0), gear, false)     # plate carrier
	B.box(body, Vector3(0.3, 0.12, 0.08), Vector3(0, 1.1, -0.2), gear, false)    # pouches
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.13
	hs.height = 0.28
	head.mesh = hs
	head.material_override = M.tinted("uniform", Color(0.35, 0.33, 0.3))   # balaclava
	head.position = Vector3(0, 1.65, 0)
	body.add_child(head)
	var helm := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.155
	hm.height = 0.2
	hm.is_hemisphere = true
	helm.mesh = hm
	helm.material_override = gear
	helm.position = Vector3(0, 1.69, 0)
	body.add_child(helm)
	# Night-vision goggles with a faint green glow
	B.box(body, Vector3(0.14, 0.05, 0.06), Vector3(0, 1.72, -0.15), metal, false)
	B.box(body, Vector3(0.1, 0.02, 0.01), Vector3(0, 1.72, -0.185), M.emissive(Color(0.3, 1.0, 0.4), 3.0), false)
	# Arms + rifle
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.3, 1.38, 0)
	body.add_child(arm_r)
	B.box(arm_r, Vector3(0.13, 0.13, 0.5), Vector3(0, -0.12, -0.22), uni, false)
	B.box(body, Vector3(0.13, 0.13, 0.5), Vector3(-0.25, 1.26, -0.25), uni, false, Vector3(0, 25, 0))
	var gun := Node3D.new()
	gun.position = Vector3(0.05, 1.25, -0.45)
	body.add_child(gun)
	B.box(gun, Vector3(0.06, 0.1, 0.7), Vector3.ZERO, metal, false)
	B.box(gun, Vector3(0.04, 0.16, 0.06), Vector3(0, -0.1, 0.05), metal, false)
	if is_sniper:
		B.box(gun, Vector3(0.05, 0.05, 0.25), Vector3(0, 0.08, 0.0), metal, false)
		B.cyl(gun, 0.012, 0.012, 0.4, Vector3(0, 0.0, -0.55), metal, false, Vector3(90, 0, 0), 8)
	gun_tip = Node3D.new()
	gun_tip.position = Vector3(0, 0, -0.4 if not is_sniper else -0.75)
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
		_search_timer += delta
		if _search_timer > 6.0:
			state = State.SEARCH
			_search_timer = 10.0
		elif not stationary:
			_move_toward(_last_seen, 3.2)
		return
	_search_timer = 0.0

	# Movement: hold a comfortable distance, strafe between shots
	var dist := global_position.distance_to(player.global_position)
	if not stationary:
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
	var headshot := hit_pos.y - global_position.y > 1.5
	health -= damage * (4.0 if headshot else 1.0)
	S.play3d(self, "hit", hit_pos, -2.0)
	if health <= 0.0:
		_die(headshot)
		return
	# Getting shot means you know where the player is
	alert(player.global_position)
	var tw := create_tween()
	tw.tween_property(body, "rotation_degrees:x", 8.0, 0.06)
	tw.tween_property(body, "rotation_degrees:x", 0.0, 0.15)


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
