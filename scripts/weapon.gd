extends Node3D
## Vance's weapons: 5 hand slots, any weapon in any slot (keys 1-5 / mouse wheel, G drops).
## Guns taken from fallen enemies go into a free slot; ammo is tracked per calibre and has to be picked up.

const B := preload("res://scripts/build.gd")
const M := preload("res://scripts/mats.gd")
const S := preload("res://scripts/sfx.gd")
const MD := preload("res://scripts/models.gd")

const RANGE := 250.0
const SPRINT_POS := Vector3(0.12, -0.24, -0.3)
const MODEL_SCALE := 0.82
const PICKUP_RANGE := 2.2
const SWAP_TIME := 0.45

## Every weapon in the game. sight = height of the sight line in the model, muzzle = barrel tip (Godot axes).
const GUNS := {
	"carbine": {"name": "M4 CARBINE", "model": "rifle", "slot": 0, "ammo": "5.56", "mag": 30, "rate": 0.09,
		"damage": 34.0, "reload": 2.1, "auto": true, "recoil": 1.0, "sound": "rifle", "loud": false,
		"sight": 0.086, "ads_z": -0.2, "muzzle": Vector3(0, 0.006, -0.8), "fov": 52.0,
		"hip": Vector3(0.2, -0.205, -0.38), "hands": [[Vector3(0.012, -0.1, 0.075), Vector3(0.06, 0.07, 0.09)], [Vector3(0.0, -0.075, -0.33), Vector3(0.07, 0.06, 0.1)]]},
	"ak": {"name": "AK-74", "model": "ak", "slot": 0, "ammo": "7.62", "mag": 30, "rate": 0.105,
		"damage": 40.0, "reload": 2.5, "auto": true, "recoil": 1.5, "sound": "enemy_rifle", "loud": true,
		"sight": 0.066, "ads_z": -0.26, "muzzle": Vector3(0, 0.0, -0.68), "fov": 56.0,
		"hip": Vector3(0.2, -0.2, -0.36), "hands": [[Vector3(0.012, -0.095, 0.07), Vector3(0.06, 0.07, 0.09)], [Vector3(0.0, -0.04, -0.29), Vector3(0.07, 0.06, 0.1)]]},
	"dmr": {"name": "SVD MARKSMAN", "model": "dmr", "slot": 0, "ammo": ".308", "mag": 10, "rate": 0.4,
		"damage": 120.0, "reload": 2.9, "auto": false, "recoil": 3.2, "sound": "sniper", "loud": true,
		"sight": 0.075, "ads_z": -0.15, "muzzle": Vector3(0, 0.005, -0.89), "fov": 16.0, "scope": true,
		"hip": Vector3(0.2, -0.2, -0.38), "hands": [[Vector3(0.012, -0.095, 0.1), Vector3(0.06, 0.07, 0.09)], [Vector3(0.0, -0.04, -0.33), Vector3(0.07, 0.06, 0.1)]]},
	"pistol": {"name": "P226 PISTOL", "model": "pistol", "slot": 1, "ammo": "9mm", "mag": 15, "rate": 0.13,
		"damage": 30.0, "reload": 1.6, "auto": false, "recoil": 1.4, "sound": "pistol", "loud": true,
		"sight": 0.03, "ads_z": -0.36, "muzzle": Vector3(0, 0.004, -0.11), "fov": 62.0,
		"hip": Vector3(0.13, -0.15, -0.34), "hands": [[Vector3(0.0, -0.09, 0.07), Vector3(0.045, 0.07, 0.07)], [Vector3(-0.03, -0.1, 0.06), Vector3(0.04, 0.06, 0.07)]]},
	"knife": {"name": "COMBAT KNIFE", "model": "knife", "slot": 2, "melee": true, "damage": 250.0,
		"hip": Vector3(0.15, -0.13, -0.3), "rot": Vector3(18, 12, -8), "hands": [[Vector3(0.0, -0.005, 0.07), Vector3(0.05, 0.06, 0.09)]]},
}

