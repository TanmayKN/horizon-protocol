extends CanvasLayer
## On-screen HUD: objectives, radio subtitles, crosshair, ammo, health, detection, damage, mud.

var game
var _objective: Label
var _radio_name: Label
var _radio_text: Label
var _radio_panel: PanelContainer
var _title: Label
var _subtitle: Label
var _hint: Label
var _prompt: Label
var _prompt_bar: ProgressBar
var _ammo: Label
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _stance: Label
var _detect: ProgressBar
var _detect_label: Label
var _click: Label
var _vignette: TextureRect
var _fade: ColorRect
var _hitmarker: Label
var _cross: Control
var _marker: Label
var _mud_layer: Control
var _dmg_arrow: Label
var _slot_labels: Array = []
var _caliber: Label
var _scope: Control

var _radio_hide := 0.0
var _hint_hide := 0.0
var _title_t := -1.0
var _vig := 0.0
var _hit_t := 0.0
var _marker_pos = null
var _dmg_from := Vector3.ZERO
var _dmg_t := 0.0
var _mud_tex: Texture2D
var _t := 0.0


func _ready() -> void:
	layer = 5
	_vignette = TextureRect.new()
	_vignette.texture = _radial_tex(Color(0.6, 0.0, 0.0, 0.0), Color(0.6, 0.0, 0.0, 0.85))
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	# Subtle permanent dark vignette for mood
	var mood := TextureRect.new()
	mood.texture = _radial_tex(Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	mood.set_anchors_preset(Control.PRESET_FULL_RECT)
	mood.stretch_mode = TextureRect.STRETCH_SCALE
	mood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mood)

	_mud_layer = Control.new()
	_mud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mud_layer)
	_mud_tex = _blob_tex()

	_objective = _label("", 19, Color(0.92, 0.92, 0.86))
	_place(_objective, Control.PRESET_TOP_LEFT, 28, 22, 800, 50)

	_detect = ProgressBar.new()
	_detect.show_percentage = false
	_detect.max_value = 1.0
	_place(_detect, Control.PRESET_CENTER_TOP, -90, 70, 90, 76)
	_style_bar(_detect, Color(1, 0.8, 0.2))
	_detect_label = _label("", 13, Color(1, 0.85, 0.3))
	_place(_detect_label, Control.PRESET_CENTER_TOP, -150, 78, 150, 98)
	_detect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_title = _label("", 46, Color(0.95, 0.95, 0.9))
	_place(_title, Control.PRESET_CENTER, -600, -120, 600, -60)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle = _label("", 20, Color(0.75, 0.8, 0.8))
	_place(_subtitle, Control.PRESET_CENTER, -600, -55, 600, -20)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_radio_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_radio_panel.add_theme_stylebox_override("panel", sb)
	_place(_radio_panel, Control.PRESET_CENTER_BOTTOM, -430, -150, 430, -80)
	var vb := VBoxContainer.new()
	_radio_panel.add_child(vb)
	_radio_name = _label("", 14, Color(0.5, 0.95, 0.55), vb)
	_radio_text = _label("", 18, Color(0.92, 0.95, 0.9), vb)
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_panel.modulate.a = 0.0

	_hint = _label("", 18, Color(1, 0.9, 0.6))
	_place(_hint, Control.PRESET_CENTER, -400, 120, 400, 150)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_prompt = _label("", 20, Color.WHITE)
	_place(_prompt, Control.PRESET_CENTER, -300, 50, 300, 80)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_bar = ProgressBar.new()
	_prompt_bar.show_percentage = false
	_prompt_bar.max_value = 1.0
	_place(_prompt_bar, Control.PRESET_CENTER, -120, 84, 120, 92)
	_style_bar(_prompt_bar, Color(0.9, 0.9, 0.9))
	_prompt_bar.visible = false

	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.size = Vector2(2, 9) if i < 2 else Vector2(9, 2)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cross.add_child(r)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.9)
	dot.size = Vector2(2, 2)
	dot.position = Vector2(-1, -1)
	_cross.add_child(dot)

	_hitmarker = _label("X", 26, Color(1, 1, 1))
	_place(_hitmarker, Control.PRESET_CENTER, -20, -19, 20, 19)
	_hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker.modulate.a = 0.0

	_marker = _label("", 15, Color(1, 0.85, 0.35))
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.size = Vector2(120, 40)

	_dmg_arrow = _label("^", 40, Color(1, 0.2, 0.15))
	_dmg_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dmg_arrow.size = Vector2(40, 50)
	_dmg_arrow.pivot_offset = Vector2(20, 25)
	_dmg_arrow.modulate.a = 0.0

	# Bottom-left: health, stamina, stance
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.max_value = 100
	_place(_health_bar, Control.PRESET_BOTTOM_LEFT, 28, -64, 258, -54)
	_style_bar(_health_bar, Color(0.85, 0.9, 0.85))
	_stamina_bar = ProgressBar.new()
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = 6.0
	_place(_stamina_bar, Control.PRESET_BOTTOM_LEFT, 28, -48, 258, -44)
	_style_bar(_stamina_bar, Color(0.5, 0.75, 1.0))
	_stance = _label("", 14, Color(0.8, 0.85, 0.9))
	_place(_stance, Control.PRESET_BOTTOM_LEFT, 28, -36, 600, -14)

	_ammo = _label("", 30, Color(0.95, 0.95, 0.9))
	_place(_ammo, Control.PRESET_BOTTOM_RIGHT, -260, -70, -28, -30)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caliber = _label("", 13, Color(0.8, 0.8, 0.72))
	_place(_caliber, Control.PRESET_BOTTOM_RIGHT, -260, -30, -30, -12)
	_caliber.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Weapon slots (1 primary, 2 sidearm, 3 knife)
	for i in 5:
		var sl := _label("", 14, Color.WHITE)
		_place(sl, Control.PRESET_BOTTOM_RIGHT, -300, -210 + i * 22, -30, -190 + i * 22)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_slot_labels.append(sl)
	# Sniper scope overlay: a generated reticle image (clear circle, black ring, crosshairs)
	# plus black bars on the sides. No shaders, so it looks the same on every GPU.
	_scope = Control.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scope)
	var tr := TextureRect.new()
	tr.name = "reticle"
	tr.texture = _scope_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.add_child(tr)
	for side in ["bar_l", "bar_r"]:
		var bar := ColorRect.new()
		bar.name = side
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scope.add_child(bar)
	_scope.visible = false

	_click = _label("CLICK TO PLAY", 40, Color.WHITE)
	_place(_click, Control.PRESET_CENTER, -300, -30, 300, 30)
	_click.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _process(delta: float) -> void:
	_t += delta
	var p = game.player if game else null
	if p == null:
		return

	if _intel_panel and _intel_panel.visible and _t > _intel_hide:
		_intel_panel.modulate.a = move_toward(_intel_panel.modulate.a, 0.0, delta * 2.0)
		if _intel_panel.modulate.a <= 0.0:
			_intel_panel.visible = false

	# Radio / hint fade
	if _t > _radio_hide:
		_radio_panel.modulate.a = move_toward(_radio_panel.modulate.a, 0.0, delta * 2.5)
	if _t > _hint_hide:
		_hint.modulate.a = move_toward(_hint.modulate.a, 0.0, delta * 2.0)

	# Title card
	if _title_t >= 0.0:
		_title_t += delta
		var a := clampf(_title_t / 1.0, 0.0, 1.0) * clampf((6.0 - _title_t) / 1.5, 0.0, 1.0)
		_title.modulate.a = a
		_subtitle.modulate.a = a
		if _title_t > 6.0:
			_title_t = -1.0

	# Crosshair
	var spread: float = p.weapon.spread
	var gap := 6.0 + spread * 9.0
	var bars := _cross.get_children()
	bars[0].position = Vector2(-1, -gap - 9)
	bars[1].position = Vector2(-1, gap)
	bars[2].position = Vector2(-gap - 9, -1)
	bars[3].position = Vector2(gap, -1)
	_cross.modulate.a = move_toward(_cross.modulate.a, 0.0 if (p.aiming or p.sprinting or p.driving) else 1.0, delta * 8.0)

	_hit_t -= delta
	_hitmarker.modulate.a = clampf(_hit_t / 0.15, 0.0, 1.0)

	# Ammo / health / stamina
	var w = p.weapon
	_ammo.text = ("RELOADING" if w.reloading else "%d / %d" % [w.ammo, w.reserve])
	_ammo.modulate = Color(1, 0.4, 0.3) if w.ammo <= 5 and not w.reloading else Color.WHITE
	_ammo.visible = not p.driving and not w.is_melee()
	_caliber.visible = _ammo.visible
	_caliber.text = w.ammo_type() + "   " + String(w.def()["name"])
	for i in _slot_labels.size():
		var sl: Label = _slot_labels[i]
		var nm: String = w.weapon_name(i)
		var extra := ""
		if nm != "EMPTY" and not w.GUNS[w.slots[i]["id"]].get("melee", false):
			var sd: Dictionary = w.slots[i]
			extra = "  %d" % int(sd["mag"])
		sl.text = "[%d]  %s%s" % [i + 1, nm if nm != "EMPTY" else "- empty -", extra]
		sl.visible = not p.driving
		sl.modulate = Color(1, 0.85, 0.35, 1.0) if i == w.current else Color(1, 1, 1, 0.45)
	_health_bar.value = p.health
	_stamina_bar.value = p.stamina
	_stamina_bar.modulate.a = 1.0 if p.stamina < 5.9 else 0.3
	var names := ["STANDING", "CROUCHED", "PRONE  -  Space to stand"]
	_stance.text = names[p.stance] + ("   |   MUD" if p.in_mud else "")

	# Damage vignette
	var low := clampf(1.0 - p.health / 60.0, 0.0, 1.0)
	_vig = maxf(0.0, _vig - delta * 1.2)
	_vignette.modulate.a = maxf(_vig, low * 0.7)
	_dmg_t -= delta
	if _dmg_t > 0.0:
		var to: Vector3 = _dmg_from - p.global_position
		var local: Vector3 = p.global_transform.basis.inverse() * to
		var ang := atan2(local.x, -local.z)
		var vp := get_viewport().get_visible_rect().size
		_dmg_arrow.position = vp * 0.5 + Vector2(sin(ang), -cos(ang)) * 140.0 - Vector2(20, 25)
		_dmg_arrow.rotation = ang
		_dmg_arrow.modulate.a = clampf(_dmg_t, 0.0, 1.0)
	else:
		_dmg_arrow.modulate.a = 0.0

	# Detection meter
	var aw: float = game.max_awareness()
	_detect.value = aw
	_detect.visible = aw > 0.02
	var col := Color(1, 0.85, 0.2) if aw < 1.0 else Color(1, 0.2, 0.15)
	_detect.modulate = col
	_detect_label.modulate = col
	_detect_label.text = "" if aw < 0.02 else ("ALERTED" if aw >= 1.0 else "BEING NOTICED")

	# Objective marker
	if _marker_pos != null and not p.is_dead:
		var cam: Camera3D = p.camera
		var mp: Vector3
		if _marker_pos is Node3D:
			if not is_instance_valid(_marker_pos):
				_marker_pos = null
				return
			mp = _marker_pos.global_position + Vector3(0, 2.1, 0)
		else:
			mp = _marker_pos
		if not cam.is_position_behind(mp):
			var sp := cam.unproject_position(mp)
			_marker.visible = true
			_marker.position = sp - Vector2(60, 20)
			_marker.text = "◆\n%dm" % int(p.global_position.distance_to(mp))
		else:
			_marker.visible = false
	else:
		_marker.visible = false

	_click.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused and not p.is_dead

	# Mud blobs fade
	for blob in _mud_layer.get_children():
		blob.modulate.a -= delta * 0.12
		if blob.modulate.a <= 0.0:
			blob.queue_free()


