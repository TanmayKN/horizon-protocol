extends Node3D
## A character for cutscenes (Vance, Reyes, Hale, Raskov, soldiers): walks, turns, strikes poses.
## Uses the same jointed Blender models as the enemies (pelvis/torso/thigh/shin/arm/head nodes).

const MD := preload("res://scripts/models.gd")

var model: Node3D
var parts := {}
var _walk := 0.0
var _speed := 0.0
var _target = null
var _on_arrive: Callable
var gun_visible := true:
	set(v):
		gun_visible = v
		if parts.has("gun"):
			parts["gun"].visible = v


static func spawn(parent: Node, model_name: String, pos: Vector3, yaw_deg := 0.0, tint := Color(1, 1, 1)) -> Node3D:
	var a := Node3D.new()
	a.set_script(load("res://scripts/actor.gd"))
	parent.add_child(a)
	a.global_position = pos
	a.rotation_degrees.y = yaw_deg
	a.call("_build", model_name, tint)
	return a


func _build(model_name: String, tint: Color) -> void:
	model = MD.place(self, model_name, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, tint)
	if model == null:
		model = MD.place(self, "soldier", Vector3.ZERO)
	if model == null:
		return
	for n in ["pelvis", "torso", "head", "thigh_l", "thigh_r", "shin_l", "shin_r", "arm_l", "arm_r", "gun"]:
		var node: Node3D = model.find_child(n, true, false)
		if node:
			parts[n] = node
			node.set_meta("rest", node.rotation)
			node.set_meta("rest_pos", node.position)


## Walk to a spot (xz); faces the way it walks
func walk_to(pos: Vector3, speed := 1.6, on_arrive := Callable()) -> void:
	_target = pos
	_speed = speed
	_on_arrive = on_arrive


func face(point: Vector3) -> void:
	var d := point - global_position
	rotation.y = atan2(-d.x, -d.z)


func turn_to(point: Vector3, time := 0.6) -> void:
	var d := point - global_position
	var yaw := atan2(-d.x, -d.z)
	var cur := rotation.y
	var diff := wrapf(yaw - cur, -PI, PI)
	create_tween().tween_property(self, "rotation:y", cur + diff, time).set_trans(Tween.TRANS_SINE)


func _rot(part: String, deg: Vector3, time := 0.4) -> void:
	if not parts.has(part):
		return
	var node: Node3D = parts[part]
	var target: Vector3 = node.get_meta("rest") + deg * (PI / 180.0)
	if time <= 0.0:
		node.rotation = target
	else:
		create_tween().tween_property(node, "rotation", target, time).set_trans(Tween.TRANS_SINE)


## Poses: "rest", "aim", "point", "hands_up", "kneel", "wounded", "talk", "salute", "dead", "sit"
func pose(name: String, time := 0.4) -> void:
	for n in parts:
		if n != "gun":
			_rot(n, Vector3.ZERO, time)
	match name:
		"aim":
			_rot("arm_r", Vector3(-10, 0, 0), time)
			_rot("arm_l", Vector3(-10, 0, 0), time)
			_rot("torso", Vector3(-4, 0, 0), time)
		"point":
			_rot("arm_r", Vector3(-70, 0, -10), time)
		"hands_up":
			_rot("arm_r", Vector3(-160, 0, 0), time)
			_rot("arm_l", Vector3(-160, 0, 0), time)
			gun_visible = false
		"kneel":
			_rot("thigh_l", Vector3(90, 0, 0), time)
			_rot("shin_l", Vector3(-90, 0, 0), time)
			_rot("thigh_r", Vector3(-10, 0, 0), time)
			_rot("shin_r", Vector3(-100, 0, 0), time)
			if parts.has("pelvis"):
				var p: Node3D = parts["pelvis"]
				create_tween().tween_property(p, "position:y", p.get_meta("rest_pos").y - 0.45, time)
		"wounded":
			_rot("torso", Vector3(-25, 0, 10), time)
			_rot("arm_l", Vector3(40, 0, 25), time)
			_rot("arm_r", Vector3(30, 0, -20), time)
			gun_visible = false
		"talk":
			_rot("arm_r", Vector3(35, 0, -15), time)
			_rot("head", Vector3(-5, 0, 0), time)
		"salute":
			_rot("arm_r", Vector3(-120, 0, 40), time)
		"sit":
			_rot("thigh_l", Vector3(88, 0, 0), time)
			_rot("thigh_r", Vector3(88, 0, 0), time)
			_rot("shin_l", Vector3(-85, 0, 0), time)
			_rot("shin_r", Vector3(-85, 0, 0), time)
		"dead":
			var tw := create_tween()
			tw.tween_property(self, "rotation:x", -PI / 2.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(self, "position:y", position.y + 0.15, 0.6)
	if name == "rest" and parts.has("pelvis"):
		var p2: Node3D = parts["pelvis"]
		create_tween().tween_property(p2, "position:y", p2.get_meta("rest_pos").y, time)


func _process(delta: float) -> void:
	var moving := false
	if _target != null:
		var tgt: Vector3 = _target
		var d := Vector2(tgt.x - global_position.x, tgt.z - global_position.z)
		if d.length() < 0.08:
			_target = null
			if _on_arrive.is_valid():
				_on_arrive.call()
		else:
			moving = true
			var step := minf(_speed * delta, d.length())
			var dir := d.normalized()
			global_position += Vector3(dir.x, 0, dir.y) * step
			var yaw := atan2(-dir.x, -dir.y)
			rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))
	# leg swing while walking
	if parts.has("thigh_l") and parts.has("thigh_r"):
		var amt := 0.0
		if moving:
			_walk += delta * _speed * 3.6
			amt = clampf(_speed / 1.8, 0.0, 1.0)
		if moving or absf(sin(_walk)) > 0.01:
			var swing := sin(_walk) * amt * 0.7
			parts["thigh_l"].rotation.x = parts["thigh_l"].get_meta("rest").x + swing
			parts["thigh_r"].rotation.x = parts["thigh_r"].get_meta("rest").x - swing
			if parts.has("shin_l"):
				parts["shin_l"].rotation.x = parts["shin_l"].get_meta("rest").x - maxf(0.0, -sin(_walk + 0.6)) * amt * 1.1
				parts["shin_r"].rotation.x = parts["shin_r"].get_meta("rest").x - maxf(0.0, sin(_walk + 0.6)) * amt * 1.1
			if not moving:
				_walk = 0.0
