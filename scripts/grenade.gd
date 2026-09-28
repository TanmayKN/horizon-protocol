extends Node3D
## Frag grenade thrown by an enemy: arcs, bounces, beeps a warning on the HUD, explodes after 2.6 s.

const S := preload("res://scripts/sfx.gd")
const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")

var game
var vel := Vector3.ZERO
var fuse := 2.6
var _bounced := 0
var _mesh: MeshInstance3D
var _warned := false


func _ready() -> void:
	_mesh = B.cyl(self, 0.045, 0.045, 0.11, Vector3.ZERO, M.get_mat("gun_metal"), false, Vector3.ZERO, 8)
	B.omni(self, Vector3.ZERO, Color(1, 0.3, 0.2), 0.4, 1.5)
	S.play3d(self, "pin", global_position, -4.0)


func throw_at(target: Vector3) -> void:
	var t := 1.1
	var d := target - global_position
	vel = Vector3(d.x / t, (d.y + 0.5 * 9.8 * t * t) / t, d.z / t)


func _physics_process(delta: float) -> void:
	fuse -= delta
	var p = game.player if game else null
	if p and not _warned and global_position.distance_to(p.global_position) < 9.0:
		_warned = true
		game.hud.banner("GRENADE!", 1.6)
	vel.y -= 9.8 * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if p:
		q.exclude = [p.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		global_position = hit.position + n * 0.06
		vel = vel.bounce(n) * 0.35
		if _bounced < 4:
			S.play3d(self, "grenade_bounce", global_position, -6.0 - _bounced * 3.0)
		_bounced += 1
	else:
		global_position = to
	_mesh.rotation.x += delta * 12.0
	if fuse <= 0.0:
		_explode()


func _explode() -> void:
	S.play3d(get_tree().current_scene, "explosion", global_position, 6.0, 0.05, 160.0)
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.amount = 50
	fx.lifetime = 0.9
	fx.explosiveness = 1.0
	fx.spread = 180.0
	fx.initial_velocity_min = 4.0
	fx.initial_velocity_max = 11.0
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.05, 0.05)
	fx.mesh = sm
	fx.material_override = M.emissive(Color(1, 0.6, 0.2), 4.0)
	get_tree().current_scene.add_child(fx)
	fx.global_position = global_position
	fx.emitting = true
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)
	var l := B.omni(get_tree().current_scene, global_position + Vector3(0, 0.5, 0), Color(1, 0.6, 0.3), 10.0, 14.0)
	l.create_tween().tween_property(l, "light_energy", 0.0, 0.5)
	get_tree().create_timer(0.6).timeout.connect(l.queue_free)
	var p = game.player if game else null
	if p and not p.is_dead:
		var d: float = global_position.distance_to(p.global_position + Vector3(0, 0.8, 0))
		if d < 7.0:
			var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.3, 0), p.eye_position())
			q.exclude = [p.get_rid()]
			q.collision_mask = 1
			var blocked := not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
			var dmg := lerpf(95.0, 10.0, d / 7.0) * (0.35 if blocked else 1.0)
			p.take_damage(dmg, global_position)
		p.add_shake(clampf(1.6 - d * 0.08, 0.2, 1.6))
	# enemies caught in the blast
	if game:
		for e in game.alive_enemies():
			if e.global_position.distance_to(global_position) < 4.0:
				e.take_hit(150.0, e.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	queue_free()
