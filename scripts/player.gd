extends CharacterBody3D
## Major Elena Vance - first-person controller.
## Controls: WASD move, Mouse look, Shift sprint, C crouch, Z prone,
## Space jump / stand up, Esc free mouse, click to recapture.

enum Stance { STAND, CROUCH, PRONE }

const EYE_HEIGHT := { Stance.STAND: 1.6, Stance.CROUCH: 1.0, Stance.PRONE: 0.35 }
const BODY_HEIGHT := { Stance.STAND: 1.8, Stance.CROUCH: 1.2, Stance.PRONE: 0.6 }
const SPEED := { Stance.STAND: 4.0, Stance.CROUCH: 2.2, Stance.PRONE: 1.6 }
const SPRINT_SPEED := 7.0
const MUD_MULTIPLIER := 0.55
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0025

var stance: Stance = Stance.PRONE
var mud_check: Callable          # set by the level: func(pos: Vector3) -> bool
var in_mud := false
var key_events := 0   # diagnostics: keyboard events that reached the game

var head: Node3D
var camera: Camera3D
var capsule: CapsuleShape3D
var col: CollisionShape3D
var _bob_time := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_setup_inputs()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	col = CollisionShape3D.new()
	col.shape = capsule
	add_child(col)

	head = Node3D.new()
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	head.add_child(camera)
	camera.current = true

	_apply_stance(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		key_events += 1
		# Any key press also grabs the mouse so looking around works right away
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not event.is_action("ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("crouch"):
		_set_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)
	elif event.is_action_pressed("prone"):
		_set_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump"):
		if stance != Stance.STAND:
			_set_stance(Stance.STAND)
		elif is_on_floor():
			velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed: float = SPEED[stance]
	if stance == Stance.STAND and Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	in_mud = mud_check.is_valid() and mud_check.call(global_position)
	if in_mud:
		speed *= MUD_MULTIPLIER

	var accel := 10.0 if is_on_floor() else 3.0
	velocity.x = lerp(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerp(velocity.z, dir.z * speed, accel * delta)
	move_and_slide()

	# Smooth eye height + head bob
	var target_eye: float = EYE_HEIGHT[stance]
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal > 0.5:
		_bob_time += delta * horizontal * 2.2
	var bob: float = sin(_bob_time) * 0.04 * clampf(horizontal / 4.0, 0.0, 1.0)
	head.position.y = lerp(head.position.y, target_eye + bob, 12.0 * delta)


func eye_position() -> Vector3:
	return camera.global_position


func _set_stance(new_stance: Stance) -> void:
	stance = new_stance
	_apply_stance(false)


func _apply_stance(instant: bool) -> void:
	capsule.height = BODY_HEIGHT[stance]
	col.position.y = capsule.height / 2.0
	if instant:
		head.position.y = EYE_HEIGHT[stance]


func _setup_inputs() -> void:
	var binds := {
		"move_forward": KEY_W, "move_back": KEY_S,
		"move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "crouch": KEY_C,
		"prone": KEY_Z, "jump": KEY_SPACE,
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = binds[action]
			InputMap.action_add_event(action, ev)
