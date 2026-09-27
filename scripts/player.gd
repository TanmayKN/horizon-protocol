extends CharacterBody3D
## Major Elena Vance — first-person controller.
## WASD move | Mouse look | Shift sprint | C crouch (while sprinting = slide) | Z prone
## Space jump/stand | Q/E lean | LMB fire | RMB aim | R reload | F interact | Esc free mouse

const S := preload("res://scripts/sfx.gd")
const WeaponScript := preload("res://scripts/weapon.gd")
const MD := preload("res://scripts/models.gd")

enum Stance { STAND, CROUCH, PRONE }

const EYE_HEIGHT := { Stance.STAND: 1.62, Stance.CROUCH: 1.05, Stance.PRONE: 0.35 }
const BODY_HEIGHT := { Stance.STAND: 1.8, Stance.CROUCH: 1.2, Stance.PRONE: 0.6 }
const SPEED := { Stance.STAND: 4.2, Stance.CROUCH: 2.3, Stance.PRONE: 1.3 }
const STEP_LENGTH := { Stance.STAND: 2.0, Stance.CROUCH: 1.5, Stance.PRONE: 1.1 }
const SPRINT_SPEED := 7.2
const MUD_MULTIPLIER := 0.6
const JUMP_VELOCITY := 4.6
const MOUSE_SENS := 0.0022
const MAX_STAMINA := 6.0
const MAX_HEALTH := 100.0

signal died

var game                      # game.gd (set by game)
var stance: Stance = Stance.PRONE
var surface_check: Callable   # func(pos: Vector3) -> String  ("grass", "mud", "hard", "metal")
var surface := "grass"
var in_mud := false
var key_events := 0

var controls_enabled := true  # false during scripted moments
var move_enabled := true      # false while riding the truck (can still look + shoot)
var driving := false          # true while Vance drives the truck (no shooting)
var carrier: Node3D = null    # when set, Vance rides along with this node (the truck bed)
var _carrier_yaw := 0.0
var health := MAX_HEALTH
var stamina := MAX_STAMINA
var is_dead := false
var aiming := false
var sprinting := false
var noise_level := 0.0        # how loud the player is right now (0..1), used by enemy AI

var head: Node3D              # pitch
var cam_holder: Node3D        # lean / bob / shake / roll
var camera: Camera3D
var weapon                    # weapon.gd
var capsule: CapsuleShape3D
var col: CollisionShape3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _bob_time := 0.0
var _step_dist := 0.0
var _lean := 0.0
var _slide_time := 0.0
var _slide_dir := Vector3.ZERO
var _land_dip := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _shake := 0.0
var _recoil := Vector2.ZERO   # visual kick (pitch, yaw) that springs back
var _since_damage := 99.0
var _stamina_lock := false
var _mud_splash_timer := 0.0
var _ladders: Array = []
var _climb_step := 0.0

# Third-person view (V to toggle)
var third_person := false
var _tp_blend := 0.0
var body_model: Node3D
var _b_thigh_l: Node3D
var _b_thigh_r: Node3D
var _b_shin_l: Node3D
var _b_shin_r: Node3D
var _b_torso: Node3D
var _b_arm_r: Node3D
var _b_arm_l: Node3D
var _walk_phase := 0.0


func _ready() -> void:
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	col = CollisionShape3D.new()
	col.shape = capsule
	add_child(col)

	head = Node3D.new()
	add_child(head)
	cam_holder = Node3D.new()
	head.add_child(cam_holder)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.02
	camera.far = 900.0
	cam_holder.add_child(camera)
	camera.current = true

	weapon = Node3D.new()
	weapon.set_script(WeaponScript)
	weapon.player = self
	camera.add_child(weapon)

	_build_body()
	_apply_stance(true)
	# Don't grab the mouse yet: on macOS/Windows grabbing it before the game window is focused
	# leaves the mouse "captured" by nothing. It is grabbed on the first click ("CLICK TO PLAY").


