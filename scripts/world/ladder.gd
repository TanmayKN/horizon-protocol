extends Area3D
## Climbable ladder volume. While Vance is inside it, W climbs up and S climbs down.

const MD := preload("res://scripts/models.gd")
const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")


## Build a ladder of `height` metres at `pos`, facing `yaw_deg` (the climber stands on the +Z side).
static func create(parent: Node, pos: Vector3, height: float, yaw_deg: float) -> Area3D:
	var a := Area3D.new()
	a.set_script(load("res://scripts/world/ladder.gd"))
	a.position = pos
	a.rotation_degrees.y = yaw_deg
	parent.add_child(a)
	var model := MD.place(a, "ladder", Vector3.ZERO, Vector3.ZERO, Vector3(1, height / 9.4, 1))
	if model == null:
		# Fallback: simple rails and rungs
		for sx in [-0.26, 0.26]:
			B.box(a, Vector3(0.05, height, 0.07), Vector3(sx, height / 2.0, 0), M.get_mat("metal"), false)
		for i in int(height / 0.3):
			B.box(a, Vector3(0.52, 0.03, 0.03), Vector3(0, 0.3 + i * 0.3, 0), M.get_mat("metal"), false)
	a.set_meta("height", height)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, height + 1.4, 1.0)
	B.add_shape(a, shape, Vector3(0, (height + 1.4) / 2.0, 0.45))
	a.body_entered.connect(a._on_enter)
	a.body_exited.connect(a._on_exit)
	return a


func _on_enter(b: Node) -> void:
	if b.has_method("enter_ladder"):
		b.enter_ladder(self)


func _on_exit(b: Node) -> void:
	if b.has_method("exit_ladder"):
		b.exit_ladder(self)