var player
var model: Node3D
var muzzle: Node3D
var flash_light: OmniLight3D
var flash_mesh: MeshInstance3D

## slot -> {"id": weapon id or "", "mag": rounds loaded}
const SLOT_COUNT := 5
var slots: Array = [{"id": "carbine", "mag": 30}, {"id": "pistol", "mag": 15}, {"id": "knife", "mag": 0}, {"id": "", "mag": 0}, {"id": "", "mag": 0}]
var current := 0
var reserves := {"5.56": 60, "7.62": 0, ".308": 0, "9mm": 30}

var ammo: int:
	get:
		return int(slots[current]["mag"])
	set(v):
		slots[current]["mag"] = v
var reserve: int:
	get:
		return int(reserves.get(ammo_type(), 0))
	set(v):
		if ammo_type() != "":
			reserves[ammo_type()] = v

var reloading := false
var spread := 0.0
var scoped := false

var _cooldown := 0.0
var _reload_t := 0.0
var _swap_t := 0.0
var _swing_t := -1.0
var _swing_hit := false
var _sway := Vector2.ZERO
var _kick := 0.0
var _flash_t := 0.0
var _bob := 0.0
var _mud_spots: Array = []
var _holes: Array = []
var _ads_blend := 0.0
var _gun_root: Node3D
var _prompt_on := false


func _ready() -> void:
	model = Node3D.new()
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	_build_model()
	model.position = def().hip


# ------------------------------------------------------------------ queries

func id() -> String:
	return String(slots[current]["id"])


func def() -> Dictionary:
	return GUNS.get(id(), GUNS["knife"])


func ammo_type() -> String:
	return String(def().get("ammo", ""))


func is_melee() -> bool:
	return def().get("melee", false)


func can_aim() -> bool:
	return not reloading and not is_melee() and _swap_t <= 0.0


func ads_fov() -> float:
	return float(def().get("fov", 60.0))


func weapon_name(slot: int) -> String:
	var gid := String(slots[slot]["id"])
	return String(GUNS[gid]["name"]) if GUNS.has(gid) else "EMPTY"


# ------------------------------------------------------------------ viewmodel

func _build_model() -> void:
	if _gun_root:
		_gun_root.queue_free()
	_mud_spots.clear()
	_gun_root = Node3D.new()
	model.add_child(_gun_root)
	var d := def()
	var glove := M.get_mat("gear")
	var g := MD.place(_gun_root, String(d["model"]), Vector3.ZERO)
	if g == null:
		B.box(_gun_root, Vector3(0.05, 0.07, 0.5), Vector3.ZERO, M.get_mat("gun_metal"), false)
	for hp in d["hands"]:
		B.box(_gun_root, hp[1], hp[0], glove, false)
	for mi in _gun_root.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if id() == "carbine":
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0015
		sm.height = 0.003
		dot.mesh = sm
		dot.material_override = M.emissive(Color(1, 0.1, 0.05), 6.0)
		dot.position = Vector3(0, 0.086, -0.045)
		_gun_root.add_child(dot)
	muzzle = Node3D.new()
	muzzle.position = d.get("muzzle", Vector3(0, 0, -0.3))
	_gun_root.add_child(muzzle)
	flash_light = B.omni(muzzle, Vector3.ZERO, Color(1, 0.75, 0.4), 0.0, 6.0)
	var fm := QuadMesh.new()
	fm.size = Vector2(0.09, 0.09) * (0.6 if id() == "pistol" else 1.0)
	flash_mesh = B.mesh(muzzle, fm, Vector3(0, 0, -0.03), M.emissive(Color(1, 0.7, 0.3), 4.0), Vector3.ZERO, false)
	var fmat: StandardMaterial3D = flash_mesh.material_override.duplicate()
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.albedo_color = Color(1, 0.7, 0.3, 0.8)
	flash_mesh.material_override = fmat
	flash_mesh.visible = false


