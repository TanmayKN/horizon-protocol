extends CanvasLayer
## Esc menu: resume, restart from checkpoint, mouse sensitivity, difficulty, quit.

var game
var panel: PanelContainer
var sens_slider: HSlider
var diff_option: OptionButton
var open := false
var controls_panel: PanelContainer
var _rebind_action := ""
var _rebind_button: Button
var _bind_buttons := {}

## Rebindable actions shown on the Controls screen
const ACTIONS := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["sprint", "Sprint"], ["crouch", "Crouch / slide"], ["prone", "Prone"], ["jump", "Jump / stand up"],
	["lean_left", "Lean left"], ["lean_right", "Lean right"], ["fire", "Fire / knife slash"], ["aim", "Aim down sights"],
	["reload", "Reload"], ["interact", "Interact / pick up gun"], ["weapon_1", "Slot 1"], ["weapon_2", "Slot 2"],
	["weapon_3", "Slot 3"], ["weapon_4", "Slot 4"], ["weapon_5", "Slot 5"], ["drop_weapon", "Drop weapon"], ["toggle_view", "First / third person"],
]


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.92)
	sb.border_color = Color(0.9, 0.8, 0.4, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -230
	panel.offset_bottom = 230
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "THE HORIZON PROTOCOL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "PAUSED"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	vb.add_child(sub)
	_button(vb, "Resume", _resume)
	_button(vb, "Restart from checkpoint", _restart)
	_button(vb, "Intel & Story  (what you know)", _show_story)
	_button(vb, "Controls", _show_controls)
	_button(vb, "First / third person view  (V)", func(): game.player.toggle_view())
	var sl := Label.new()
	sl.text = "Mouse sensitivity"
	vb.add_child(sl)
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.3
	sens_slider.max_value = 2.5
	sens_slider.step = 0.05
	sens_slider.value = 1.0
	sens_slider.value_changed.connect(func(v): game.mouse_sens_mult = v)
	vb.add_child(sens_slider)
	var dl := Label.new()
	dl.text = "Difficulty"
	vb.add_child(dl)
	diff_option = OptionButton.new()
	diff_option.add_item("Recruit (easy)")
	diff_option.add_item("Regular")
	diff_option.add_item("Veteran (hard)")
	diff_option.select(1)
	diff_option.item_selected.connect(func(i): game.difficulty_mult = [0.55, 1.0, 1.5][i])
	vb.add_child(diff_option)
	_button(vb, "Quit game", func(): get_tree().quit())
	var help := Label.new()
	help.text = "Open Controls to see or change every key"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	vb.add_child(help)
	panel.offset_top = -295
	panel.offset_bottom = 295
	_build_controls()
	_build_story()
	visible = false


# ------------------------------------------------------------------ intel & story screen

var story_panel: PanelContainer
var story_text: RichTextLabel

const STORY_INTRO := "[b]YOUR MISSION[/b]\nYou are Major Elena Vance. Colonel Raskov of Vanguard Corp has stolen the [b]Horizon Protocol[/b], a drive that can switch off a country's defences, and he is about to sell it.\n1. Sneak into Timberline Outpost.  2. Steal Raskov's logs from the Kranor admin block to find where the drive is.\n3. Escape.  4. Drive up the pass to Site 9.  5. Kill Raskov and take the drive from the vault.\n"


func _build_story() -> void:
	story_panel = PanelContainer.new()
	story_panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel"))
	story_panel.set_anchors_preset(Control.PRESET_CENTER)
	story_panel.offset_left = -380
	story_panel.offset_right = 380
	story_panel.offset_top = -330
	story_panel.offset_bottom = 330
	add_child(story_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	story_panel.add_child(vb)
	var title := Label.new()
	title.text = "INTEL & STORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	vb.add_child(title)
	story_text = RichTextLabel.new()
	story_text.bbcode_enabled = true
	story_text.custom_minimum_size = Vector2(700, 520)
	story_text.scroll_active = true
	story_text.add_theme_font_size_override("normal_font_size", 15)
	story_text.add_theme_font_size_override("bold_font_size", 16)
	vb.add_child(story_text)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180, 36)
	back.pressed.connect(_hide_story)
	vb.add_child(back)
	story_panel.visible = false


func _show_story() -> void:
	var t := STORY_INTRO
	t += "\n[b]RIGHT NOW:[/b]  " + String(game.hud._objective.text).replace("OBJECTIVE:  ", "") + "\n"
	t += "\n[b]WHAT YOU HAVE FOUND[/b]  (intel %d / %d)\n" % [game.intel_found, game.intel_total]
	if game.story_log.is_empty():
		t += "Nothing yet. Look for red folders with a blue glow and press F to read them.\n"
	for e in game.story_log:
		t += "\n[color=#f2d98c][b]%s[/b][/color]\n%s\n" % [e["title"], e["body"]]
	story_text.text = t
	panel.visible = false
	story_panel.visible = true


func _hide_story() -> void:
	story_panel.visible = false
	panel.visible = true


# ------------------------------------------------------------------ controls screen

func _build_controls() -> void:
	controls_panel = PanelContainer.new()
	controls_panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel"))
	controls_panel.set_anchors_preset(Control.PRESET_CENTER)
	controls_panel.offset_left = -330
	controls_panel.offset_right = 330
	controls_panel.offset_top = -350
	controls_panel.offset_bottom = 350
	add_child(controls_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	controls_panel.add_child(vb)
	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	vb.add_child(title)
	var tip := Label.new()
	tip.text = "Click a key, then press the new key (or mouse button). Esc cancels."
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.65, 0.67, 0.7))
	vb.add_child(tip)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	for a in ACTIONS:
		var l := Label.new()
		l.text = a[1]
		l.custom_minimum_size = Vector2(150, 0)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(130, 30)
		b.pressed.connect(_start_rebind.bind(a[0], b))
		grid.add_child(b)
		_bind_buttons[a[0]] = b
	var fixed := Label.new()
	fixed.text = "Mouse: look   |   Mouse wheel: switch weapon   |   Esc: pause"
	fixed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fixed.add_theme_font_size_override("font_size", 12)
	fixed.add_theme_color_override("font_color", Color(0.65, 0.67, 0.7))
	vb.add_child(fixed)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(180, 36)
	reset.pressed.connect(_reset_defaults)
	row.add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180, 36)
	back.pressed.connect(_hide_controls)
	row.add_child(back)
	controls_panel.visible = false


