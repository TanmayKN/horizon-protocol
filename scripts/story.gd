extends Node
## The cinematics of THE HORIZON PROTOCOL (built on cutscene.gd + actor.gd).
##  intro()      - flyover of the valley, Colonel Hale's briefing, Reyes on the ridge
##  twist()      - Site 9: Hale lands, reveals he is 'H', shoots Reyes, takes the drive
##  reyes_free() - Vance cuts Reyes loose in the hangar office
##  hale_intro() - Hale at his jet, engines spooling
##  finale()     - sunrise on the runway, Hale beaten, Command listening

const Actor := preload("res://scripts/actor.gd")
const S := preload("res://scripts/sfx.gd")

const HALE := "Col. Hale"
const VANCE := "Vance"
const REYES := "Sgt. Reyes"
const RASKOV := "Raskov"
const PILOT := "Nightingale 2-1"
const COMMAND := "Allied Command (duty officer)"

var game
var _actors: Array = []


func _spawn(model: String, pos: Vector3, yaw := 0.0) -> Node3D:
	var a := Actor.spawn(game, model, pos, yaw)
	_actors.append(a)
	return a


func _clear_actors() -> void:
	for a in _actors:
		if is_instance_valid(a):
			a.queue_free()
	_actors.clear()


## Lambdas capture locals by value, so actors live in a shared dictionary A and are looked up when used
func _head(A: Dictionary, key: String, h := 1.6) -> Callable:
	return func() -> Vector3:
		var n = A.get(key)
		return n.global_position + Vector3(0, h, 0) if n != null and is_instance_valid(n) else Vector3.ZERO


# ------------------------------------------------------------------ 1. insertion

func intro() -> void:
	var A := {}
	var p = game.player
	var ppos: Vector3 = p.global_position
	var tower: Vector3 = game.seg1.TOWER_POS + Vector3(0, 9, 0)
	var fwd: Vector3 = -p.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	await game.cutscene.play([
		{"t": 7.0, "cam": [Vector3(-70, 48, -125), Vector3(-30, 40, -95)], "look": [Vector3(20, 0, 90), Vector3(20, 0, 70)], "fov": 55,
		 "call": func(): game.hud.fade_to(0.0, 2.0),
		 "lines": [[0.8, HALE, "Major Vance, this is Colonel Hale. From here on you're alone. This channel is your only line home."],
			[4.0, HALE, "Three days ago Vanguard Corp stole the Horizon Protocol. With it, they can switch off the defences of any country on Earth."]]},
		{"t": 6.0, "cam": [Vector3(30, 16, -8), Vector3(16, 13, 2)], "look": [tower, tower], "fov": 40,
		 "lines": [[0.3, HALE, "Kranor, down in the valley, has Raskov's launch logs. Get them and we find the drive."],
			[3.4, REYES, "Overwatch on the ridge. Tower's got a sniper and a searchlight. Stay low, Major."]]},
		{"t": 5.0, "cam": [ppos + fwd * 2.8 + side * 1.4 + Vector3(0, 1.0, 0), ppos + fwd * 2.0 + side * 0.7 + Vector3(0, 0.95, 0)], "look": [ppos + Vector3(0, 0.95, 0), ppos + Vector3(0, 1.0, 0)], "fov": 45,
		 "call": func():
			A.vance = _spawn("vance", ppos, rad_to_deg(p.rotation.y))
			A.vance.pose("kneel", 0.0),
		 "lines": [[0.3, VANCE, "Copy, Overwatch. Moving in."],
			[2.6, HALE, "Good luck, Elena. Nobody else knows you're there."]]},
	])
	_clear_actors()


# ------------------------------------------------------------------ 2. the betrayal at Site 9