func _ads_pos() -> Vector3:
	var d := def()
	return Vector3(0.0, -float(d.get("sight", 0.05)) * MODEL_SCALE, float(d.get("ads_z", -0.2)))


# ------------------------------------------------------------------ inventory

func switch_to(slot: int) -> void:
	if slot == current or slot < 0 or slot >= slots.size() or String(slots[slot]["id"]) == "":
		return
	current = slot
	reloading = false
	_swing_t = -1.0
	_swap_t = SWAP_TIME
	_build_model()
	model.position = def().hip + Vector3(0, -0.25, 0.1)
	S.play2d(self, "swap", -8.0)


func add_ammo(kind: String, amount: int) -> void:
	reserves[kind] = int(reserves.get(kind, 0)) + amount


func slot_of(gid: String) -> int:
	for i in slots.size():
		if String(slots[i]["id"]) == gid:
			return i
	return -1


func free_slot() -> int:
	return slot_of("")


## Pick up a weapon lying on the ground.
## Same weapon already carried -> take its ammo.  Free slot -> put it there.  Hands full -> swap with what you're holding.
func take_gun(gid: String, mag: int) -> void:
	var have := slot_of(gid)
	if have >= 0:
		if GUNS[gid].get("melee", false):
			switch_to(have)
			return
		add_ammo(String(GUNS[gid]["ammo"]), mag)
		if player.game:
			player.game.hud.hint("+%d %s" % [mag, GUNS[gid]["ammo"]], 1.4)
		S.play2d(self, "reload", -10.0)
		return
	var slot := free_slot()
	if slot < 0:
		slot = current
		_drop_slot(slot)
	slots[slot] = {"id": gid, "mag": mag}
	current = -1
	switch_to(slot)
	if player.game:
		player.game.hud.hint("PICKED UP  %s   (slot %d)" % [GUNS[gid]["name"], slot + 1], 1.6)


func _drop_slot(slot: int) -> void:
	var old: Dictionary = slots[slot]
	if String(old["id"]) != "" and player.game:
		player.game.spawn_weapon_drop(String(old["id"]), player.global_position + Vector3(0, 0.3, 0) - player.global_transform.basis.z * 0.8, int(old["mag"]))
	slots[slot] = {"id": "", "mag": 0}


## G: throw away the weapon in your hands (you always keep at least one)
func drop_current() -> void:
	var count := 0
	for sl in slots:
		if String(sl["id"]) != "":
			count += 1
	if count <= 1:
		if player.game:
			player.game.hud.hint("You need to keep at least one weapon", 1.4)
		return
	var name_dropped := weapon_name(current)
	_drop_slot(current)
	S.play2d(self, "swap", -8.0)
	if player.game:
		player.game.hud.hint("DROPPED  %s" % name_dropped, 1.2)
	var s := current
	for i in slots.size():
		s = (s + 1) % slots.size()
		if String(slots[s]["id"]) != "":
			break
	current = -1
	switch_to(s)


func refill() -> void:
	# Checkpoint respawn: top up so the player is never stuck with nothing
	for sl in slots:
		if GUNS.has(sl["id"]) and not GUNS[sl["id"]].get("melee", false):
			sl["mag"] = int(GUNS[sl["id"]]["mag"])
	reserves["5.56"] = maxi(int(reserves["5.56"]), 60)
	reserves["9mm"] = maxi(int(reserves["9mm"]), 30)
	reloading = false


func add_sway(rel: Vector2) -> void:
	_sway += rel * 0.00012 * (0.3 if player.aiming else 1.0)
	_sway = _sway.limit_length(0.05)


