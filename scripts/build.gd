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


## A straight wall from a to b (on the XZ plane, base at y) with rectangular openings.
## openings: Array of [offset_along_wall, width, bottom, top]
static func wall_openings(parent: Node, a: Vector3, b: Vector3, height: float, thick: float, material: Material, openings: Array = []) -> void:
	var dir := b - a
	dir.y = 0
	var length := dir.length()
	var u := dir / length
	var yaw := atan2(-u.z, u.x)   # rotate +X onto the wall direction
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	var cursor := 0.0
	var pieces: Array = []   # [start, end, bottom, top]
	for o in ops:
		var s: float = o[0]
		var e: float = o[0] + o[1]
		if s > cursor:
			pieces.append([cursor, s, 0.0, height])
		if o[2] > 0.0:
			pieces.append([s, e, 0.0, o[2]])
		if o[3] < height:
			pieces.append([s, e, o[3], height])
		cursor = e
	if cursor < length:
		pieces.append([cursor, length, 0.0, height])
	for p in pieces:
		var w: float = p[1] - p[0]
		var hgt: float = p[3] - p[2]
		if w <= 0.01 or hgt <= 0.01:
			continue
		var center: Vector3 = a + u * (p[0] + w / 2.0) + Vector3(0, p[2] + hgt / 2.0, 0)
		box(parent, Vector3(w, hgt, thick), center, material, true, Vector3(0, rad_to_deg(yaw), 0))


## A walkable ramp (invisible collider) with visual steps, rising from `bottom` to `top` (both centre points).
static func stairs(parent: Node, bottom: Vector3, top: Vector3, width: float, material: Material, solid_below := true) -> void:
	var d := top - bottom
	var run := Vector2(d.x, d.z).length()
	var rise := d.y
	var yaw := atan2(d.x, d.z)
	var steps := int(ceil(rise / 0.2))
	var holder := Node3D.new()
	holder.position = bottom
	holder.rotation.y = yaw
	parent.add_child(holder)
	for i in steps:
		var top_y := (i + 1) * rise / steps
		var z := (i + 0.5) * run / steps
		var bm := BoxMesh.new()
		# solid_below = false: each step is a thick tread (so another flight can pass underneath)
		var h := top_y if solid_below else minf(top_y, 0.4)
		bm.size = Vector3(width, h, run / steps)
		mesh(holder, bm, Vector3(0, top_y - h / 2.0, z), material)
	# Smooth ramp collider along the steps
	var body := StaticBody3D.new()
	holder.add_child(body)
	var shape := BoxShape3D.new()
	var slope_len := sqrt(run * run + rise * rise)
	shape.size = Vector3(width, 0.1, slope_len)
	var cs := add_shape(body, shape, Vector3(0, rise / 2.0, run / 2.0))
	cs.rotation.x = -atan2(rise, run)