func capture_mouse() -> void:
	# Toggle through VISIBLE so the OS really re-grabs the cursor for this window
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Let go of the mouse when you switch apps; clicking back in grabs it again
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Walk up small ledges (kerbs, door sills, floor slabs) instead of getting stuck on them
const STEP_HEIGHT := 0.35
func _try_step_up(vel: Vector3, delta: float) -> void:
	var horiz := Vector3(vel.x, 0, vel.z)
	if not is_on_floor() or not is_on_wall() or horiz.length() < 0.5:
		return
	var motion := horiz.normalized() * maxf(horiz.length() * delta, 0.12)
	var up := Vector3(0, STEP_HEIGHT, 0)
	var start := global_transform
	if test_move(start, up):
		return                                   # something above: can't step
	var raised := start.translated(up)
	if test_move(raised, motion):
		return                                   # still blocked higher up: it's a real wall
	var moved := raised.translated(motion)
	var col := KinematicCollision3D.new()
	if test_move(moved, -up, col):
		var drop: float = col.get_travel().length()
		if drop > 0.02:
			global_position = moved.origin - Vector3(0, drop - 0.01, 0)


## Vance's full body, only shown in third person
func _build_body() -> void:
	body_model = MD.place(self, "soldier", Vector3.ZERO)
	if body_model == null:
		return
	_b_thigh_l = body_model.find_child("thigh_l", true, false)
	_b_thigh_r = body_model.find_child("thigh_r", true, false)
	_b_shin_l = body_model.find_child("shin_l", true, false)
	_b_shin_r = body_model.find_child("shin_r", true, false)
	_b_torso = body_model.find_child("torso", true, false)
	_b_arm_r = body_model.find_child("arm_r", true, false)
	_b_arm_l = body_model.find_child("arm_l", true, false)
	for g in body_model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body_model.visible = false


func toggle_view() -> void:
	third_person = not third_person
	if game:
		game.hud.hint("THIRD PERSON" if third_person else "FIRST PERSON", 1.0)


func _update_body(delta: float, horizontal: float) -> void:
	if body_model == null:
		return
	# Third person camera: pull back over the right shoulder (aiming snaps back to first person for the sights)
	var want := 1.0 if (third_person and not aiming and not driving and not is_dead) else 0.0
	_tp_blend = move_toward(_tp_blend, want, delta * 4.0)
	body_model.visible = _tp_blend > 0.02
	weapon.visible = _tp_blend < 0.5 and not driving
	var offset := Vector3(0.75, 0.35, 3.0) * _tp_blend
	if _tp_blend > 0.0:
		# Keep the camera out of walls
		var from := head.global_position
		var to: Vector3 = head.global_transform * offset
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var frac: float = maxf(0.05, from.distance_to(hit.position) - 0.25) / maxf(0.01, from.distance_to(to))
			offset *= clampf(frac, 0.0, 1.0)
	camera.position = offset
	if not body_model.visible:
		return
	# Simple procedural animation: walk cycle, crouch and prone poses, rifle held up
	body_model.rotation.y = 0.0
	_walk_phase += delta * horizontal * 2.2
	var swing := sin(_walk_phase) * clampf(horizontal / 3.0, 0.0, 1.0) * 0.8
	var crouch := 0.0
	match stance:
		Stance.CROUCH:
			crouch = 1.0
		Stance.PRONE:
			crouch = 2.0
	if crouch >= 2.0:
		body_model.rotation_degrees.x = -85.0
		body_model.position = Vector3(0, 0.25, 0.7)
	else:
		body_model.rotation_degrees.x = 0.0
		body_model.position = Vector3(0, -0.38 * crouch, 0)
	if _b_thigh_l:
		_b_thigh_l.rotation.x = swing + crouch * 0.9 * (1.0 if crouch < 2.0 else 0.0)
		_b_thigh_r.rotation.x = -swing + crouch * 0.4 * (1.0 if crouch < 2.0 else 0.0)
		_b_shin_l.rotation.x = -maxf(0.0, -sin(_walk_phase)) * 0.8 - crouch * 1.1 * (1.0 if crouch < 2.0 else 0.0)
		_b_shin_r.rotation.x = -maxf(0.0, sin(_walk_phase)) * 0.8 - crouch * 1.4 * (1.0 if crouch < 2.0 else 0.0)
	if _b_arm_l and crouch < 2.0:
		_b_arm_l.rotation.x = 0.9 - swing * 0.2
		_b_arm_r.rotation.x = 0.9 + swing * 0.2
	if _b_torso:
		_b_torso.rotation.x = -head.rotation.x * 0.5 + (0.25 if sprinting else 0.0)
		_b_torso.rotation.z = -_lean * 0.3


