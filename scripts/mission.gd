extends Node
## Story director for THE HORIZON PROTOCOL.
## The narrative only ever moves forward: no cutscenes, no loading screens.

const S := preload("res://scripts/sfx.gd")

const OVERWATCH := "Overwatch (Sgt. Reyes)"
const VANCE := "Vance"
const RASKOV_PA := "Raskov (PA)"
const NIGHTINGALE := "Nightingale 2-1"
const HALE := "Col. Hale (Command)"
const COMMAND := "Allied Command (duty officer)"
const StoryScript := preload("res://scripts/story.gd")
const Voice := preload("res://scripts/voice.gd")
var story

var auto_start := true
var _overheard: Array = []   # {pos, r, lines, done}
var _heli_t := -1.0

var game
var step := ""
var _radio_queue: Array = []
var _radio_wait := 0.0
var _cut_progress := 0.0
var _alert_lines := 0
var _kill_lines := 0
var _t := 0.0
var _step_t := 0.0
var _dl_progress := 0.0
var _wave: Array = []
var _wave_spawned := 0
var _shout_t := 0.0
var _breach_progress := 0.0
var _breach_armed := false
var _vault_progress := 0.0
var _raskov


func _ready() -> void:
	if auto_start:
		begin()


func begin() -> void:
	if story == null:
		story = Node.new()
		story.set_script(StoryScript)
		story.game = game
		add_child(story)
	if step == "":
		_setup_story()
		_go("s1_intro")


const GUARD := "Guard (overheard)"
const GUARD2 := "Guard 2 (overheard)"


## What the downloaded data tells you (and what you do with it)
const LOGS_TEXT := "WHAT THE DATA SAYS:\n- The Horizon Protocol (a drive that can shut down any country's defences) is NOT at Kranor.\n- It is locked in the vault at SITE 9, Raskov's bunker at the top of the mountain pass.\n- A buyer called 'H' collects it at 07:00.\n- Vault override code: 4-7-1-9.\n- Raskov knew you were coming. Someone on our side leaked the mission.\n\nWHAT YOU DO WITH IT:\nEscape Kranor, get up the pass to Site 9, kill Raskov, use the code to open the vault and take the drive before H arrives.\nFind all the intel documents: they prove who 'H' really is."


func _setup_story() -> void:
	game.spawn_intel(Vector3(-26, 0.97, 8), "Shipping manifest", "TIMBERLINE LOGGING CO.  -  night shipments\n\nCrates marked KR-9 go straight to Kranor, NOT to the mill. Do not open them. Do not log them.\nAnyone asking questions answers to Vanguard.\n\n- V.C. Logistics", "Segment 1 - on the rusty workbench by the shed, far LEFT (west) side of the logging yard")
	game.spawn_intel(Vector3(0.9, 9.22, 17.0), "Tower sniper's logbook", "02:40  Convoy through the pass. Four trucks, one jeep. The General rode in the jeep.\n03:15  Orders: shoot anything that moves near the wire. No warnings.\n04:10  Rain again. Searchlight motor keeps sticking.", "Segment 1 - up in the guard tower cabin (climb the ladder)")
	game.spawn_intel(Vector3(42.8, 0.22, 60.0), "Guard rota note", "QRF sleeps in the admin block.\nGrid test scheduled for 05:00. If the lights go out, it is a DRILL.\n\n(Someone has scrawled underneath: 'unless it isn't')", "Segment 2 - inside the big warehouse next to the admin building, on the floor at the end nearest the main gate")
	game.spawn_intel(Vector3(43.3, 4.42, 110.1), "Printed email", "FROM: V. Raskov\nTO: Kranor Admin\n\nSite 9 is ready. The Protocol stays there until the buyer arrives at 07:00.\nKranor keeps the logs as bait. If anyone comes for them, cut the power and let the QRF do its job.", "Segment 2 - admin building, MIDDLE floor, on a desk")
	game.spawn_intel(Vector3(7.5, 19.25, 668.0), "Vanguard personnel file", "SUBJECT: MAJ. ELENA VANCE\nStatus: EXPECTED.\n\nInsertion route, radio codes and Sgt. Reyes' position all supplied by our friend at Allied Command.\n'She will come alone and she will not come quietly.'\n- Source: 'H'  (colonel's clearance)", "Segment 5 - in the big bunker hall just after the long entrance corridor, on the floor")
	game.spawn_intel(Vector3(98.5, 13.05, 1099.2), "Purchase agreement", "PURCHASE AGREEMENT  (encrypted, decrypted by Vance)\n\nItem: THE HORIZON PROTOCOL, one unit.\nBuyer: the MERIDIAN CONSORTIUM.\nPrice: 400,000,000 USD, escrow released on delivery. Vostok airfield, 07:00.\nSeller's agent: A. HALE\n\n'The courier will not be a problem. She trusts me.'", "Segment 6 - in the control tower cab, on the radar console")
	game.spawn_intel(Vector3(-72.5, 0.86, 1110.8), "Flight plan", "FLIGHT PLAN  N-7730\nVostok -> (destination blank)\nPassengers: 2.  Cargo: 'diplomatic, do not inspect'.\nFiled by: Col. A. Hale, Allied Command liaison office.\n\nPilot's note: paid in cash. Asked no questions.", "Segment 6 - on the desk in the OPS office at the back of Hangar 1")
	game.spawn_intel(Vector3(-2.0, 23.07, 696.3), "Encrypted message on Raskov's console", "DECRYPTED:\n\nPackage inbound. Payment on delivery.\nVance is handled. The leak has been useful.\n\nReply routed to: A. HALE, Allied Command liaison office.\n- H.", "Segment 5 - on Raskov's console in the command room")
	_overheard = [
		{"pos": Vector3(-24, 0, 12), "r": 17.0, "done": false, "lines": [
			[GUARD, "Why are we guarding logs in the pouring rain?"],
			[GUARD2, "Those aren't logs going down to Kranor. Keep your mouth shut and your eyes on the wire."]]},
		{"pos": Vector3(26, 0, 80), "r": 16.0, "done": false, "lines": [
			[GUARD, "The General's moving the drive to Site 9 tonight."],
			[GUARD2, "Site 9? Up the pass? Then why are we still sitting in this dump?"],
			[GUARD, "Because someone is coming for the logs. The General said so. Like he knew."]]},
		{"pos": Vector3(43, 0, 106), "r": 9.0, "done": false, "lines": [
			[GUARD, "Command, ground floor is quiet. ...Copy. The QRF stays up top until the grid test."]]},
		{"pos": Vector3(10, 19, 645), "r": 13.0, "done": false, "lines": [
			["Technician (overheard)", "Server sync at ninety percent. Once the buyer pays, the Protocol goes live."],
			[GUARD, "And if that Major gets this far?"],
			["Technician (overheard)", "Then pray the General is faster than she is."]]},
	]