func add_mud() -> void:
	if _mud_spots.size() > 16 or is_melee():
		return
	var q := QuadMesh.new()
	var s := randf_range(0.01, 0.028)
	q.size = Vector2(s, s * randf_range(0.6, 1.2))
	var mat: StandardMaterial3D = M.get_mat("mud").duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spot := MeshInstance3D.new()
	spot.mesh = q
	spot.material_override = mat
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side := randi() % 2
	if side == 0:
		spot.position = Vector3(0.03, randf_range(-0.03, 0.03), randf_range(-0.4, 0.1))
		spot.rotation_degrees = Vector3(0, 90, randf() * 360)
	else:
		spot.position = Vector3(randf_range(-0.02, 0.02), 0.041, randf_range(-0.4, 0.1))
		spot.rotation_degrees = Vector3(-90, 0, randf() * 360)
	_gun_root.add_child(spot)
	_mud_spots.append({"node": spot, "life": 40.0})


# ------------------------------------------------------------------ per frame

func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controls_enabled or player.is_dead or player.driving:
		return
	for i in SLOT_COUNT:
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			switch_to(i)
			return
	if event.is_action_pressed("drop_weapon"):
		drop_current()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step := 1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
			var s := current
			for i in slots.size():
				s = (s + step + slots.size()) % slots.size()
				if String(slots[s]["id"]) != "":
					break
			switch_to(s)


func _process(delta: float) -> void:
	if player == null:
		return
	_cooldown -= delta
	_swap_t -= delta
	var can_act: bool = player.controls_enabled and not player.is_dead and not player.driving and _swap_t <= 0.0
	var d := def()

	if is_melee():
		_process_knife(delta, can_act)
	else:
		# Reload
		if reloading:
			_reload_t -= delta
			if _reload_t <= 0.0:
				var need: int = int(d["mag"]) - ammo
				var take: int = mini(need, reserve)
				ammo += take
				reserve -= take
				reloading = false
		elif can_act and Input.is_action_just_pressed("reload") and ammo < int(d["mag"]) and reserve > 0:
			_start_reload()
		# Fire
		var trigger: bool = Input.is_action_pressed("fire") if d["auto"] else Input.is_action_just_pressed("fire")
		if can_act and not reloading and trigger and not player.sprinting:
			if _cooldown <= 0.0:
				if ammo > 0:
					_fire()
				elif Input.is_action_just_pressed("fire"):
					S.play2d(self, "empty", -6.0)
					if reserve > 0:
						_start_reload()
					elif player.game:
						player.game.hud.hint("NO %s AMMO  -  switch weapons (1 / 2 / 3) or find more" % ammo_type(), 2.0)

	_check_pickups()

	# Spread: grows while moving / firing, shrinks when aiming
	var move_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var base_spread := 0.8 + move_speed * 0.35
	if player.stance == 1:
		base_spread *= 0.7
	elif player.stance == 2:
		base_spread *= 0.45
	if player.aiming:
		base_spread *= 0.05 if d.get("scope", false) else 0.12
	spread = lerpf(spread, base_spread, clampf(8.0 * delta, 0.0, 1.0))

	# Viewmodel pose
	_ads_blend = lerpf(_ads_blend, 1.0 if player.aiming else 0.0, clampf(14.0 * delta, 0.0, 1.0))
	var hip: Vector3 = d["hip"]
	var target := hip.lerp(_ads_pos(), _ads_blend)
	var rot: Vector3 = d.get("rot", Vector3.ZERO)
	if player.sprinting and move_speed > 3.0:
		target = SPRINT_POS
		rot = Vector3(-12, 35, 8)
	if reloading:
		var t := 1.0 - _reload_t / float(d["reload"])
		var dip := sin(t * PI)
		target += Vector3(0, -0.08, 0.04) * dip
		rot += Vector3(-25, 10, 30) * dip
	if _swing_t >= 0.0:
		# Knife slash: arc from right to left with a forward thrust
		var k := _swing_t / 0.35
		var arc := sin(k * PI)
		target += Vector3(-0.18 * k, 0.04 * arc, -0.16 * arc)
		rot += Vector3(-30 * arc, 50 * arc, -70 * k)
	_bob += delta * move_speed * 1.8
	var bob_amt := clampf(move_speed / 4.0, 0.0, 1.4) * (1.0 - _ads_blend * 0.85)
	target += Vector3(sin(_bob) * 0.008, absf(cos(_bob)) * 0.01, 0) * bob_amt
	_sway = _sway.lerp(Vector2.ZERO, clampf(6.0 * delta, 0.0, 1.0))
	target += Vector3(-_sway.x, _sway.y, 0)
	_kick = lerpf(_kick, 0.0, clampf(16.0 * delta, 0.0, 1.0))
	target.z += _kick * 0.05
	rot.x += _kick * 4.0 * float(d.get("recoil", 1.0))
	model.position = model.position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	model.rotation_degrees = model.rotation_degrees.lerp(rot, clampf((25.0 if _swing_t >= 0.0 else 12.0) * delta, 0.0, 1.0))

	# Sniper scope: hide the rifle and show the scope overlay once fully aimed
	scoped = d.get("scope", false) and player.aiming and _ads_blend > 0.6
	# never let the camera end up inside the scope body: hide the rifle as soon as you start aiming it
	_gun_root.visible = not (d.get("scope", false) and player.aiming and _ads_blend > 0.15)
	if player.game:
		player.game.hud.set_scope(scoped)

	# Muzzle flash
	_flash_t -= delta
	flash_mesh.visible = _flash_t > 0.0 and not scoped
	flash_light.light_energy = 1.6 if _flash_t > 0.0 else 0.0

	# Mud washes off slowly in the rain
	for i in range(_mud_spots.size() - 1, -1, -1):
		var m: Dictionary = _mud_spots[i]
		m.life -= delta
		if not is_instance_valid(m.node):
			_mud_spots.remove_at(i)
			continue
		var mat: StandardMaterial3D = m.node.material_override
		mat.albedo_color.a = clampf(m.life / 10.0, 0.0, 1.0)
		if m.life <= 0.0:
			m.node.queue_free()
			_mud_spots.remove_at(i)