# ------------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_dead:
		_look(event)
		return
	if event.is_action_pressed("toggle_view") and not is_dead:
		toggle_view()
	if event is InputEventKey and event.pressed:
		key_events += 1
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not event.is_action("ui_cancel") and not get_tree().paused and DisplayServer.window_is_focused():
			capture_mouse()


func _look(event: InputEventMouseMotion) -> void:
	var sens: float = MOUSE_SENS * ((camera.fov / 75.0) if aiming else 1.0) * (game.mouse_sens_mult if game else 1.0)   # slower when zoomed in
	rotate_y(-event.relative.x * sens)
	head.rotate_x(-event.relative.y * sens)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-86), deg_to_rad(86))
	if weapon:
		weapon.add_sway(event.relative)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion:
		pass   # handled in _input
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
		get_viewport().set_input_as_handled()
	elif not controls_enabled:
		return
	elif event.is_action_pressed("crouch"):
		if sprinting and is_on_floor() and _slide_time <= 0.0:
			_start_slide()
		else:
			_set_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)
	elif event.is_action_pressed("prone"):
		_set_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		velocity.y -= _gravity * delta
		move_and_slide()
		return

	if carrier:
		# Riding the truck: follow the bed and turn with it
		var yaw := carrier.global_rotation.y
		rotation.y += angle_difference(_carrier_yaw, yaw)
		_carrier_yaw = yaw
		global_position = carrier.global_position
		velocity = Vector3.ZERO
		aiming = controls_enabled and Input.is_action_pressed("aim") and weapon.can_aim()
		sprinting = false
		surface = "metal"
		_update_camera(delta, Vector2.ZERO, 0.0)
		return
	# Ladder climbing: W climbs up, S climbs down (whichever way you face), Space jumps off
	if not _ladders.is_empty() and controls_enabled and move_enabled:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var lad: Node3D = _ladders[0]
		var top_y: float = lad.global_position.y + float(lad.get_meta("height", 3.0))
		var into: Vector3 = -lad.global_transform.basis.z   # towards the wall / platform
		var on_ground_backing := is_on_floor() and iv.y > 0.1
		if Input.is_action_just_pressed("jump"):
			_ladders.clear()
			velocity = -into * 3.0 + Vector3.UP * 2.5
		elif not on_ground_backing:
			if stance != Stance.STAND:
				stance = Stance.STAND
				_apply_stance(false)
			var climb := -iv.y
			var hv := Vector3.ZERO
			if global_position.y > top_y - 0.35 and climb > 0.0:
				# At the top: step forward off the ladder onto the platform
				hv = into * 2.2
				velocity.y = 1.2
			else:
				velocity.y = climb * 2.6
				# Stay centred on the ladder
				var to_line: Vector3 = lad.global_position + lad.global_transform.basis.z * 0.55 - global_position
				to_line.y = 0
				hv = to_line * 4.0
			velocity.x = hv.x
			velocity.z = hv.z
			move_and_slide()
			_climb_step += absf(climb) * delta * 2.6
			if _climb_step > 0.45:
				_climb_step = 0.0
				S.play3d(self, "step_metal", global_position + Vector3.UP, -10.0, 0.2)
			_fall_speed = 0.0
			_update_camera(delta, Vector2.ZERO, 0.0)
			return

	if not is_on_floor():
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)

	var can_move := controls_enabled and move_enabled
	var input_dir := Vector2.ZERO
	if can_move:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			if stance != Stance.STAND:
				_set_stance(Stance.STAND)
			elif is_on_floor():
				velocity.y = JUMP_VELOCITY
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	aiming = controls_enabled and Input.is_action_pressed("aim") and weapon.can_aim()

	# Surface + sprint + stamina
	surface = surface_check.call(global_position) if surface_check.is_valid() else "grass"
	in_mud = surface == "mud"
	var wants_sprint := can_move and Input.is_action_pressed("sprint") and input_dir.y < -0.1 and not aiming
	if wants_sprint and stance != Stance.STAND and _slide_time <= 0.0:
		_set_stance(Stance.STAND)   # sprinting stands you up
	sprinting = wants_sprint and stance == Stance.STAND and not _stamina_lock and stamina > 0.0
	if sprinting and input_dir.length() > 0.1:
		stamina = maxf(0.0, stamina - delta)
		if stamina <= 0.0:
			_stamina_lock = true
	else:
		stamina = minf(MAX_STAMINA, stamina + delta * 0.9)
		if stamina > 1.5:
			_stamina_lock = false

	var speed: float = SPEED[stance]
	if sprinting:
		speed = SPRINT_SPEED
	if aiming:
		speed *= 0.6
	if in_mud:
		speed *= MUD_MULTIPLIER

	# Slide overrides normal movement
	if _slide_time > 0.0:
		_slide_time -= delta
		var slide_speed := lerpf(3.0, 9.5, clampf(_slide_time / 0.8, 0.0, 1.0))
		velocity.x = _slide_dir.x * slide_speed
		velocity.z = _slide_dir.z * slide_speed
	else:
		var accel := 12.0 if dir.length() > 0.0 else 14.0
		if not is_on_floor():
			accel = 2.5
		velocity.x = lerpf(velocity.x, dir.x * speed, clampf(accel * delta, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, dir.z * speed, clampf(accel * delta, 0.0, 1.0))

	var pre_move_vel := velocity
	move_and_slide()
	_try_step_up(pre_move_vel, delta)

	# Landing
	if is_on_floor() and not _was_on_floor:
		_land_dip = clampf(_fall_speed * 0.035, 0.03, 0.3)
		_play_step(clampf(_fall_speed / 6.0, 0.3, 1.0) * 6.0)
		if _fall_speed > 14.0:
			take_damage((_fall_speed - 14.0) * 8.0, global_position)
		_fall_speed = 0.0
	_was_on_floor = is_on_floor()

	# Footsteps
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal > 0.4 and _slide_time <= 0.0:
		_step_dist += horizontal * delta
		var step_len: float = STEP_LENGTH[stance] * (1.25 if sprinting else 1.0)
		if _step_dist > step_len:
			_step_dist = 0.0
			_play_step(0.0)
	noise_level = 0.0
	if horizontal > 0.4:
		noise_level = {Stance.STAND: 0.5, Stance.CROUCH: 0.2, Stance.PRONE: 0.08}[stance]
		if sprinting:
			noise_level = 1.0

	# Mud splashes on screen / weapon when moving through mud
	if in_mud and horizontal > 1.0:
		_mud_splash_timer -= delta * (2.0 if sprinting else 1.0)
		if _mud_splash_timer <= 0.0:
			_mud_splash_timer = randf_range(0.5, 1.4)
			if game:
				game.hud.mud_splash()
			weapon.add_mud()

	# Health regen
	_since_damage += delta
	if _since_damage > 5.0 and health < MAX_HEALTH:
		health = minf(MAX_HEALTH, health + 14.0 * delta)

	if global_position.y < -40.0:
		take_damage(999, global_position)

	_update_camera(delta, input_dir, horizontal)


func _update_camera(delta: float, input_dir: Vector2, horizontal: float) -> void:
	# Lean (Q/E) with wall check
	var lean_target := 0.0
	if controls_enabled and stance != Stance.PRONE:
		lean_target = Input.get_axis("lean_left", "lean_right")
	if lean_target != 0.0:
		var side := global_transform.basis.x * signf(lean_target)
		var from := head.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from + side * 0.7)
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			lean_target = 0.0
	_lean = lerpf(_lean, lean_target, clampf(10.0 * delta, 0.0, 1.0))

	# Head bob
	if is_on_floor() and horizontal > 0.5:
		_bob_time += delta * horizontal * (1.9 if stance == Stance.STAND else 2.6)
	var bob_amt := clampf(horizontal / 4.0, 0.0, 1.3) * (0.35 if aiming else 1.0)
	var bob_y := sin(_bob_time * 2.0) * 0.035 * bob_amt
	var bob_x := sin(_bob_time) * 0.025 * bob_amt

	_land_dip = lerpf(_land_dip, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	var eye: float = EYE_HEIGHT[stance]
	if _slide_time > 0.0:
		eye = 0.85
	head.position.y = lerpf(head.position.y, eye, clampf(10.0 * delta, 0.0, 1.0))

	# Shake
	_shake = maxf(0.0, _shake - delta * 2.5)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.04

	cam_holder.position = Vector3(_lean * 0.42 + bob_x, bob_y - _land_dip, 0) + sh

	# Recoil springs back
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(9.0 * delta, 0.0, 1.0))
	var roll := -_lean * 13.0 - input_dir.x * 1.6
	if _slide_time > 0.0:
		roll += 6.0
	cam_holder.rotation_degrees = Vector3(_recoil.x, _recoil.y, lerpf(cam_holder.rotation_degrees.z, roll, clampf(10.0 * delta, 0.0, 1.0)))

	# FOV
	var fov := 75.0
	if sprinting and horizontal > 3.0:
		fov = 82.0
	if _slide_time > 0.0:
		fov = 86.0
	if aiming:
		fov = weapon.ads_fov()
	camera.fov = lerpf(camera.fov, fov, clampf(10.0 * delta, 0.0, 1.0))
	_update_body(delta, horizontal)