# ------------------------------------------------------------------ API

func set_objective(text: String, marker = null) -> void:
	_objective.text = ("OBJECTIVE:  " + text) if text != "" else ""
	_marker_pos = marker


func radio(speaker: String, text: String, duration := 5.5) -> void:
	_radio_name.text = speaker.to_upper()
	_radio_name.modulate = Color(0.5, 0.95, 0.55)
	if speaker == "Vance":
		_radio_name.modulate = Color(0.55, 0.8, 1.0)
	elif speaker.begins_with("Raskov") or speaker.begins_with("RASKOV"):
		_radio_name.modulate = Color(1.0, 0.35, 0.3)
	elif speaker.begins_with("Nightingale"):
		_radio_name.modulate = Color(1.0, 0.85, 0.4)
	_radio_text.text = text
	_radio_panel.modulate.a = 1.0
	_radio_hide = _t + duration


func title(line1: String, line2: String) -> void:
	_title.text = line1
	_subtitle.text = line2
	_title_t = 0.0


func set_scope(on: bool) -> void:
	if _scope.visible != on:
		_scope.visible = on
		_cross.visible = not on
	if on:
		var vp := get_viewport().get_visible_rect().size
		var side_w := maxf(0.0, (vp.x - vp.y) * 0.5) + 2.0
		var bl: ColorRect = _scope.get_node("bar_l")
		var br: ColorRect = _scope.get_node("bar_r")
		bl.position = Vector2.ZERO
		bl.size = Vector2(side_w, vp.y)
		br.position = Vector2(vp.x - side_w, 0)
		br.size = Vector2(side_w, vp.y)


