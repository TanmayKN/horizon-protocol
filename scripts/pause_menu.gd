extends CanvasLayer
## Esc menu: resume, restart from checkpoint, mouse sensitivity, difficulty, quit.

var game
var panel: PanelContainer
var sens_slider: HSlider
var diff_option: OptionButton
var open := false


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
	help.text = "WASD move  |  Shift sprint  |  C crouch / slide  |  Z prone\nQ / E lean  |  LMB fire  |  RMB aim  |  R reload  |  F interact"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65))
	vb.add_child(help)
	visible = false


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(cb)
	parent.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if open:
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
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restart() -> void:
	_resume()
	game.player.take_damage(999, game.player.global_position)
