extends RefCounted
## Small helpers for building greybox geometry from code.
## Usage:  const B := preload("res://scripts/build.gd")   then   B.box(parent, size, pos, mat)


static func mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, rot_deg := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A box. solid=true wraps it in a StaticBody3D with a matching collider.
static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, solid := true, rot_deg := Vector3.ZERO) -> Node3D:
	var bm := BoxMesh.new()
	bm.size = size
	if not solid:
		return mesh(parent, bm, pos, material, rot_deg)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	parent.add_child(body)
	mesh(body, bm, Vector3.ZERO, material)
	var shape := BoxShape3D.new()
	shape.size = size
	add_shape(body, shape, Vector3.ZERO)
	return body


static func cyl(parent: Node, r_top: float, r_bottom: float, h: float, pos: Vector3, material: Material, solid := true, rot_deg := Vector3.ZERO, segments := 16) -> Node3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = segments
	if not solid:
		return mesh(parent, cm, pos, material, rot_deg)
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	parent.add_child(body)
	mesh(body, cm, Vector3.ZERO, material)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(r_top, r_bottom)
	shape.height = h
	add_shape(body, shape, Vector3.ZERO)
	return body


static func add_shape(body: CollisionObject3D, shape: Shape3D, pos: Vector3, rot_deg := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	return cs


## Invisible wall
static func wall(parent: Node, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	add_shape(body, shape, Vector3.ZERO)
	parent.add_child(body)
	return body


static func omni(parent: Node, pos: Vector3, color: Color, energy: float, rng: float, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


static func spot(parent: Node, pos: Vector3, rot_deg: Vector3, color: Color, energy: float, rng: float, angle: float, shadows := false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = rot_deg
	l.light_color = color
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.shadow_enabled = shadows
	parent.add_child(l)
	return l


static func label3d(parent: Node, text: String, pos: Vector3, size := 64, color := Color.WHITE, rot_deg := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees = rot_deg
	l.font_size = size
	l.modulate = color
	l.outline_size = 0
	parent.add_child(l)
	return l
