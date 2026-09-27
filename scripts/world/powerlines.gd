extends Node3D
## Wooden utility poles with sagging wires between them.
## Usage: PowerLines.build(parent, [Vector3...], height_func)

const MD := preload("res://scripts/models.gd")
const M := preload("res://scripts/mats.gd")

const ATTACH := [Vector3(-1.05, 8.93, 0), Vector3(1.05, 8.93, 0), Vector3(0, 9.22, 0)]


static func build(parent: Node, points: Array) -> void:
	var poles: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var d: Vector3
		if i < points.size() - 1:
			d = points[i + 1] - p
		else:
			d = p - points[i - 1]
		d.y = 0
		var yaw := atan2(d.x, d.z)
		var body := StaticBody3D.new()
		body.position = p
		body.rotation.y = yaw
		parent.add_child(body)
		MD.place(body, "power_pole", Vector3.ZERO)
		var shape := CylinderShape3D.new()
		shape.radius = 0.14
		shape.height = 9.6
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, 4.8, 0)
		body.add_child(cs)
		poles.append(Transform3D(Basis(Vector3.UP, yaw), p))
	# Wires as thin cylinder segments following a catenary sag
	var xforms: Array = []
	for i in poles.size() - 1:
		var ta: Transform3D = poles[i]
		var tb: Transform3D = poles[i + 1]
		for att in ATTACH:
			var a: Vector3 = ta * att
			var b: Vector3 = tb * att
			var sag := 0.35 + a.distance_to(b) * 0.014
			var prev := a
			var segs := 10
			for k in range(1, segs + 1):
				var t := float(k) / segs
				var cur := a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
				var dir := cur - prev
				var y := dir.normalized()
				var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
				var z := x.cross(y)
				xforms.append(Transform3D(Basis(x * 0.012, y * dir.length(), z * 0.012), (prev + cur) / 2.0))
				prev = cur
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 5
	cyl.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cyl
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = M.get_mat("black")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