func _key_name(action: String) -> String:
	var evs := InputMap.action_get_events(action)
	var names: Array = []
	for ev in evs:
		if ev is InputEventKey:
			var k: Key = (ev as InputEventKey).physical_keycode
			if k == KEY_NONE:
				k = (ev as InputEventKey).keycode
			names.append(OS.get_keycode_string(k))
		elif ev is InputEventMouseButton:
			var mb: MouseButton = (ev as InputEventMouseButton).button_index
			names.append({MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_MIDDLE: "Middle mouse"}.get(mb, "Mouse %d" % mb))
	return " / ".join(names) if not names.is_empty() else "-"


func _refresh_bindings() -> void:
	for a in _bind_buttons:
		(_bind_buttons[a] as Button).text = _key_name(a)


func _show_controls() -> void:
	_refresh_bindings()
	panel.visible = false
	controls_panel.visible = true


func _hide_controls() -> void:
	_rebind_action = ""
	controls_panel.visible = false
	story_panel.visible = false
	panel.visible = true


func _start_rebind(action: String, b: Button) -> void:
	_rebind_action = action
	_rebind_button = b
	b.text = "press a key..."


func _input(event: InputEvent) -> void:
	if _rebind_action == "" or not open:
		return
	var ok := false
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_rebind_action = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		ok = true
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		ok = true
	if ok:
		var ev: InputEvent = event.duplicate()
		if ev is InputEventKey:
			var ke := ev as InputEventKey
			if ke.physical_keycode == KEY_NONE:
				ke.physical_keycode = ke.keycode
		# The key can only do one thing: take it away from any other action
		for a in ACTIONS:
			for old in InputMap.action_get_events(a[0]):
				if _same(old, ev):
					InputMap.action_erase_event(a[0], old)
		InputMap.action_erase_events(_rebind_action)
		InputMap.action_add_event(_rebind_action, ev)
		_rebind_action = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()


func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


func _reset_defaults() -> void:
	for a in ACTIONS:
		InputMap.action_erase_events(a[0])
	game.setup_inputs()
	_refresh_bindings()


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(cb)
	parent.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if open and story_panel.visible:
			_hide_story()
		elif open and controls_panel.visible:
			_hide_controls()
		elif open:
			_resume()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	open = false
	visible = false
	controls_panel.visible = false
	story_panel.visible = false
	panel.visible = true
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart() -> void:
	_resume()
	game.player.take_damage(999, game.player.global_position)
