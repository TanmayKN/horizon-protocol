extends StaticBody3D
## Pursuing Kranor gun truck (military 4x4 with a ring-mounted machine gun) during the truck escape.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")

signal destroyed(tech)

var game
var health := 260.0
var gunner_alive := true
var dead := false
var gap := 30.0            # metres behind the player's truck along the road
var lateral := 0.0
var _fire_t := 2.0
var gun_tip: Node3D
var gunner: Node3D
var _flash: OmniLight3D


const MD := preload("res://scripts/models.gd")


func _ready() -> void:
	var paint := M.tinted("rust", Color(0.42, 0.4, 0.3))
	if MD.place(self, "technical", Vector3.ZERO, Vector3.ZERO, Vector3.ONE, Color(0.34, 0.37, 0.28)) == null:
		B.mesh(self, _bm(Vector3(2.1, 0.9, 5.0)), Vector3(0, 0.9, 0), paint)
		B.mesh(self, _bm(Vector3(2.0, 1.0, 1.9)), Vector3(0, 1.8, -0.9), paint)
		B.mesh(self, _bm(Vector3(1.9, 0.7, 0.05)), Vector3(0, 1.9, -1.86), M.get_mat("glass"))
		for wx in [-1.0, 1.0]:
			for wz in [-1.6, 1.6]:
				var w := B.mesh(self, CylinderMesh.new(), Vector3(wx, 0.45, wz), M.get_mat("black"), Vector3(0, 0, 90))
				w.scale = Vector3(0.45, 0.15, 0.45)
	var hl := B.spot(self, Vector3(0, 1.2, -2.5), Vector3(-6, 0, 0), Color(1, 0.95, 0.8), 3.0, 35.0, 30.0)
	hl.light_volumetric_fog_energy = 1.5
	# Gunner standing in the rear bay behind the ring-mounted machine gun
	gunner = Node3D.new()
	gunner.position = Vector3(0, 1.35, 1.2)
	add_child(gunner)
	var soldier := MD.place(gunner, "soldier", Vector3.ZERO)
	if soldier:
		var g: Node3D = soldier.find_child("gun", true, false)
		if g:
			g.visible = false
		for n in ["arm_r", "arm_l"]:
			var arm: Node3D = soldier.find_child(n, true, false)
			if arm:
				arm.rotation_degrees = Vector3(70, 0, 0)     # hands on the gun grips
	else:
		B.mesh(gunner, _bm(Vector3(0.45, 0.7, 0.3)), Vector3(0, 0.55, 0), M.get_mat("uniform"))
		var head := B.mesh(gunner, SphereMesh.new(), Vector3(0, 1.1, 0), M.get_mat("gear"))
		head.scale = Vector3(0.28, 0.28, 0.28)
	if not MD.available("technical"):
		B.mesh(self, _bm(Vector3(0.12, 0.12, 1.3)), Vector3(0, 2.3, 0.5), M.get_mat("gun_metal"))
		B.mesh(self, _bm(Vector3(0.08, 0.9, 0.08)), Vector3(0, 1.8, 1.0), M.get_mat("gun_metal"))
	gun_tip = Node3D.new()
	gun_tip.position = Vector3(0, 2.62, -0.52) if MD.available("technical") else Vector3(0, 2.3, -0.2)
	add_child(gun_tip)
	_flash = B.omni(gun_tip, Vector3.ZERO, Color(1, 0.7, 0.3), 0.0, 8.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 2.4, 5.0)
	B.add_shape(self, shape, Vector3(0, 1.2, 0))


func _bm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func update_fire(delta: float, player) -> void:
	_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 50.0)
	if dead or not gunner_alive or player.is_dead:
		return
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = randf_range(0.12, 0.2) if randf() < 0.8 else randf_range(1.0, 2.0)
		_flash.light_energy = 3.0
		S.play3d(self, "mg", gun_tip.global_position, 2.0)
		var chance := 0.13
		if player.stance != 0:
			chance *= 0.55
		if game and game.difficulty_mult:
			chance *= game.difficulty_mult
		if randf() < chance:
			player.take_damage(6.0, global_position)
		elif randf() < 0.3:
			S.play3d(self, "whiz", player.global_position + Vector3(randf_range(-1, 1), 1.4, 0), -6.0)
		var tr := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.02, 2.5)
		tr.mesh = bm
		tr.material_override = M.emissive(Color(1, 0.7, 0.3), 5.0)
		get_tree().current_scene.add_child(tr)
		var to: Vector3 = player.eye_position() + Vector3(randf_range(-1.2, 1.2), randf_range(-0.8, 0.6), randf_range(-1.2, 1.2))
		tr.global_position = gun_tip.global_position
		tr.look_at(to, Vector3.UP)
		var tw := tr.create_tween()
		tw.tween_property(tr, "global_position", to, 0.12)
		tw.tween_callback(tr.queue_free)


func take_hit(damage: float, hit_pos: Vector3, _dir: Vector3) -> void:
	if dead:
		return
	# Hitting the gunner silences the gun
	if gunner_alive and hit_pos.distance_to(gunner.global_position + Vector3(0, 0.8, 0)) < 0.7:
		gunner_alive = false
		gunner.visible = false
		S.play3d(self, "impact_flesh", hit_pos, 0.0)
		if game:
			game.hud.hint("GUNNER DOWN", 1.2)
		health -= 60.0
	else:
		health -= damage
		S.play3d(self, "impact_metal", hit_pos, -2.0)
	if health <= 0.0:
		explode()


func explode() -> void:
	if dead:
		return
	dead = true
	S.play3d(self, "explosion", global_position, 8.0, 0.0, 200.0)
	var l := B.omni(self, Vector3(0, 2, 0), Color(1, 0.55, 0.2), 14.0, 25.0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 2.0, 1.5)
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 1.0
	fire.direction = Vector3.UP
	fire.spread = 25.0
	fire.initial_velocity_min = 2.0
	fire.initial_velocity_max = 5.0
	fire.gravity = Vector3(0, 1, 0)
	var fm := BoxMesh.new()
	fm.size = Vector3(0.3, 0.3, 0.3)
	fire.mesh = fm
	fire.material_override = M.emissive(Color(1, 0.45, 0.1), 5.0)
	fire.position = Vector3(0, 1.5, 0)
	add_child(fire)
	if game:
		game.hud.hint("GUN TRUCK DESTROYED", 1.5)
		game.player.add_shake(0.6)
	destroyed.emit(self)
