extends SceneTree
## Finds z-fighting: pairs of box faces that lie in the same plane, overlap, and face the same way.
var game
var n := 0
func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
func _process(_d: float) -> bool:
	n += 1
	if n == 3:
		var target: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "seg5"
		var root_node: Node = game.get(target)
		var boxes := []
		for mi in root_node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not (m.mesh is BoxMesh):
				continue
			var xf := m.global_transform
			var b := xf.basis.orthonormalized()
			# only axis-aligned boxes
			if absf(absf(b.x.x) - 1.0) > 0.001 and absf(absf(b.x.z) - 1.0) > 0.001:
				continue
			var aabb: AABB = xf * m.mesh.get_aabb()
			var mat_name := ""
			var mat = m.material_override
			if mat and mat is StandardMaterial3D:
				mat_name = str((mat as StandardMaterial3D).albedo_color)
			boxes.append([aabb, m.get_path(), mat_name])
		var hits := 0
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var A: AABB = boxes[i][0]
				var Bb: AABB = boxes[j][0]
				for ax in 3:
					for side in [0, 1]:
						var pa: float = A.position[ax] + A.size[ax] * side
						var pb: float = Bb.position[ax] + Bb.size[ax] * side
						if absf(pa - pb) > 0.004:
							continue
						# overlap in the other two axes
						var o := 1.0
						for k in 3:
							if k == ax:
								continue
							var lo := maxf(A.position[k], Bb.position[k])
							var hi := minf(A.end[k], Bb.end[k])
							o *= maxf(0.0, hi - lo)
						if o > 0.05:
							hits += 1
							if hits <= 40:
								print("ZFIGHT axis=", "XYZ"[ax], " plane=", snappedf(pa, 0.01), " area=", snappedf(o, 0.1), "  ", A.get_center().snapped(Vector3.ONE * 0.1), " ", A.size.snapped(Vector3.ONE * 0.1), "  vs  ", Bb.get_center().snapped(Vector3.ONE * 0.1), " ", Bb.size.snapped(Vector3.ONE * 0.1))
		print("TOTAL ", hits, " boxes=", boxes.size())
		quit()
	return false
