extends Control

const LAUNCHER_SCENE := "res://launcher/main_menu.tscn"
const GAME_SCENE := "res://games/cribbage/scenes/game.tscn"
const RULES := preload("res://games/cribbage/scripts/cribbage_rules.gd")

var _session: Node
var _bridge: Node
var _setup_overlay: Control
var _rules_overlay: Control
var _rotate_overlay: Control
var _setup_title: Label
var _mode_help: Label
var _count_label: Label
var _name_edit: LineEdit
var _continue_button: Button
var _setup_panel: PanelContainer
var _rules_panel: PanelContainer
var _setup_intro: Label
var _mode_row: HBoxContainer
var _count_row: HBoxContainer
var _name_row: HBoxContainer
var _setup_buttons: HBoxContainer
var _main_page: VBoxContainer
var _main_title: Label
var _main_subtitle: Label
var _main_mark: Label
var _main_actions: VBoxContainer
var _mode_buttons: Dictionary = {}
var _count_buttons: Dictionary = {}
var _selected_mode := "standard"
var _selected_count := 2
var _multiplayer := false


func _ready() -> void:
	_session = get_node("/root/CribbageSession")
	_bridge = get_node("/root/CribbageWebBridge")
	_bridge.call("request_landscape", true)
	_build_interface()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("0d1713")
	add_child(background)

	var main_margin := MarginContainer.new()
	main_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_margins(main_margin, 32)
	add_child(main_margin)
	_main_page = VBoxContainer.new()
	_main_page.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_page.add_theme_constant_override("separation", 18)
	main_margin.add_child(_main_page)
	var eyebrow := _label("GAMER PUB PRESENTS", 16, Color("c9a75d"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(eyebrow)
	_main_title = _label("CRIBBAGE", 72, Color("f5e0ad"))
	_main_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(_main_title)
	_main_subtitle = _label("The classic race to 121 — built for the whole table", 22, Color("aebfb4"))
	_main_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(_main_subtitle)
	_main_mark = _label("♣  ♦  15–2  ♥  ♠", 32, Color("d8b75e"))
	_main_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_page.add_child(_main_mark)
	_main_actions = VBoxContainer.new()
	_main_actions.custom_minimum_size.x = 430
	_main_actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_main_actions.add_theme_constant_override("separation", 12)
	_main_page.add_child(_main_actions)
	var single := _button("SINGLE PLAYER", true)
	single.pressed.connect(func() -> void: _open_setup(false))
	_main_actions.add_child(single)
	var multi := _button("MULTIPLAYER READY-UP", true)
	multi.disabled = not OS.has_feature("web")
	multi.tooltip_text = "Available in browser and Discord builds." if multi.disabled else "Play in the shared browser or Discord room."
	multi.pressed.connect(func() -> void: _open_setup(true))
	_main_actions.add_child(multi)
	var how := _button("HOW TO PLAY", false)
	how.pressed.connect(func() -> void: _rules_overlay.show())
	_main_actions.add_child(how)
	var back := _button("BACK TO GAMER PUB", false)
	back.pressed.connect(back_to_launcher)
	_main_actions.add_child(back)

	_setup_overlay = _build_setup_overlay()
	add_child(_setup_overlay)
	_rules_overlay = _build_rules_overlay()
	add_child(_rules_overlay)
	_rotate_overlay = _build_rotate_overlay()
	add_child(_rotate_overlay)


func _build_setup_overlay() -> Control:
	var overlay := _modal_base()
	overlay.hide()
	_setup_panel = PanelContainer.new()
	_setup_panel.custom_minimum_size = Vector2(920, 650)
	_setup_panel.add_theme_stylebox_override("panel", _panel_style(Color("17251f"), Color("b99445"), 22, 3))
	overlay.get_node("Center").add_child(_setup_panel)
	var margin := MarginContainer.new()
	_set_margins(margin, 28)
	_setup_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	_setup_title = _label("CHOOSE YOUR TABLE", 34, Color("f1d37d"))
	_setup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_setup_title)
	_setup_intro = _label("Pick a game type, then choose the exact table size.", 18, Color("c6d0c9"))
	_setup_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_setup_intro)
	_mode_row = HBoxContainer.new()
	_mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_row.add_theme_constant_override("separation", 12)
	column.add_child(_mode_row)
	for mode in ["standard", "partnership", "variant"]:
		var button := _button(RULES.mode_title(mode).to_upper(), mode == "standard")
		button.custom_minimum_size = Vector2(250, 66)
		button.toggle_mode = true
		button.button_pressed = mode == "standard"
		button.pressed.connect(_select_mode.bind(mode))
		_mode_row.add_child(button)
		_mode_buttons[mode] = button
	_mode_help = _label("Standard play for 2–4 individual players.", 17, Color("aebfb4"))
	_mode_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_help.custom_minimum_size.y = 50
	_mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_mode_help)
	_count_label = _label("NUMBER OF PLAYERS", 17, Color("f0cf76"))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_count_label)
	_count_row = HBoxContainer.new()
	_count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_count_row.add_theme_constant_override("separation", 10)
	column.add_child(_count_row)
	for count in range(2, 7):
		var count_button := _button(str(count), count == 2)
		count_button.custom_minimum_size = Vector2(86, 58)
		count_button.toggle_mode = true
		count_button.button_pressed = count == 2
		count_button.pressed.connect(_select_count.bind(count))
		_count_row.add_child(count_button)
		_count_buttons[count] = count_button
	_name_row = HBoxContainer.new()
	_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name_row.add_theme_constant_override("separation", 12)
	column.add_child(_name_row)
	_name_row.add_child(_label("YOUR NAME", 16, Color("d9c79b")))
	_name_edit = LineEdit.new()
	_name_edit.text = "You"
	_name_edit.placeholder_text = "Player name"
	_name_edit.max_length = 32
	_name_edit.custom_minimum_size = Vector2(350, 52)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_row.add_child(_name_edit)
	_setup_buttons = HBoxContainer.new()
	_setup_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_setup_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_setup_buttons)
	var cancel := _button("BACK", false)
	cancel.custom_minimum_size.x = 180
	cancel.pressed.connect(func() -> void: overlay.hide())
	_setup_buttons.add_child(cancel)
	_continue_button = _button("PLAY WITH BOTS", true)
	_continue_button.custom_minimum_size.x = 300
	_continue_button.pressed.connect(_continue_to_game)
	_setup_buttons.add_child(_continue_button)
	_update_setup_controls()
	return overlay