func _scope_texture() -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	for y in n:
		for x in n:
			var dx := x - c + 0.5
			var dy := y - c + 0.5
			var d := sqrt(dx * dx + dy * dy) / c          # 0 centre .. 1 edge
			var a := clampf((d - 0.94) / 0.03, 0.0, 1.0)  # black outside the lens
			a = maxf(a, clampf((d - 0.7) / 0.24, 0.0, 1.0) * 0.35)   # darker towards the rim
			var thin := absf(dx) < 1.0 or absf(dy) < 1.0
			var thick := (absf(dx) < 3.0 and absf(dy) > c * 0.3) or (absf(dy) < 3.0 and absf(dx) > c * 0.3)
			if (thin or thick) and d < 0.95:
				a = 1.0
			img.set_pixel(x, y, Color(0, 0, 0, a))
	# red dot in the middle
	for y in range(-2, 3):
		for x in range(-2, 3):
			img.set_pixel(int(c) + x, int(c) + y, Color(0.9, 0.1, 0.05, 1.0))
	return ImageTexture.create_from_image(img)


func hint(text: String, duration := 3.0) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	_hint_hide = _t + duration


func prompt(text: String, progress := -1.0) -> void:
	_prompt.text = text
	_prompt_bar.visible = progress >= 0.0
	_prompt_bar.value = maxf(progress, 0.0)