func _check_overheard() -> void:
	var p: Vector3 = game.player.global_position
	for o in _overheard:
		if o.done or p.distance_to(o.pos) > o.r or game.max_awareness() > 0.5:
			continue
		o.done = true
		var first := true
		for l in o.lines:
			say(l[0], l[1], 0.3 if first else 0.5)
			first = false


func _process(delta: float) -> void:
	_t += delta
	_step_t += delta
	_process_radio(delta)
	_check_overheard()
	var p = game.player
	if step == "s4_ride":
		_do_wheel(delta)
	if step in ["s3_down", "s3_catwalk", "s3_window"] and not game.seg2.in_admin(p.global_position) and not game.seg2.in_w1(p.global_position) and p.global_position.y < 2.0 and p.is_on_floor():
		say(OVERWATCH, "Vance! You're outside? Hold on, I'm coming to you!", 0.0, true)
		_go("s4_escape")
	match step:
		"s1_intro":
			if _near(game.seg1.WIRE_POS, 3.2):
				_go("s1_cut")
		"s1_cut":
			_do_cut(delta)
		"s1_sniper":
			if game.seg1.sniper and game.seg1.sniper.dead():
				_go("s1_downhill")
		"s1_downhill":
			if p.global_position.z > game.terrain.YARD_Z + 2.0:
				_go("s2_enter")
		"s2_enter":
			if game.seg2.in_admin(p.global_position):
				_go("s2_admin")
		"s2_admin":
			if _near3(game.seg2.TERMINAL_POS, 2.4):
				_go("s2_download")
		"s2_download":
			_do_download(delta)
		"s3_blackout":
			if _step_t > 4.0 and _wave_dead(_wave):
				_go("s3_down")
		"s3_down":
			if game.seg2.floor_of(p.global_position) == 1 and game.seg2.in_admin(p.global_position):
				_go("s3_catwalk")
		"s3_catwalk":
			_do_catwalk_wave(delta)
			if _step_t > 8.0 and (_alive_in(_wave) <= 1 or _step_t > 50.0):
				_go("s3_window")
		"s3_window":
			_do_window(delta)
		"s5_enter":
			if game.seg5.in_server_room(p.global_position):
				_go("s5_server")
		"s5_server":
			if _near3(game.seg5.BREACH_POS + Vector3(0, 0, -1.5), 3.0):
				_go("s5_breach")
		"s5_breach":
			_do_breach(delta)
		"s5_raskov":
			if _raskov and _raskov.dead() and _wave_dead(_wave):
				_go("s5_vault")
		"s5_vault":
			_do_vault(delta)
		"e_return":
			if _near3(game.seg4.truck.global_position, 7.0):
				_go("e_extract")
		"s6_infil":
			if p.global_position.z > game.seg6.FENCE_Z + 2.0:
				_go("s6_tower")
		"s6_tower":
			_hold_task(delta, game.seg6.TOWER_CONSOLE, 2.6, 3.0, "Hold  F  to wreck the radar", "s6_reyes")
		"s6_reyes":
			_do_reyes(delta)
		"s6_hale":
			_do_hale(delta)
		"s5_drive":
			if _near3(game.seg5.DRIVE_POS, 2.2):
				game.hud.prompt("Press  F  to take the Horizon Protocol drive")
				if Input.is_action_just_pressed("interact"):
					_go("end")
			else:
				game.hud.prompt("")
		_:
			pass


# ------------------------------------------------------------------ steps