# ------------------------------------------------------------------ actions

func _start_slide() -> void:
	_slide_time = 0.8
	_slide_dir = Vector3(velocity.x, 0, velocity.z).normalized()
	stance = Stance.CROUCH
	_apply_stance(false)
	S.play3d(self, "step_mud" if in_mud else "step_grass", global_position, 2.0)


func _set_stance(new_stance: Stance) -> void:
	if new_stance == stance:
		return
	# Can't stand up under something low
	if BODY_HEIGHT[new_stance] > BODY_HEIGHT[stance]:
		var from := global_position + Vector3.UP * 0.3
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * (BODY_HEIGHT[new_stance] - 0.2))
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			if game:
				game.hud.hint("Not enough room to stand")
			return
	stance = new_stance
	_apply_stance(false)
	S.play3d(self, "step_grass", global_position, -8.0)


func _apply_stance(instant: bool) -> void:
	capsule.height = BODY_HEIGHT[stance]
	col.position.y = capsule.height / 2.0
	if instant:
		head.position.y = EYE_HEIGHT[stance]


func _play_step(extra_db: float) -> void:
	var kind := "grass"
	if surface in ["mud", "hard", "metal", "gravel"]:
		kind = surface
	var sound := "step_%s_%d" % [kind, randi() % 5]      # 5 different takes per surface so it never repeats
	var vol: float = {Stance.STAND: -8.0, Stance.CROUCH: -14.0, Stance.PRONE: -18.0}[stance]
	if sprinting:
		vol = -4.0
	S.play3d(self, sound, global_position, vol + extra_db, 0.07)