func twist() -> void:
	var A := {}
	var Y: float = game.seg5.Y
	var p = game.player
	var heli: Node3D = game.seg5.heli
	var vpos := Vector3(10, Y, 612)
	await game.cutscene.play([
		{"t": 4.5, "cam": [Vector3(15, Y + 3.2, 620), Vector3(12.5, Y + 2.4, 615)], "look": [Vector3(10, Y + 2.0, 596), Vector3(10, Y + 1.8, 600)], "fov": 50,
		 "call": func():
			p.visible = false
			A.vance = _spawn("vance", vpos, 0.0)
			A.reyes = _spawn("reyes", Vector3(6.8, Y, 614.5), 20.0)
			A.reyes.pose("wounded", 0.0)
			A.hale = _spawn("hale", Vector3(10, Y, 597.5), 180.0)
			A.g1 = _spawn("soldier", Vector3(8.4, Y, 597.0), 180.0)
			A.g2 = _spawn("soldier", Vector3(11.6, Y, 597.0), 180.0)
			A.hale.walk_to(Vector3(10, Y, 606.5), 1.3)
			A.g1.walk_to(Vector3(7.8, Y, 605.5), 1.35)
			A.g2.walk_to(Vector3(12.2, Y, 605.5), 1.35),
		 "lines": [[0.4, PILOT, "Site 9, Nightingale on the ground. Your ride's here."]]},
		{"t": 4.5, "cam": [Vector3(13.5, Y + 0.7, 608.5), Vector3(12.6, Y + 0.9, 610)], "look": [_head(A, "hale",  1.5), _head(A, "hale",  1.6)], "fov": 42,
		 "lines": [[0.6, HALE, "Major Vance. Outstanding work, truly. I'll take the drive from here."]]},
		{"t": 3.6, "cam": [Vector3(10.7, Y + 1.85, 614.4), Vector3(10.6, Y + 1.8, 613.9)], "look": [_head(A, "hale"), _head(A, "hale")], "fov": 45,
		 "call": func():
			A.vance.face(Vector3(10, Y, 606))
			A.hale.pose("talk"),
		 "lines": [[0.3, VANCE, "Colonel? You flew out here yourself? That's not how this works."]]},
		{"t": 4.2, "cam": [Vector3(4.2, Y + 1.5, 612.2), Vector3(4.6, Y + 1.5, 612.6)], "look": [_head(A, "reyes",  1.3), _head(A, "reyes",  1.3)], "fov": 40,
		 "call": func(): A.reyes.face(Vector3(10, Y, 606)),
		 "lines": [[0.3, REYES, "Elena... the file on Raskov's console. His source was 'H'. Colonel's clearance."]]},
		{"t": 4.0, "cam": [Vector3(10.4, Y + 1.72, 609.3), Vector3(10.3, Y + 1.7, 608.9)], "look": [_head(A, "hale",  1.62), _head(A, "hale",  1.62)], "fov": 38,
		 "call": func():
			A.hale.face(A.reyes.global_position)
			A.hale.pose("point"),
		 "lines": [[0.2, HALE, "Always the sharp one, Marcus."]],
		 "events": [[2.3, func():
			S.play3d(game, "pistol", A.hale.global_position + Vector3(0, 1.4, 0), 4.0)
			game.cutscene.shake(0.8)
			A.reyes.pose("kneel", 0.25)]]},
		{"t": 6.5, "cam": [Vector3(3.5, Y + 2.6, 616.5), Vector3(5.0, Y + 2.3, 615.5)], "look": [Vector3(10, Y + 1.3, 608), Vector3(10, Y + 1.3, 607.5)], "fov": 50,
		 "call": func():
			A.g1.pose("aim")
			A.g2.pose("aim")
			A.g1.face(vpos)
			A.g2.face(vpos)
			A.vance.pose("hands_up")
			A.hale.face(vpos)
			A.hale.pose("talk")
			game.audio.stinger("sting_reveal", -2.0),
		 "lines": [[0.2, VANCE, "You're 'H'."],
			[1.4, HALE, "The Protocol goes to the highest bidder at seven. Vostok airfield. Nothing personal, Elena."],
			[4.2, HALE, "You were the best we had. That's exactly why I needed you to fetch it for me."]]},
		{"t": 4.5, "cam": [Vector3(15, Y + 1.8, 612), Vector3(15.5, Y + 2.2, 610)], "look": [Vector3(10, Y + 1.4, 606), Vector3(10, Y + 1.8, 600)], "fov": 50,
		 "call": func():
			A.g1.pose("rest")
			A.g1.walk_to(A.reyes.global_position + Vector3(0.7, 0, -0.3), 2.0)
			A.hale.walk_to(Vector3(10, Y, 599), 1.4),
		 "events": [[1.6, func():
			A.reyes.pose("wounded", 0.2)
			A.reyes.walk_to(Vector3(9.4, Y, 598.5), 1.2)
			A.g1.walk_to(Vector3(8.8, Y, 598.5), 1.2)]],
		 "lines": [[0.3, HALE, "Marcus comes with us. Insurance."], [2.6, VANCE, "HALE!"]]},
		{"t": 2.6, "cam": [Vector3(10.6, Y + 1.8, 613.6), Vector3(10.6, Y + 1.8, 613.4)], "look": [Vector3(11.5, Y + 1.0, 607), Vector3(11.5, Y + 0.4, 609)], "fov": 45,
		 "call": func():
			A.g2.pose("point"),
		 "events": [[0.9, func(): S.play3d(game, "grenade_bounce", Vector3(10.5, Y + 0.2, 610), 2.0)],
			[1.9, func():
				S.play2d(game, "explosion", -2.0, 0.0)
				game.hud.flash_white(3.0)]],
		 "lines": [[0.1, "Mercenary", "Flashbang!"]]},
	])
	game.hud.fade_to(1.0, 0.01)
	game.seg5.heli_depart()
	_clear_actors()
	p.visible = true


# ------------------------------------------------------------------ 3. Reyes cut loose