func _go(new_step: String) -> void:
	step = new_step
	_step_t = 0.0
	var hud = game.hud
	var seg1 = game.seg1
	match step:
		"s1_intro":
			_spawn_segment1()
			_intro_sequence()
			say(OVERWATCH, "Vance, comms check. I have you prone, forty metres off the wire. Stay low.", 2.0)
			say(VANCE, "Copy, Overwatch. Soaked but in position.")
			say(OVERWATCH, "Fence is torn right in front of you. One strand still holds. Cut it and you're in.")
			say(OVERWATCH, "Mind the searchlight on the central tower. If it lights you up, the sniper up there won't miss.")
			say(OVERWATCH, "Controls check: C to crouch, Z to go prone, Q and E to lean. Stay in the dark.", 1.0)
			_goal("Crawl to the broken fence  (follow the yellow marker)", "Stay low so the searchlight misses you:  Z = lie down,  C = crouch", _marker(seg1.WIRE_POS, 1.0))
		"s1_cut":
			_goal("Cut the fence wire", "Stand at the gap and HOLD  F", _marker(seg1.WIRE_POS, 1.0))
		"s1_sniper":
			hud.prompt("")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(OVERWATCH, "You're through. Tower sniper is your priority. Once he's down, the yard is blind.", 0.5)
			say(OVERWATCH, "Right-click to aim. That light is a target too if you want to keep it simple.")
			_goal("Kill the sniper in the guard tower", "Hold RIGHT-CLICK (or X) to aim, then shoot.  His scoped rifle drops in the tower - climb the ladder to grab it", seg1.sniper)
		"s1_downhill":
			seg1.stop_searchlight()
			say(OVERWATCH, "Sniper down. Tower's dark. Nice work, Major.", 0.8)
			say(OVERWATCH, "Kranor Logistics is at the bottom of the slope. Follow the access road to the gate.")
			say(VANCE, "Moving down.")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			_goal("Go down the hill to the Kranor yard", "Follow the road and the power lines down the slope", Vector3(20, 2, game.terrain.YARD_Z))
		"s2_enter":
			game.set_atmosphere("yard")
			hud.title("SEGMENT 2", "The Logistics Hub Infiltration     |     Kranor Logistics Yard")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			say(OVERWATCH, "You're inside Kranor. The target terminal is in the admin office, dead centre of the yard.", 1.0)
			say(OVERWATCH, "Container stacks will box you in. Watch every corner.")
			say(OVERWATCH, "Admin block is the three-storey building east of the road, next to warehouse W1. Terminal's on the top floor.")
			_spawn_segment2()
			_goal("Get inside the grey 3-storey admin building", "Sneak through the containers.  The door is on the loading-bay side (marker)", Vector3(36.5, 1.5, 105))
		"s2_admin":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(OVERWATCH, "You're inside. Stairs are in the north-east corner. Top floor, secure node.", 0.3)
			_goal("Go UP the stairs to the TOP floor - the computer is there", "The stairs are in the back corner.  Look for the glowing green screen", game.seg2.TERMINAL_POS + Vector3(0, 1.2, -0.9))
		"s2_download":
			say(VANCE, "At the terminal. Starting the download.", 0.0)
			_goal("Take the data from the computer", "Stand at the green screen and HOLD  F  until the bar is full", game.seg2.TERMINAL_POS + Vector3(0, 1.2, -0.9))
		"s3_blackout":
			hud.prompt("")
			game.seg2.start_blackout()
			game.set_atmosphere("blackout")
			game.player.add_shake(1.2)
			hud.title("SEGMENT 3", "The Ambush and Comms Jam     |     The Admin Block")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			game.add_story("RASKOV'S LOGS  (downloaded at Kranor)", LOGS_TEXT)
			hud.show_intel("RASKOV'S LOGS - DOWNLOADED", LOGS_TEXT, 0, 0)
			say(VANCE, "Download complete. Command, the logs point to Site 9, Raskov's bunker up the pass. The Protocol isn't here-", 0.2, true)
			say(HALE, "Site 9. Understood, Major. Sit tight, I'm moving assets now.", 0.2)
			say(OVERWATCH, "Vance, the grid just went- that wasn't us. Vanguard QRF is on the stairs!", 0.3, false, true)
			hud.hint("COMMS JAMMED", 4.0)
			hud.banner("!!  POWER FAILURE  -  LOCKDOWN  -  ALL DOORS CLOSING  !!", 6.0)
			say(RASKOV_PA, "Major Vance. Did you really think I would leave my logs unguarded?", 3.0)
			_goal("AMBUSH!  Kill the soldiers coming up the stairs", "Take cover behind the desks.  R = reload,  1 / 2 / 3 = switch weapon")
			_wave = []
			var top: Vector3 = game.seg2.RAMP_B_TOP
			for off in [Vector3(-0.8, 0.3, 0.5), Vector3(0.8, 0.3, 1.5), Vector3(0.0, 0.3, 2.5)]:
				var e = game.spawn_enemy(top + off, [], false, false, 0.0, "Vanguard")
				e.health = 120.0
				e.alert(game.player.global_position)
				_wave.append(e)
			get_tree().create_timer(1.0).timeout.connect(func():
				if _wave.size() > 0 and is_instance_valid(_wave[0]):
					_wave[0].shout("CONTACT! TOP FLOOR!"))
		"s3_down":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(OVERWATCH, "-ance, do you read? ...stairwell's collapsing below the second floor...", 0.5, false, true)
			say(OVERWATCH, "Get down to the second storey. The transformer blast took out the west windows. That's your exit.")
			say(OVERWATCH, "Vance... they were waiting for you. Somebody tipped them off.", 1.5)
			say(VANCE, "Only three people knew I was here. You, me... and the Colonel.")
			say(OVERWATCH, "Don't even say that. Just get out of there.")
			_goal("Go DOWN the stairs one floor", "The stairs below that are blocked by rubble - get off on the middle floor", Vector3(47.2, game.seg2.FLOOR_H * 1.5 + 1.2, 107.5))
		"s3_catwalk":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			_wave = []
			_wave_spawned = 0
			game.seg2.breach_catwalk_door()
			hud.banner("!!  CATWALK DOOR FORCED OPEN  !!", 3.0)
			say(OVERWATCH, "Movement on the warehouse catwalk! They're forcing the south door!", 0.3, true)
			say(RASKOV_PA, "Take her alive if you can. If you can't... I'll settle for the drive.", 2.0)
			_goal("Kill the soldiers coming through the catwalk door", "Aim at the door (marker).  Grab the guns and ammo they drop", game.seg2.CATWALK_DOOR + Vector3(0, 1.5, 0))
		"s3_window":
			game.seg2.open_window()
			game.seg2.reseal_catwalk_door()
			game.seg4.visible = true
			game.seg2.stop_alarm()
			say(OVERWATCH, "Vance! I've got a supply truck. I'm bringing it under the west window. When I say jump, you JUMP!", 0.2, true)
			_goal("Run to the smashed window and jump", "Stand at the window and press  F  to jump onto Reyes' truck", game.seg2.WINDOW_POS + Vector3(0, 1.2, 0))
		"s4_escape":
			hud.prompt("")
			hud.set_objective("")
			say(OVERWATCH, "NOW, VANCE!", 0.0, true)
			game.start_segment4()
		"s4_ride":
			_goal("Shoot the gun trucks chasing you", "Aim for the gunner behind the machine gun.  Crouch (C) when bullets fly")
			say(OVERWATCH, "Got you! Hold on to something!", 0.2, true)
			say(VANCE, "Just drive, Reyes!")
			say(HALE, "Major, Nightingale is standing by. I'll meet you at Site 9 myself.", 6.0)
			say(OVERWATCH, "The Colonel? In person? ...Since when does he leave his desk?", 1.0)
		"s5_enter":
			game.seg1.visible = false
			game.seg2.visible = false
			var out: Vector3 = game.seg4.dismount()
			game.player.global_position = out
			game.player.stance = 1
			game.player._apply_stance(true)
			game.player.move_enabled = true
			game.player.controls_enabled = true
			game.set_atmosphere("bunker")
			game.seg5.set_ambience(true)
			game.set_checkpoint(out, game.player.rotation.y, false)
			hud.title("SEGMENT 5", "The Subterranean Stronghold     |     Vanguard Command Bunker")
			say(OVERWATCH, "Argh... my leg's pinned under the dash. I'll hold the entrance.", 1.5, true)
			say(OVERWATCH, "Go, Vance. Raskov is in there. Finish it.")
			say(RASKOV_PA, "Welcome to Site 9, Major. You've come a long way to die underground.", 1.5)
			_goal("Fight through the bunker to the server room", "Go round the barrier and through the door at the back of the hall (marker)", Vector3(10, 20.5, 648))
			_spawn_segment5()
		"s5_server":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(OVERWATCH, "Command center is up the stairs on the west side of the data core. Behind the glass.", 0.5)
			_goal("Find the command center door", "Go up the stairs on the west side of the server room", game.seg5.BREACH_POS + Vector3(0, 1.6, -0.4))
		"s5_breach":
			game.seg5.set_ambience(false)
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(VANCE, "At the command center door. It's quiet. Too quiet.", 0.3, true)
			say(OVERWATCH, "Plant the charge. On your go, Major.")
			say(RASKOV_PA, "You can still walk away, Major. The Protocol ends wars. Whoever holds it, nobody dares fight them.", 1.5)
			say(RASKOV_PA, "And ask yourself who told me you were coming. Your own side sold you, Vance.", 0.8)
			say(VANCE, "That's not peace, Raskov. That's a leash.")
			_goal("Blow the door open", "Stand at the door and HOLD  F  to plant the charge, then step back", game.seg5.BREACH_POS + Vector3(0, 1.6, -0.4))
		"s5_raskov":
			hud.prompt("")
			_goal("Kill Raskov before the buyer 'H' arrives", "He is the officer in the red beret.  His guards will cover him")
		"s5_vault":
			game.seg5.set_ambience(true)
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			say(VANCE, "Raskov is down.", 1.0, true)
			say(OVERWATCH, "...Good. The Protocol is in the vault behind the command center. Get it.", 0.3)
			say(OVERWATCH, "And check his console on the way. I want to know who tipped him off.")
			_goal("Use Raskov's key on the vault door", "Go to the vault (marker) and HOLD  F", game.seg5.VAULT_POS + Vector3(0, 1.7, -0.5))
		"s5_drive":
			hud.prompt("")
			_goal("Grab the Horizon Protocol drive", "Walk up to the glowing drive and press  F", game.seg5.DRIVE_POS + Vector3(0, 0.4, 0))
		"end":
			hud.prompt("")
			game.drive_secured()
			game.seg5.drive.visible = false
			hud.hint("HORIZON PROTOCOL SECURED", 3.0)
			say(VANCE, "Overwatch, I have the Horizon Protocol. Coming back to you.", 0.5, true)
			say(OVERWATCH, "Copy. Nightingale's inbound... Elena, Hale's on board. He wants the drive handed to him personally.")
			say(VANCE, "Then let's not keep the Colonel waiting.")
			get_tree().create_timer(4.0).timeout.connect(func(): game.seg5.spawn_helicopter())
			_goal("Go back to Reyes and the truck at the entrance", "Follow the marker out of the bunker", game.seg4.truck.global_position + Vector3(0, 2.5, 0))
			_go_quiet("e_return")
		"e_extract":
			hud.set_objective("")
			hud.prompt("")
			_twist_sequence()
		"s6_infil":
			hud.title("SEGMENT 6", "The Buyer     |     Vostok Airfield, 06:40")
			game.set_checkpoint(game.player.global_position, game.player.rotation.y, false)
			say(VANCE, "Any Allied station, this is Major Vance. Nightingale is compromised. Colonel Hale is 'H'. He has the Protocol.", 2.5, true)
			say(COMMAND, "...Vance? This is Command. We copy. We can't touch Hale while that airfield tower is up - it's giving his buyer's jet clearance.", 1.0)
			say(COMMAND, "Kill the tower radar and we can hold the airspace. After that he's not going anywhere.")
			say(VANCE, "And Reyes?")
			say(COMMAND, "Heat signature in hangar one. Could be him.")
			_goal("Get inside Vostok airfield", "Sneak in through the broken fence by the fuel tanks (marker), or fight through the gate", Vector3(-101, 1.5, game.seg6.FENCE_Z))
		"s6_tower":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			say(VANCE, "I'm inside the wire.", 0.3)
			say(COMMAND, "Tower's to the east. Radar console is in the glass cab at the top.")
			_goal("Take out the tower radar", "Climb the stairs on the east side of the control tower, then HOLD  F  at the green radar screen", game.seg6.TOWER_CONSOLE + Vector3(0, 1.3, 0))
		"s6_reyes":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			hud.prompt("")
			game.seg6.kill_radar()
			hud.banner("!!  RADAR DOWN  -  THE JET HAS NO CLEARANCE  !!", 4.0)
			say(COMMAND, "Radar's dark. Fighters are holding the airspace. Hale is grounded.", 1.0, true)
			say(HALE, "Elena. You just don't know when to quit. Men, she's in the tower. Burn it down.", 1.0)
			_goal("Find Reyes in Hangar 1", "Hale's men are holding him in the OPS office at the back of Hangar 1 (marker)", game.seg6.OFFICE_DOOR + Vector3(0, 1.6, 0))
			_spawn_seg6_reinforce(0)
		"s6_hale":
			game.set_checkpoint(game.player.global_position, game.player.rotation.y)
			hud.prompt("")
			_hale_sequence()
		"s6_end":
			hud.prompt("")
			hud.set_objective("")
			_finale_sequence()