func add_recoil(pitch: float, yaw: float) -> void:
	_recoil += Vector2(pitch, yaw)
	head.rotation.x = clampf(head.rotation.x + deg_to_rad(pitch * 0.35), deg_to_rad(-86), deg_to_rad(86))
	rotate_y(deg_to_rad(yaw * 0.3))


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 2.0)


func take_damage(amount: float, from_pos: Vector3) -> void:
	if is_dead or (game and game.god_mode):
		return
	health -= amount * (game.difficulty_mult if game else 1.0)
	_since_damage = 0.0
	add_shake(0.5)
	S.play2d(self, "hurt", -4.0)
	if game:
		game.hud.damage(from_pos, amount)
	if health <= 0.0:
		health = 0.0
		is_dead = true
		controls_enabled = false
		died.emit()


func respawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation.y = yaw
	head.rotation.x = 0.0
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	is_dead = false
	controls_enabled = true
	move_enabled = true
	stance = Stance.CROUCH
	_apply_stance(true)
	weapon.refill()


func enter_ladder(l: Node) -> void:
	if not l in _ladders:
		_ladders.append(l)
		if game and _ladders.size() == 1:
			game.hud.hint("LADDER  -  W to climb up, S to climb down", 2.5)


func exit_ladder(l: Node) -> void:
	_ladders.erase(l)


func set_carrier(node: Node3D) -> void:
	carrier = node
	if node:
		_carrier_yaw = node.global_rotation.y


func eye_position() -> Vector3:
	return head.global_position


func aim_ray() -> Array:
	return [head.global_position, -camera.global_transform.basis.z]