func _build_rules_overlay() -> Control:
	var overlay := _modal_base()
	overlay.hide()
	_rules_panel = PanelContainer.new()
	_rules_panel.custom_minimum_size = Vector2(900, 700)
	_rules_panel.add_theme_stylebox_override("panel", _panel_style(Color("17211d"), Color("b99445"), 22, 3))
	overlay.get_node("Center").add_child(_rules_panel)
	var margin := MarginContainer.new()
	_set_margins(margin, 26)
	_rules_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := _label("HOW TO PLAY CRIBBAGE", 30, Color("f1d37d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var rules := RichTextLabel.new()
	rules.bbcode_enabled = true
	rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules.add_theme_font_size_override("normal_font_size", 17)
	rules.add_theme_font_size_override("bold_font_size", 18)
	rules.text = _rules_text()
	column.add_child(rules)
	var close := _button("BACK", true)
	close.pressed.connect(func() -> void: overlay.hide())
	column.add_child(close)
	return overlay


func _build_rotate_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("0b1511")
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var message := _label("↻\nROTATE TO LANDSCAPE\nCribbage needs a wider table.", 34, Color("f2d37b"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(message)
	return overlay


func _open_setup(multiplayer: bool) -> void:
	_multiplayer = multiplayer
	_setup_title.text = "MULTIPLAYER TABLE" if multiplayer else "SINGLE-PLAYER TABLE"
	_continue_button.text = "CONTINUE TO READY-UP" if multiplayer else "PLAY WITH BOTS"
	if multiplayer:
		var suggested := String(_bridge.call("suggested_name"))
		if not suggested.is_empty() and suggested != "Player":
			_name_edit.text = suggested
	_setup_overlay.show()


func _select_mode(mode: String) -> void:
	_selected_mode = mode
	_selected_count = RULES.valid_player_counts(mode)[0]
	_update_setup_controls()


func _select_count(count: int) -> void:
	if not RULES.valid_player_counts(_selected_mode).has(count):
		return
	_selected_count = count
	_update_setup_controls()


func _update_setup_controls() -> void:
	for mode in _mode_buttons:
		_mode_buttons[mode].set_pressed_no_signal(mode == _selected_mode)
	var valid_counts := RULES.valid_player_counts(_selected_mode)
	for count in _count_buttons:
		_count_buttons[count].visible = valid_counts.has(count)
		_count_buttons[count].set_pressed_no_signal(count == _selected_count)
	match _selected_mode:
		"partnership":
			_mode_help.text = "Two-seat play, or four players with opposite partners sharing a score."
		"variant":
			_mode_help.text = "House rules: five individual players, or six players in three opposite-seat teams."
		_:
			_mode_help.text = "Standard play for 2–4 individual players."
	_count_label.text = "NUMBER OF PLAYERS  •  %d" % _selected_count


func _continue_to_game() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "You"
	_session.set("player_name", player_name)
	_session.call("configure", _selected_mode, _selected_count, _multiplayer)
	get_tree().change_scene_to_file(GAME_SCENE)


func _apply_responsive_layout() -> void:
	var viewport := get_viewport_rect().size
	var window_size := Vector2(get_window().size)
	_rotate_overlay.visible = window_size.y > window_size.x
	var compact := window_size.x < 1050 or window_size.y < 620
	_main_page.add_theme_constant_override("separation", 12 if compact else 18)
	_main_title.add_theme_font_size_override("font_size", 96 if compact else 72)
	_main_subtitle.add_theme_font_size_override("font_size", 32 if compact else 22)
	_main_mark.add_theme_font_size_override("font_size", 44 if compact else 32)
	_main_actions.add_theme_constant_override("separation", 12)
	_main_actions.custom_minimum_size.x = minf(900, viewport.x - 80) if compact else 430
	for button in _main_actions.get_children():
		button.custom_minimum_size.y = 96 if compact else 54
		button.add_theme_font_size_override("font_size", 30 if compact else 17)
	_setup_panel.custom_minimum_size = Vector2(minf(1800, viewport.x - 30), minf(820, viewport.y - 30)) if compact else Vector2(920, 650)
	_rules_panel.custom_minimum_size = Vector2(minf(1800, viewport.x - 30), minf(820, viewport.y - 30)) if compact else Vector2(900, 700)
	var setup_margin: MarginContainer = _setup_panel.get_child(0)
	_set_margins(setup_margin, 24 if compact else 28)
	var setup_column: VBoxContainer = setup_margin.get_child(0)
	setup_column.add_theme_constant_override("separation", 10 if compact else 16)
	_setup_intro.visible = not compact
	_setup_title.add_theme_font_size_override("font_size", 52 if compact else 34)
	_mode_help.custom_minimum_size.y = 60 if compact else 50
	_mode_help.add_theme_font_size_override("font_size", 26 if compact else 17)
	_count_label.add_theme_font_size_override("font_size", 26 if compact else 17)
	_name_edit.custom_minimum_size.y = 86 if compact else 52
	_name_edit.add_theme_font_size_override("font_size", 28 if compact else 18)
	var mode_width := (minf(1800, viewport.x - 30) - 100) / 3.0
	for button in _mode_buttons.values():
		button.custom_minimum_size = Vector2(mode_width if compact else 250, 100 if compact else 66)
		button.add_theme_font_size_override("font_size", 28 if compact else 17)
	for button in _count_buttons.values():
		button.custom_minimum_size = Vector2(150 if compact else 86, 90 if compact else 58)
		button.add_theme_font_size_override("font_size", 32 if compact else 17)
	for button in _setup_buttons.get_children():
		button.custom_minimum_size.y = 92 if compact else 54
		button.add_theme_font_size_override("font_size", 28 if compact else 17)


func back_to_launcher() -> void:
	_bridge.call("request_landscape", false)
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


func _modal_base() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.035, 0.028, 0.94)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	return overlay


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 54
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("172019") if accent else Color("f1dfb2"))
	button.add_theme_color_override("font_hover_color", Color("101711") if accent else Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color("d5b45e") if accent else Color("26372f"), Color("8d7135"), 12, 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("edcf77") if accent else Color("344b40"), Color("f3d783"), 12, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("f4db8a") if accent else Color("405a4d"), Color("fff1ae"), 12, 3))
	button.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("fff1ae"), 12, 3))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("1a241f"), Color("354139"), 12, 1))
	return button