func _intro_sequence() -> void:
	await story.intro()
	get_tree().create_timer(0.6).timeout.connect(func():
		game.hud.title("THE HORIZON PROTOCOL", "Segment 1  —  The Perimeter Breach     |     Timberline Outpost, 04:52"))


func _go_quiet(new_step: String) -> void:
	step = new_step
	_step_t = 0.0


func skip() -> void:
	match step:
		"s6_infil":
			game.player.global_position = Vector3(-101, 0.4, game.seg6.FENCE_Z + 4.0)
			return
		"s6_tower":
			game.player.global_position = game.seg6.TOWER_CONSOLE + Vector3(0, 0.3, -1.2)
			_task_progress = 99.0
			return
		"s6_reyes":
			_door_open = true
			game.seg6.open_office_door()
			game.player.global_position = game.seg6.REYES_POS + Vector3(1.0, 0.3, 0)
			_task_progress = 99.0
			return
		"s6_hale":
			if _hale and is_instance_valid(_hale):
				_hale.take_hit(99999.0, _hale.eye(), Vector3.ZERO)
			return
		"e_return":
			game.player.global_position = game.seg4.truck.global_position + Vector3(3, 0.5, 0)
		"s1_intro":
			game.player.global_position = game.seg1.WIRE_POS + Vector3(0, game.terrain.height_at(0, -32) + 0.3, -2.0)
		"s1_cut":
			_cut_progress = 99.0
		"s1_sniper":
			if game.seg1.sniper:
				game.seg1.sniper.take_hit(999, game.seg1.sniper.eye(), Vector3.ZERO)
		"s1_downhill":
			game.player.global_position = Vector3(20, 0.5, game.terrain.YARD_Z + 4.0)
		"s2_enter":
			game.player.global_position = Vector3(38, 0.3, 105)
		"s2_admin":
			game.player.global_position = game.seg2.TERMINAL_POS + Vector3(-1.0, 0.3, 0.2)
		"s2_download":
			_dl_progress = 99.0
		"s3_blackout", "s3_catwalk":
			for e in _wave:
				if is_instance_valid(e) and not e.dead():
					e.take_hit(999, e.eye(), Vector3.ZERO)
			if step == "s3_catwalk":
				_step_t = 99.0
		"s3_down":
			game.player.global_position = Vector3(43.0, game.seg2.FLOOR_H + 0.3, 112.0)
		"s3_window":
			if _near3(game.seg2.WINDOW_POS, 2.8):
				_go("s4_escape")
			else:
				game.player.global_position = game.seg2.WINDOW_POS + Vector3(1.0, 0.3, 0)
				_step_t = 99.0
		"s4_ride":
			game.seg4.s = maxf(game.seg4.s, game.seg4.s_end - 25.0)
		"s5_enter":
			game.player.global_position = Vector3(10, 19.3, 668)
		"s5_server":
			game.player.global_position = game.seg5.BREACH_POS + Vector3(0, 0.3, -1.8)
		"s5_breach":
			_breach_progress = 99.0
		"s5_raskov":
			for e in _wave + [_raskov]:
				if is_instance_valid(e) and not e.dead():
					e.take_hit(9999, e.eye(), Vector3.ZERO)
		"s5_vault":
			_vault_progress = 99.0
			game.player.global_position = game.seg5.VAULT_POS + Vector3(0, 0.3, -2.0)
		"e_return":
			if _near3(game.seg4.truck.global_position, 7.0):
				_go("e_extract")
		"s5_drive":
			if _near3(game.seg5.DRIVE_POS, 2.2):
				_go("end")
			else:
				game.player.global_position = game.seg5.DRIVE_POS + Vector3(0, -0.8, -1.2)