func reyes_free() -> void:
	var s6 = game.seg6
	var r: Node3D = s6.reyes_actor
	var p = game.player
	var rp: Vector3 = s6.REYES_POS
	await game.cutscene.play([
		{"t": 4.0, "cam": [rp + Vector3(1.8, 1.3, -1.6), rp + Vector3(1.4, 1.2, -1.2)], "look": [rp + Vector3(0, 1.0, 0), rp + Vector3(0, 1.1, 0)], "fov": 45,
		 "call": func(): p.visible = false,
		 "lines": [[0.2, REYES, "Took you long enough, Major. Cable ties. Hale's idea of a joke."],
			[2.2, VANCE, "Can you walk?"]]},
		{"t": 4.5, "cam": [rp + Vector3(-1.0, 1.6, -2.3), rp + Vector3(-0.6, 1.7, -2.0)], "look": [rp + Vector3(0, 1.4, 0), rp + Vector3(0, 1.6, 0)], "fov": 45,
		 "call": func():
			if is_instance_valid(r):
				r.pose("rest", 0.6)
				r.set("gun_visible", true),
		 "lines": [[0.2, REYES, "Walk, no. Shoot, yes. Give me that rifle, I'll cover you from the hangar door."],
			[2.5, REYES, "Hale's at the jet with the drive. They're fuelling it now. Go!"]]},
	])
	p.visible = true
	if is_instance_valid(r):
		r.global_position = Vector3(-50, 0, 1128)
		r.rotation_degrees.y = 180.0
		r.pose("aim", 0.0)


# ------------------------------------------------------------------ 4. Hale at the jet

func hale_intro() -> void:
	var s6 = game.seg6
	var jp: Vector3 = s6.JET_POS
	await game.cutscene.play([
		{"t": 4.2, "cam": [jp + Vector3(-18, 2.0, -24), jp + Vector3(-12, 3.0, -20)], "look": [jp + Vector3(0, 2.5, 0), jp + Vector3(-3, 2.5, 0)], "fov": 48,
		 "call": func(): s6.set_jet_power(0.25),
		 "lines": [[0.3, HALE, "Elena! You should have stayed down at Site 9."],
			[2.4, HALE, "Kill her. Then get this bird in the air!"]]},
	])


# ------------------------------------------------------------------ 5. sunrise

func finale() -> void:
	var A := {}
	var s6 = game.seg6
	var p = game.player
	var hp: Vector3 = s6.JET_POS + Vector3(-4.5, 0, -6.5)
	var all_intel: bool = game.intel_found >= game.intel_total
	await game.cutscene.play([
		{"t": 5.0, "cam": [hp + Vector3(6, 1.0, -7), hp + Vector3(4, 1.2, -5)], "look": [hp + Vector3(0, 1.0, 0), hp + Vector3(0, 1.1, 0)], "fov": 45,
		 "call": func():
			p.visible = false
			s6.set_jet_power(0.0)
			A.hale = _spawn("hale", hp, 200.0)
			A.hale.pose("kneel", 0.0)
			A.hale.set("gun_visible", false)
			A.vance = _spawn("vance", hp + Vector3(2.5, 0, -3.5), 0.0)
			A.vance.face(hp)
			A.vance.pose("aim", 0.0),
		 "lines": [[0.4, HALE, "You think Command will take your word over mine? I'm a colonel. You're a ghost."]]},
		{"t": 4.6, "cam": [hp + Vector3(1.2, 1.7, -1.0), hp + Vector3(1.0, 1.6, -0.8)], "look": [_head(A, "vance"), _head(A, "vance")], "fov": 40,
		 "lines": [[0.2, VANCE, "Every file, every payment, every name. I found it all, Adrian." if all_intel else "They won't need my word. Raskov kept everything he had on you."]]},
		{"t": 5.5, "cam": [hp + Vector3(-7, 2.2, 4), hp + Vector3(-5, 2.0, 1)], "look": [hp + Vector3(0, 1.2, 0), hp + Vector3(1, 1.2, -2)], "fov": 50,
		 "call": func():
			A.reyes = _spawn("reyes", hp + Vector3(-12, 0, -14), 0.0)
			A.reyes.walk_to(hp + Vector3(-2.5, 0, -2.5), 1.4),
		 "lines": [[0.3, REYES, "And the channel's been open since the tower went down, Colonel. Command heard every word."],
			[3.2, COMMAND, "Colonel Adrian Hale, stand down. Nightingale, this is Command. Bring them home."]]},
		{"t": 7.0, "cam": [hp + Vector3(2, 1.8, -4), hp + Vector3(20, 18, -40)], "look": [hp + Vector3(0, 1.2, 0), hp + Vector3(-60, 8, 60)], "fov": 55,
		 "call": func():
			A.vance.pose("rest")
			A.hale.pose("hands_up")
			game.hud.hint("HORIZON PROTOCOL RECOVERED", 4.0),
		 "lines": [[0.5, VANCE, "It's over, Marcus."], [3.0, REYES, "Yeah. And for once, the sun's actually up."]]},
	])
	_clear_actors()
	p.visible = true