func hitmarker() -> void:
	_hit_t = 0.18


func damage(from_pos: Vector3, amount: float) -> void:
	_vig = clampf(_vig + amount / 30.0, 0.0, 1.0)
	_dmg_from = from_pos
	_dmg_t = 1.5


func mud_splash() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in randi_range(1, 3):
		var r := TextureRect.new()
		r.texture = _mud_tex
		var s := randf_range(60, 180)
		r.size = Vector2(s, s * randf_range(0.6, 1.1))
		r.stretch_mode = TextureRect.STRETCH_SCALE
		# Splashes land near the bottom and edges of the screen
		var edge := randi() % 3
		match edge:
			0: r.position = Vector2(randf_range(0, vp.x - s), vp.y - s * randf_range(0.3, 0.9))
			1: r.position = Vector2(randf_range(-s * 0.4, s * 0.3), randf_range(vp.y * 0.3, vp.y - s))
			2: r.position = Vector2(vp.x - s * randf_range(0.5, 1.0), randf_range(vp.y * 0.3, vp.y - s))
		r.rotation = randf() * TAU
		r.modulate = Color(1, 1, 1, randf_range(0.6, 0.9))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mud_layer.add_child(r)


func fade_to(alpha: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, time)


## Opening briefing typed out over black. Returns when finished or skipped.
var briefing_skip := false
func briefing(lines: Array) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -480
	box.offset_right = 480
	box.offset_top = -200
	box.offset_bottom = 220
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	move_child(box, get_child_count() - 1)
	var skip := _label("Click or press Space to skip", 13, Color(0.6, 0.6, 0.6))
	_place(skip, Control.PRESET_CENTER_BOTTOM, -200, -50, 200, -25)
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_child(skip, get_child_count() - 1)
	for i in lines.size():
		var big: bool = i < 2
		var l := _label("", 30 if i == 0 else (18 if big else 19), Color(0.95, 0.9, 0.7) if big else Color(0.85, 0.87, 0.88), box)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if big else HORIZONTAL_ALIGNMENT_LEFT
		var text: String = lines[i]
		for c in text.length():
			if briefing_skip:
				break
			l.text = text.substr(0, c + 1)
			if c % 3 == 0:
				await get_tree().create_timer(0.018).timeout
		l.text = text
		if briefing_skip:
			continue
		await get_tree().create_timer(0.5 if big else 0.9).timeout
	if not briefing_skip:
		await get_tree().create_timer(1.5).timeout
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	tw.parallel().tween_property(skip, "modulate:a", 0.0, 0.5)
	await tw.finished
	box.queue_free()
	skip.queue_free()