# ------------------------------------------------------------------ segment 1

func _spawn_segment1() -> void:
	var t = game.terrain
	var seg1 = game.seg1
	var tp: Vector3 = seg1.TOWER_POS
	seg1.sniper = game.spawn_enemy(tp + Vector3(0.6, 9.2, -0.6), [], true, true, 0.0, "Tower")
	# Fence patrol just inside the wire
	game.spawn_enemy(Vector3(-24, t.height_at(-24, -24), -24), [Vector3(-24, 0, -24), Vector3(16, 0, -23)], false, false, 0.0)
	# Road patrol
	game.spawn_enemy(Vector3(22, 0, 26), [Vector3(22, 0, 26), Vector3(21, 0, -6)], false, false, PI)
	# Guard at the tower base, and one by the sawmill
	game.spawn_enemy(tp + Vector3(3, 0, 4), [tp + Vector3(3, 0, 4), tp + Vector3(-5, 0, 5), tp + Vector3(-4, 0, -3)], false, false, PI)
	game.spawn_enemy(Vector3(-24, 0, 12), [], false, true, PI * 0.8)


func _do_cut(delta: float) -> void:
	var hud = game.hud
	if not _near(game.seg1.WIRE_POS, 3.2):
		hud.prompt("")
		_cut_progress = 0.0
		return
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		var before := _cut_progress
		_cut_progress += delta / 2.4
		if int(before * 4) != int(_cut_progress * 4):
			S.play3d(game, "cut", game.seg1.WIRE_POS + Vector3(0, 1, 0), -6.0)
		hud.prompt("Cutting the wire...", _cut_progress)
	else:
		_cut_progress = maxf(0.0, _cut_progress - delta)
		hud.prompt("Hold  F  to cut the wire", _cut_progress if _cut_progress > 0 else -1.0)
	if _cut_progress >= 1.0:
		game.seg1.cut_wire()
		_go("s1_sniper")


# ------------------------------------------------------------------ segment 2 / 3

func _spawn_segment2() -> void:
	var seg2 = game.seg2
	var lanes: Array = seg2.lanes
	# Container maze patrols (walk along the lanes)
	for i in [1, 4, 7, 10]:
		if i < lanes.size():
			var z: float = lanes[i]
			game.spawn_enemy(Vector3(-50, 0, z), [Vector3(-58, 0, z), Vector3(-4, 0, z)], false, false, 0.0)
	# Yard between the generators and the road
	game.spawn_enemy(Vector3(2, 0, 150), [Vector3(2, 0, 150), Vector3(-6, 0, 170), Vector3(10, 0, 168)])
	game.spawn_enemy(Vector3(26, 0, 70), [Vector3(26, 0, 60), Vector3(26, 0, 98)])   # loading bay
	# Warehouse W1: floor + catwalk
	game.spawn_enemy(Vector3(54, 0, 70), [Vector3(54, 0, 62), Vector3(54, 0, 94), Vector3(62, 0, 94)])
	game.spawn_enemy(Vector3(50, 3.7, 76.8), [Vector3(40, 3.7, 76.8), Vector3(72, 3.7, 76.8)])
	# Admin block: one per floor
	game.spawn_enemy(Vector3(43, 0.1, 106), [], false, true, PI * 0.5)
	game.spawn_enemy(Vector3(41, 3.7, 112), [Vector3(38, 3.7, 112), Vector3(44, 3.7, 102)])
	game.spawn_enemy(Vector3(44, 7.3, 110), [], false, true, PI)


func _do_download(delta: float) -> void:
	var hud = game.hud
	if not _near3(game.seg2.TERMINAL_POS, 2.6):
		hud.prompt("Return to the terminal")
		return
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		_dl_progress += delta / 7.0
		hud.prompt("Downloading encrypted logs...  %d%%" % int(minf(_dl_progress, 1.0) * 100), _dl_progress)
		if int((_dl_progress - delta / 7.0) * 10) != int(_dl_progress * 10):
			S.play3d(game, "beep", game.seg2.TERMINAL_POS + Vector3(0, 1.2, -0.9), -8.0)
	else:
		hud.prompt("Hold  F  to download the encrypted logs" + ("  (%d%%)" % int(_dl_progress * 100) if _dl_progress > 0 else ""), _dl_progress if _dl_progress > 0 else -1.0)
	if _dl_progress >= 0.5 and _dl_progress - delta / 7.0 < 0.5:
		say(OVERWATCH, "Halfway. Something's spiking on the facility grid... keep going.", 0.0, true)
	if _dl_progress >= 1.0:
		_go("s3_blackout")


func _do_catwalk_wave(delta: float) -> void:
	# Four soldiers push through the catwalk door, calling signals as they come
	var door: Vector3 = game.seg2.CATWALK_DOOR
	var t := _step_t
	var spawn_times := [2.0, 3.5, 7.0, 9.0]
	var commands := ["MOVE UP!", "COVER ME!", "FLANK LEFT!", "GRENADE OUT!"]
	while _wave_spawned < spawn_times.size() and t > spawn_times[_wave_spawned]:
		var e = game.spawn_enemy(door + Vector3(randf_range(-0.5, 0.5), 0.2, -4.0 - _wave_spawned * 1.5), [], false, false, 0.0, "Vanguard")
		e.health = 120.0
		e.alert(game.player.global_position)
		e.shout(commands[_wave_spawned])
		_wave.append(e)
		_wave_spawned += 1
	_shout_t -= delta
	if _shout_t <= 0.0 and _wave_spawned > 0:
		_shout_t = randf_range(3.0, 5.0)
		var alive := _wave.filter(func(e): return is_instance_valid(e) and not e.dead())
		if alive.size() > 0:
			alive.pick_random().shout(["PUSH! PUSH!", "HE'S BEHIND THE DESKS!", "RELOADING!", "HOLD THE DOOR!", "SUPPRESSING!"].pick_random())


func _do_window(_delta: float) -> void:
	var hud = game.hud
	if _near3(game.seg2.WINDOW_POS, 2.8) and _step_t > 3.0:
		hud.prompt("Press  F  to JUMP")
		if Input.is_action_just_pressed("interact"):
			_go("s4_escape")
	elif _near3(game.seg2.WINDOW_POS, 2.8):
		hud.prompt("Wait for the truck...")
	else:
		hud.prompt("")