func _panel_style(background: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_top = 10
	style.content_margin_right = 14
	style.content_margin_bottom = 10
	return style


func _set_margins(container: MarginContainer, amount: int) -> void:
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_%s" % side, amount)


func _rules_text() -> String:
	return """[b][color=#f1d37d]THE RACE[/color][/b]
Be first to 121 points. Scores are shared by partners in four-player Partnership and by opposite-seat partners in the six-player Variant.

[b][color=#f1d37d]DEAL & CRIB[/color][/b]
Two players receive six cards and discard two each. Three and four players receive five and discard one; the three-player crib also receives one card from the deck. In the five-player Variant, the dealer gets four while everyone else gets five and discards one. In the six-player Variant, the dealer and dealer's partner get four; the other four players get five and discard one.

[b][color=#f1d37d]PEGGING[/color][/b]
Starting left of the dealer, play a card without taking the running count over 31. Score 2 for 15 or 31, 2/6/12 for a pair/triple/quad, and the length of a run of three or more. The last card before a go scores 1. The count then resets.

[b][color=#f1d37d]SHOW[/color][/b]
Score every combination totaling 15, pairs, runs, four- or five-card flushes, and a jack matching the starter's suit. Non-dealers count first, the dealer counts last, then the dealer's crib. Cutting a jack gives the dealer's team 2 points immediately.
"""