func _process_knife(delta: float, can_act: bool) -> void:
	if _swing_t >= 0.0:
		_swing_t += delta
		if not _swing_hit and _swing_t > 0.12:
			_swing_hit = true
			_knife_hit()
		if _swing_t > 0.35:
			_swing_t = -1.0
	elif can_act and Input.is_action_just_pressed("fire") and not player.sprinting:
		_swing_t = 0.0
		_swing_hit = false
		S.play2d(self, "swish", -4.0)


func _knife_hit() -> void:
	var cam: Camera3D = player.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 2.4)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		# Forgiving: also check a slightly lower ray (enemies' torsos when you look at their heads)
		q = PhysicsRayQueryParameters3D.create(origin, origin + (fwd + Vector3(0, -0.3, 0)).normalized() * 2.4)
		q.exclude = [player.get_rid()]
		hit = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var c: Object = hit.collider
	if c and c.has_method("take_hit"):
		c.take_hit(float(def()["damage"]), hit.position, fwd)
		S.play2d(self, "stab", -2.0)
		player.add_shake(0.15)
		if player.game:
			player.game.hud.hitmarker()
	else:
		S.play3d(self, "impact", hit.position, -6.0)


func _start_reload() -> void:
	reloading = true
	_reload_t = float(def()["reload"])
	S.play2d(self, "reload", -6.0)