func _wave_dead(w: Array) -> bool:
	return _alive_in(w) == 0


func _alive_in(w: Array) -> int:
	var n := 0
	for e in w:
		if is_instance_valid(e) and not e.dead():
			n += 1
	return n


# ------------------------------------------------------------------ segment 4 / 5

func on_seg4_event(name: String) -> void:
	var hud = game.hud
	match name:
		"landed":
			_go("s4_ride")
		"gate":
			hud.title("SEGMENT 4", "The Escape Vector     |     The Mountain Access Pass")
			game.set_atmosphere("mountain")
			game.seg2.stop_alarm()
			say(OVERWATCH, "Hold on, gate!", 0.0, true)
		"techs1":
			say(OVERWATCH, "Kranor gun trucks on our six! Light 'em up, Vance! Take out the gunners!", 0.5, true)
		"bridge_warn":
			say(OVERWATCH, "Bridge coming up. It's older than both of us. Hang on!", 0.0, true)
		"techs2":
			say(OVERWATCH, "Two more coming up fast behind us!", 0.0, true)
			say(OVERWATCH, "Argh! I'm hit... I can't hold the wheel! Vance, get up here and DRIVE! I'll cover the back!", 2.5)
			get_tree().create_timer(6.0).timeout.connect(_offer_wheel)
			say("Raskov (intercept)", "All units: stop that truck. I don't care what it costs.", 1.0)
		"tunnel":
			say(OVERWATCH, "Tunnel's collapsed! Taking the old service road around it!", 0.0, true)
		"roadblock_warn":
			say(OVERWATCH, "Roadblock! That's Raskov's checkpoint. Get down, we're going through!", 0.0, true)
			hud.hint("CROUCH!  (C)", 3.0)
			var rb: Vector3 = game.seg4.pos_at(game.seg4.s_roadblock)
			var f: Vector3 = game.seg4.dir_at(game.seg4.s_roadblock)
			var left := Vector3.UP.cross(f).normalized()
			for k in [-6.5, 6.5]:
				var e = game.spawn_enemy(rb + left * k + f * 3.0 + Vector3(0, 0.5, 0), [], false, true, 0.0, "Checkpoint")
				e.alert(game.player.global_position)
		"bunker_gate":
			game.seg5.smash_gate()
			say(OVERWATCH, "Bunker gate! BRACE!", 0.0, true)
		"crash":
			_go("s5_enter")


var _wheel_offered := false
var _wheel_hold := 0.0
var _wheel_t := 0.0


## Reyes is hit: tell the player to climb into the cab
func _offer_wheel() -> void:
	if not step.begins_with("s4") or game.seg4.player_driving or not game.seg4.active:
		return
	_wheel_offered = true
	_wheel_hold = 0.0
	_wheel_t = 0.0
	_goal("Reyes is hit!  Climb into the driver's seat", "HOLD  F  to climb over into the cab and take the wheel", game.seg4.driver_anchor)


func _do_wheel(delta: float) -> void:
	if not _wheel_offered or game.seg4.player_driving:
		return
	_wheel_t += delta
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		_wheel_hold += delta / 1.0
		game.hud.prompt("Climbing into the cab...", _wheel_hold)
	else:
		_wheel_hold = maxf(0.0, _wheel_hold - delta)
		game.hud.prompt("HOLD  F  to take the wheel", _wheel_hold if _wheel_hold > 0.0 else -1.0)
	if _wheel_hold >= 1.0 or _wheel_t > 25.0:     # Reyes can't hold on forever
		_wheel_offered = false
		game.hud.prompt("")
		game.hud.fade_to(1.0, 0.2)
		S.play2d(game, "door", -4.0)
		get_tree().create_timer(0.35).timeout.connect(func():
			_take_wheel()
			game.hud.fade_to(0.0, 0.4))


func _take_wheel() -> void:
	if not step.begins_with("s4") or game.seg4.player_driving or not game.seg4.active:
		return
	game.seg4.start_player_drive()
	_goal("Drive to Raskov's bunker - dodge the falling rocks", "W = gas,  S = brake,  A / D = steer.  Stay on the road")
	say(VANCE, "I've got the wheel! Hold on, Reyes!", 0.2, true)


## Objective + a how-to hint so it's always obvious what to do next
func _goal(text: String, how: String = "", marker = null) -> void:
	game.hud.set_objective(text, marker)
	if how != "":
		game.hud.hint(how, 7.0)


func _spawn_segment5() -> void:
	var y := 19.1
	game.spawn_enemy(Vector3(4, y, 612), [], false, true, PI).alert(game.player.global_position)
	game.spawn_enemy(Vector3(16, y, 628), [], false, true, PI).alert(game.player.global_position)
	game.spawn_enemy(Vector3(10, y, 652), [Vector3(10, y, 640), Vector3(10, y, 657)])
	game.spawn_enemy(Vector3(31, y, 640), [Vector3(31, y, 622), Vector3(31, y, 656)])
	game.spawn_enemy(Vector3(-6, y, 670), [Vector3(-6, y, 664), Vector3(-6, y, 688)])
	game.spawn_enemy(Vector3(12, y, 680), [Vector3(8, y, 668), Vector3(14, y, 688)])
	game.spawn_enemy(Vector3(24, y, 684), [Vector3(20, y, 666), Vector3(28, y, 688)])
	game.spawn_enemy(Vector3(-9, 22.1, 690.5), [], false, true, 0.0)


func _do_breach(delta: float) -> void:
	var hud = game.hud
	if _breach_armed:
		return
	if not _near3(game.seg5.BREACH_POS + Vector3(0, 0, -1.5), 3.2):
		hud.prompt("")
		return
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		_breach_progress += delta / 2.5
		hud.prompt("Planting breaching charge...", _breach_progress)
	else:
		hud.prompt("Hold  F  to plant the breaching charge", _breach_progress if _breach_progress > 0 else -1.0)
	if _breach_progress >= 1.0:
		_breach_armed = true
		hud.prompt("")
		hud.hint("STAND BACK", 2.5)
		for i in 3:
			get_tree().create_timer(0.6 + i * 0.6).timeout.connect(func(): S.play3d(game, "beep", game.seg5.BREACH_POS + Vector3(0, 1.2, 0), 0.0))
		get_tree().create_timer(2.4).timeout.connect(_breach_go)