func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or event.is_action_pressed("jump"):
		briefing_skip = true


var _intel_panel: PanelContainer
var _intel_title: Label
var _intel_body: Label
var _intel_hide := 0.0


func show_intel(title: String, body: String, count: int, total: int) -> void:
	if _intel_panel == null:
		_intel_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.11, 0.09, 0.93)
		sb.border_color = Color(0.85, 0.75, 0.45, 0.8)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(18)
		_intel_panel.add_theme_stylebox_override("panel", sb)
		_place(_intel_panel, Control.PRESET_CENTER_RIGHT, -470, -170, -30, 170)
		var vb := VBoxContainer.new()
		_intel_panel.add_child(vb)
		_intel_title = _label("", 18, Color(0.95, 0.85, 0.5), vb)
		_intel_body = _label("", 16, Color(0.9, 0.9, 0.86), vb)
		_intel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_intel_body.custom_minimum_size = Vector2(400, 0)
	_intel_title.text = ("INTEL  %d / %d   -   %s" % [count, total, title]) if total > 0 else title
	_intel_body.text = body
	_intel_panel.visible = true
	_intel_panel.modulate.a = 1.0
	_intel_hide = _t + (10.0 if total > 0 else 16.0)


func end_card(line1: String, body: String) -> void:
	var t := _label(line1, 60, Color(0.95, 0.9, 0.7))
	_place(t, Control.PRESET_CENTER, -600, -170, 600, -90)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var b := _label(body, 22, Color(0.85, 0.88, 0.9))
	_place(b, Control.PRESET_CENTER, -600, -70, 600, 200)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_child(t, get_child_count() - 1)
	move_child(b, get_child_count() - 1)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func flash_red(alpha: float) -> void:
	_vig = maxf(_vig, alpha)


# ------------------------------------------------------------------ helpers

func _label(text: String, size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(l)
	return l


func _place(c: Control, preset: Control.LayoutPreset, l: float, t: float, r: float, b: float) -> void:
	if c.get_parent() == null:
		add_child(c)
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _radial_tex(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([inner, inner, outer])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 1.05)
	t.width = 256
	t.height = 256
	return t


func _blob_tex() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	for x in s:
		for y in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var v := 1.0 - d + n.get_noise_2d(x, y) * 0.6
			var a := clampf((v - 0.25) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.22, 0.15, 0.08, a * 0.9))
	return ImageTexture.create_from_image(img)