func _fire() -> void:
	var d := def()
	ammo -= 1
	_cooldown = float(d["rate"])
	_kick = 1.0
	_flash_t = 0.04
	S.play2d(self, String(d["sound"]), -3.0 if not d["loud"] else -1.0)
	var r: float = randf_range(0.9, 1.25) * (0.55 if player.aiming else 1.0) * float(d["recoil"])
	player.add_recoil(r, randf_range(-0.35, 0.35) * float(d["recoil"]))
	if player.game:
		player.game.on_player_shot(player.global_position, bool(d["loud"]))

	var cam: Camera3D = player.camera
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var spread_rad := deg_to_rad(spread)
	var dir := (fwd + cam.global_transform.basis.x * randf_range(-1, 1) * spread_rad * 0.5 + cam.global_transform.basis.y * randf_range(-1, 1) * spread_rad * 0.5).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RANGE)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * RANGE
	if not hit.is_empty():
		end = hit.position
		var c: Object = hit.collider
		if c and c.has_method("take_hit"):
			c.take_hit(float(d["damage"]), hit.position, dir)
			if player.game:
				player.game.hud.hitmarker()
		elif c and c.has_method("on_shot"):
			c.on_shot(hit.position)
		else:
			_impact(hit.position, hit.normal)
	if not scoped:
		var from_pos: Vector3 = muzzle.global_position
		if player._tp_blend > 0.5:
			from_pos = player.head.global_position + player.global_transform.basis.x * 0.25 + fwd * 0.7
		_tracer(from_pos, end)


# ------------------------------------------------------------------ pick-ups

func _check_pickups() -> void:
	var game = player.game
	if game == null:
		return
	var best: Node3D = null
	var best_d := PICKUP_RANGE
	var eye: Vector3 = player.global_position
	for dr in game.weapon_drops:
		if not is_instance_valid(dr):
			continue
		var dist: float = Vector2(dr.global_position.x - eye.x, dr.global_position.z - eye.z).length()
		if dist < best_d and absf(dr.global_position.y - eye.y) < 2.0:
			best_d = dist
			best = dr
	if best == null or player.driving or not player.controls_enabled:
		if _prompt_on:
			game.hud.prompt("")
			_prompt_on = false
		return
	if game._intel_near != null:
		return
	var gid: String = best.get_meta("gun_id")
	var mag: int = best.get_meta("mag")
	var text := ""
	if slot_of(gid) >= 0:
		if GUNS[gid].get("melee", false):
			text = "You already have a %s" % GUNS[gid]["name"]
		else:
			text = "Press  F  to take ammo  (+%d %s)" % [mag, GUNS[gid]["ammo"]]
	elif free_slot() >= 0:
		text = "Press  F  to pick up  %s   (goes in slot %d)" % [GUNS[gid]["name"], free_slot() + 1]
	else:
		text = "Hands full - press  F  to swap your  %s  for  %s" % [weapon_name(current), GUNS[gid]["name"]]
	game.hud.prompt(text)
	_prompt_on = true
	if Input.is_action_just_pressed("interact"):
		game.weapon_drops.erase(best)
		best.queue_free()
		game.hud.prompt("")
		_prompt_on = false
		take_gun(gid, mag)


# ------------------------------------------------------------------ effects

func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var host := get_tree().current_scene
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, minf(length, 12.0))
	t.mesh = bm
	var mat := M.emissive(Color(1.0, 0.8, 0.5), 3.0).duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.5
	t.material_override = mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(t)
	var mid := from.lerp(to, minf(6.0, length * 0.5) / length)
	t.global_position = mid
	t.look_at_from_position(mid, to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var tw := t.create_tween()
	tw.tween_property(t, "global_position", to, 0.06)
	tw.tween_callback(t.queue_free)


func _impact(pos: Vector3, normal: Vector3) -> void:
	var host := get_tree().current_scene
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -9, 0)
	var pm := BoxMesh.new()
	pm.size = Vector3(0.02, 0.02, 0.02)
	p.mesh = pm
	p.material_override = M.get_mat("mud")
	host.add_child(p)
	p.global_position = pos
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
	var hole := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	hole.mesh = q
	hole.material_override = M.get_mat("black")
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(hole)
	hole.global_position = pos + normal * 0.01
	var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.FORWARD
	hole.look_at(pos + normal * 2.0, up)
	hole.rotate_object_local(Vector3.UP, PI)
	_holes.append(hole)
	if _holes.size() > 80:
		var old = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	S.play3d(self, "impact", pos, -10.0)