func _breach_go() -> void:
	game.seg5.blow_breach_door()
	game.player.add_shake(1.5)
	game.slow_motion(0.35, 2.5)
	_wave = []
	var cy := 22.1
	for p in [Vector3(-4, cy, 697), Vector3(6, cy, 698), Vector3(14, cy, 700)]:
		var e = game.spawn_enemy(p, [], false, false, PI, "Guard")
		e.health = 130.0
		e.alert(game.player.global_position)
		_wave.append(e)
	_raskov = game.spawn_enemy(Vector3(10, cy, 703), [], false, false, PI, "Raskov")
	_raskov.health = 650.0
	_raskov.body.scale = Vector3(1.08, 1.08, 1.08)
	for c in _raskov.body.get_children():
		if c is MeshInstance3D and c.position.y > 1.6:
			c.material_override = M_red()
	_raskov.alert(game.player.global_position)
	get_tree().create_timer(0.8).timeout.connect(func():
		if is_instance_valid(_raskov):
			_raskov.shout("YOU'RE TOO LATE, MAJOR!"))
	_go("s5_raskov")


func M_red() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.08, 0.06)
	m.roughness = 0.8
	return m


func _do_vault(delta: float) -> void:
	var hud = game.hud
	if not _near3(game.seg5.VAULT_POS + Vector3(0, 0, -1.2), 3.0):
		hud.prompt("")
		if _vault_progress < 99.0:
			return
	if Input.is_action_pressed("interact") and game.player.controls_enabled:
		_vault_progress += delta / 3.0
		hud.prompt("Entering code 4-7-1-9 from Raskov's logs...", _vault_progress)
	elif _vault_progress < 1.0:
		hud.prompt("Hold  F  to enter the vault code from the logs (4719)", _vault_progress if _vault_progress > 0 else -1.0)
	if _vault_progress >= 1.0:
		game.seg5.open_vault()
		_go("s5_drive")


# ------------------------------------------------------------------ events

## Who is talking in Vance's ear: Reyes, or Command while Hale has him
func _handler() -> String:
	return COMMAND if step in ["e_extract", "s6_infil", "s6_tower", "s6_reyes", "s6_freed"] else OVERWATCH


func on_alert(_enemy) -> void:
	if _alert_lines < 3 and _t > 5.0:
		var lines := ["You've been made! Put them down or break line of sight!", "Contact! They know you're there, Vance!", "More movement, they're converging on you!"]
		say(_handler(), lines[_alert_lines], 0.0, true)
		_alert_lines += 1


func on_enemy_killed(enemy) -> void:
	if enemy == game.seg1.sniper or enemy == _raskov:
		if enemy == _raskov:
			game.hud.hint("RASKOV NEUTRALIZED", 3.0)
		return
	if _kill_lines < 4 and randf() < 0.6:
		var lines := ["Tango down.", "Good kill.", "He's down. Keep moving.", "Clean. Nobody saw that."]
		say(_handler(), lines[_kill_lines], 0.3, true)
		_kill_lines += 1


func on_respawn() -> void:
	if step.begins_with("s4"):
		say(OVERWATCH, "Vance! Stay down in the bed, I've got you!", 0.5, true)
	else:
		say(_handler(), "Vance, you still with me? ...Okay. Take it slower this time.", 1.0, true)


# ------------------------------------------------------------------ radio

func say(speaker: String, text: String, delay := 0.4, priority := false, jammed := false) -> void:
	var orig := text
	if jammed:
		var chars := text.split("")
		for i in chars.size():
			if chars[i] != " " and randf() < 0.22:
				chars[i] = ["#", "-", "~", "/"].pick_random()
		text = "".join(chars)
	var entry := {"speaker": speaker, "text": text, "delay": delay, "orig": orig}
	if priority:
		_radio_queue.push_front(entry)
	else:
		_radio_queue.append(entry)


func _process_radio(delta: float) -> void:
	if game.cutscene_active:
		return
	_radio_wait -= delta
	if _radio_wait > 0.0 or _radio_queue.is_empty():
		return
	var e: Dictionary = _radio_queue[0]
	e.delay -= delta
	if e.delay > 0.0:
		return
	_radio_queue.pop_front()
	var duration := clampf(1.5 + e.text.length() * 0.055, 2.5, 8.0)
	var vlen: float = Voice.play(game, e.speaker, e.get("orig", e.text))
	if vlen > 0.0:
		duration = vlen + 0.6
	game.hud.radio(e.speaker, e.text, duration)
	if not String(e.speaker).contains("overheard"):
		S.play2d(game, "radio", -12.0, 0.03)
		get_tree().create_timer(duration - 0.3).timeout.connect(func(): S.play2d(game, "radio_out", -16.0, 0.03))
	_radio_wait = duration + 0.2


# ------------------------------------------------------------------ helpers

func _near(pos: Vector3, dist: float) -> bool:
	var p: Vector3 = game.player.global_position
	return Vector2(p.x - pos.x, p.z - pos.z).length() < dist


func _near3(pos: Vector3, dist: float) -> bool:
	return game.player.global_position.distance_to(pos) < dist


func _marker(pos: Vector3, up: float) -> Vector3:
	return Vector3(pos.x, game.terrain.height_at(pos.x, pos.z) + up, pos.z)


# ------------------------------------------------------------------ segment 6: the buyer

var _task_progress := 0.0
var _door_open := false
var _hale
var _hale_phase := 0
var _reyes_shot_t := 5.0
var _seg6_wave: Array = []


## Generic "stand here and hold F" objective
func _hold_task(delta: float, pos: Vector3, radius: float, seconds: float, text: String, next_step: String) -> void:
	var hud = game.hud
	if _near3(pos, radius):
		if Input.is_action_pressed("interact"):
			_task_progress += delta / seconds
		hud.prompt(text, _task_progress if _task_progress > 0.0 else -1.0)
		if _task_progress >= 1.0:
			_task_progress = 0.0
			hud.prompt("")
			_go(next_step)
	else:
		if _task_progress > 0.0 or hud._prompt.text == text:
			hud.prompt("")
		_task_progress = 0.0


func _twist_sequence() -> void:
	game.player.controls_enabled = false
	_radio_queue.clear()
	await story.twist()
	# Vance comes round alone. Twenty minutes later she rolls up to Vostok in Raskov's gun truck.
	game.hud.fade_to(1.0, 0.01)
	game.seg1.visible = false
	game.seg2.visible = false
	game.seg4.visible = false
	game.seg6.visible = true
	await get_tree().create_timer(0.3).timeout
	game.hud.title("TWENTY MINUTES LATER", "")
	await get_tree().create_timer(2.2).timeout
	game.seg5.visible = false
	game.set_atmosphere("dawn")
	var p = game.player
	p.global_position = game.seg6.START_POS
	p.rotation.y = deg_to_rad(195.0)   # facing north, toward the airfield
	p.velocity = Vector3.ZERO
	p.stance = 1
	p._apply_stance(true)
	p.health = p.MAX_HEALTH
	p.controls_enabled = true
	p.move_enabled = true
	game.spawn_supply_cache(game.seg6.START_POS + Vector3(2.0, 0, 3.0))
	game.seg6.spawn_reyes_prisoner()
	_spawn_segment6()
	game.hud.fade_to(0.0, 2.5)
	_go("s6_infil")


