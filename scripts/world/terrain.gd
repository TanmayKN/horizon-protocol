extends Node3D
## The valley terrain shared by Segment 1 (forest slope + logging yard) and Segment 2 (Kranor yard).
## Mountains rise at the edges so the valley closes itself off naturally.

const M := preload("res://scripts/mats.gd")

const X_MIN := -130.0
const X_MAX := 130.0
const Z_MIN := -120.0
const Z_MAX := 210.0
const SPACING := 2.0
const ROAD_X := 20.0
const ROAD_HALF := 4.0
const FENCE_Z := -30.0
const YARD_Z := 36.0      # Kranor perimeter

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()


func _init() -> void:
	noise.seed = 1337
	noise.frequency = 0.028
	detail.seed = 99
	detail.frequency = 0.12


func road_x_at(z: float) -> float:
	# The access road snakes gently down the slope
	if z < -10.0:
		return ROAD_X + sin(z * 0.045) * 6.0
	return ROAD_X


func height_at(x: float, z: float) -> float:
	var h := 0.0
	var forest := 0.0
	if z < -10.0:
		h = (-10.0 - z) * 0.2
		forest = clampf((-10.0 - z) / 18.0, 0.0, 1.0)
	var road_d := absf(x - road_x_at(z))
	var road_flat := clampf((road_d - ROAD_HALF) / 5.0, 0.0, 1.0)
	h += noise.get_noise_2d(x, z) * 2.6 * forest * road_flat
	h += detail.get_noise_2d(x, z) * 0.25 * forest
	# Road is cut slightly into the hillside
	if road_d < ROAD_HALF + 1.0:
		h -= 0.15 * forest
	# Mountains around the valley
	var edge_x := maxf(0.0, absf(x) - 85.0) / 45.0
	var edge_z := maxf(0.0, Z_MIN + 40.0 - z) / 40.0 + maxf(0.0, z - (Z_MAX - 30.0)) / 30.0
	var edge := clampf(maxf(edge_x, edge_z), 0.0, 1.0)
	# The exit road cuts a pass through the northern mountains
	if z > 150.0:
		edge *= clampf((absf(x - 15.0) - 9.0) / 12.0, 0.0, 1.0)
	h += edge * edge * (32.0 + noise.get_noise_2d(x * 0.5, z * 0.5) * 10.0)
	return h


func surface_at(pos: Vector3) -> String:
	if pos.z > YARD_Z - 2.0 and pos.y < 1.0:
		return "hard"
	if absf(pos.x - road_x_at(pos.z)) < ROAD_HALF and pos.z < YARD_Z:
		return "mud"
	if absf(pos.x) < 4.0 and absf(pos.z - FENCE_Z) < 4.0:
		return "mud"
	return "grass"


func _ready() -> void:
	var nx := int((X_MAX - X_MIN) / SPACING) + 1
	var nz := int((Z_MAX - Z_MIN) / SPACING) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var x := X_MIN + i * SPACING
			var z := Z_MIN + j * SPACING
			var h := height_at(x, z)
			heights[j * nx + i] = h
			st.set_color(_color_at(x, z, h))
			st.set_uv(Vector2(x, z) * 0.1)
			st.add_vertex(Vector3(x, h, z))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var d := c + 1
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	st.generate_normals()

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = M.get_mat("ground")
	body.add_child(mi)

	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(SPACING, 1, SPACING)
	# HeightMapShape3D is centred on its origin
	cs.position = Vector3((X_MIN + X_MAX) / 2.0, 0, (Z_MIN + Z_MAX) / 2.0)
	body.add_child(cs)


func _color_at(x: float, z: float, h: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0, z * 3.0)
	var c := Color(0.2, 0.25, 0.14).lerp(Color(0.27, 0.24, 0.15), 0.5 + n * 0.5)   # forest floor + needles
	if z > -10.0:
		c = Color(0.34, 0.32, 0.28).lerp(Color(0.28, 0.26, 0.22), 0.5 + n * 0.5)   # gravel yard
	if z > YARD_Z - 2.0:
		c = Color(0.36, 0.36, 0.35).lerp(Color(0.3, 0.3, 0.3), 0.5 + n * 0.5)      # concrete apron
	var road_d := absf(x - road_x_at(z))
	if z < YARD_Z and (road_d < ROAD_HALF or (absf(x) < 4.0 and absf(z - FENCE_Z) < 4.0)):
		c = Color(0.22, 0.16, 0.1).lerp(Color(0.17, 0.12, 0.08), 0.5 + n * 0.5)   # mud
		if road_d > ROAD_HALF - 0.8 and road_d < ROAD_HALF:
			c = c.lightened(0.08)
	if h > 14.0 and (absf(x) > 85.0 or z < -80.0 or z > 180.0):
		c = c.lerp(Color(0.36, 0.36, 0.36), clampf((h - 14.0) / 12.0, 0.0, 0.8))  # rocky mountain
	return c