func _seg6_guard(pos: Vector3, patrol: Array = [], stationary := false, yaw := 0.0, sniper := false):
	var e = game.spawn_enemy(pos, patrol, sniper, stationary, yaw, "Merc")
	e.health = 110.0
	_seg6_wave.append(e)
	return e


func _spawn_segment6() -> void:
	var F: float = game.seg6.FENCE_Z
	# gate + perimeter
	_seg6_guard(Vector3(24, 0.3, F + 4), [], true, 0.0)
	_seg6_guard(Vector3(35, 0.3, F + 5), [], true, 0.3)
	_seg6_guard(Vector3(-60, 0.3, F + 8), [Vector3(-110, 0.3, F + 8), Vector3(-20, 0.3, F + 8)])
	_seg6_guard(Vector3(-95, 0.3, F + 14), [Vector3(-95, 0.3, F + 14), Vector3(-80, 0.3, F + 24), Vector3(-100, 0.3, F + 26)])
	# tower: sniper in the cab + two at the base
	_seg6_guard(Vector3(100, 12.2, 1093.2), [], true, 0.0, true)
	_seg6_guard(Vector3(95, 0.3, 1087), [], true, PI * 0.9)
	_seg6_guard(Vector3(90, 0.3, 1088), [Vector3(90, 0.3, 1088), Vector3(80, 0.3, 1098), Vector3(92, 0.3, 1103)])
	# hangars
	_seg6_guard(Vector3(-62, 0.3, 1114), [Vector3(-62, 0.3, 1114), Vector3(-52, 0.3, 1124)])
	_seg6_guard(Vector3(-64, 0.3, 1109), [], true, -PI / 2.0)
	_seg6_guard(Vector3(-50, 0.3, 1136), [Vector3(-50, 0.3, 1136), Vector3(-10, 0.3, 1138)])
	_seg6_guard(Vector3(58, 0.3, 1118), [Vector3(58, 0.3, 1118), Vector3(60, 0.3, 1136)])
	# apron
	_seg6_guard(Vector3(20, 0.3, 1155), [Vector3(20, 0.3, 1155), Vector3(40, 0.3, 1170), Vector3(10, 0.3, 1180)])
	_seg6_guard(Vector3(-28, 0.3, 1166), [], true, PI)


func _spawn_seg6_reinforce(k: int) -> void:
	var spots := [[Vector3(62, 0.3, 1100), Vector3(56, 0.3, 1102)],
		[Vector3(58, 0.3, 1150), Vector3(64, 0.3, 1152), Vector3(52, 0.3, 1156)],
		[Vector3(-8, 0.3, 1120), Vector3(6, 0.3, 1122), Vector3(0, 0.3, 1110)]]
	for pos in spots[k]:
		var e = _seg6_guard(pos)
		e.alert(game.player.global_position)
		_wave.append(e)


func _do_reyes(delta: float) -> void:
	var s6 = game.seg6
	var hud = game.hud
	if not _door_open:
		_hold_task(delta, s6.OFFICE_DOOR, 2.2, 1.2, "Hold  F  to force the office door", "__door")
		if step == "__door":
			step = "s6_reyes"
			_door_open = true
			s6.open_office_door()
			say(REYES_LINE_SPEAKER, "Vance? Is that you? Door's open - get in here!", 0.2, true)
		return
	if s6.in_office(game.player.global_position):
		_hold_task(delta, s6.REYES_POS, 1.9, 1.5, "Hold  F  to cut Reyes loose", "__free")
		if step == "__free":
			step = "s6_reyes"
			_free_reyes()
	elif hud._prompt.text.begins_with("Hold  F  to cut"):
		hud.prompt("")


const REYES_LINE_SPEAKER := "Sgt. Reyes"


func _free_reyes() -> void:
	step = "s6_freed"
	await story.reyes_free()
	_go("s6_hale")


func _hale_sequence() -> void:
	await story.hale_intro()
	var s6 = game.seg6
	_wave = []
	_hale = game.spawn_enemy(s6.JET_POS + Vector3(-4.5, 0.3, -6.5), [], false, false, PI, "Hale")
	_hale.health = 900.0
	_hale.armor = 0.55
	_hale.headshot_mult = 2.2
	_hale.alert(game.player.global_position)
	_hale_phase = 0
	for pos in [Vector3(-10, 0.3, 1152), Vector3(12, 0.3, 1152), Vector3(-2, 0.3, 1176), Vector3(20, 0.3, 1168)]:
		var e = _seg6_guard(pos)
		e.alert(game.player.global_position)
		_wave.append(e)
	_goal("Stop Colonel Hale", "He wears body armour: aim for the head.  Reyes is covering you from Hangar 1", _hale)
	game.hud.hint("BOSS:  COLONEL ADRIAN HALE", 3.0)
	step = "s6_hale"


func _do_hale(delta: float) -> void:
	if _hale == null or not is_instance_valid(_hale):
		return
	var s6 = game.seg6
	# the jet keeps spooling up while Hale is alive (it can't leave - no radar - but it's loud)
	s6.set_jet_power(minf(1.0, s6.jet_engines + delta * 0.01))
	var frac: float = _hale.health / 900.0
	if _hale_phase == 0 and frac < 0.66:
		_hale_phase = 1
		_hale.shout("GET OUT HERE AND KILL HER!")
		say(HALE, "Everyone on the apron! Now!", 0.0, true)
		_spawn_seg6_reinforce(1)
	elif _hale_phase == 1 and frac < 0.33:
		_hale_phase = 2
		_hale.shout("YOU CAN'T WIN THIS, ELENA!")
		say(REYES_LINE_SPEAKER, "More of them coming out of hangar two! He's running out of men, Vance!", 0.0, true)
		_spawn_seg6_reinforce(2)
	# Reyes covers from the hangar door: picks off mercs near him now and then
	_reyes_shot_t -= delta
	if _reyes_shot_t <= 0.0:
		_reyes_shot_t = randf_range(4.0, 7.0)
		var rp := Vector3(-50, 1.5, 1128)
		for e in game.alive_enemies():
			if e != _hale and e.global_position.distance_to(rp) < 40.0:
				S.play3d(game, "enemy_rifle", rp, -2.0)
				e.take_hit(70.0, e.global_position + Vector3(0, 1.2, 0), Vector3.FORWARD)
				break
	if _hale.dead():
		_go("s6_end")


func _finale_sequence() -> void:
	for e in game.alive_enemies():
		e.take_hit(9999.0, e.global_position + Vector3(0, 1, 0), Vector3.FORWARD)
	await get_tree().create_timer(1.5).timeout
	await story.finale()
	game.finish_game()
