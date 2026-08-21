class_name TenkGame
extends Control
## Local hot-seat implementation of the Gamer Pub 10,000 ruleset.

const LAUNCHER_SCENE := "res://launcher/main_menu.tscn"
const WINNING_SCORE := 10_000
const OPENING_SCORE := 1_000
const RULES := preload("res://games/tenk/scripts/tenk_rules.gd")
const DIE_TEXTURES: Array[Texture2D] = [
	preload("res://shared/assets/Dice/die_red_1.png"),
	preload("res://shared/assets/Dice/die_red_2.png"),
	preload("res://shared/assets/Dice/die_red_3.png"),
	preload("res://shared/assets/Dice/die_red_4.png"),
	preload("res://shared/assets/Dice/die_red_5.png"),
	preload("res://shared/assets/Dice/die_red_6.png"),
]

var players: Array[Dictionary] = []
var current_player := 0
var turn_score := 0
var dice_to_roll := 6
var current_roll: Array[int] = []
var locked_indices := PackedInt32Array()
var locked_batches: Array = []
var go_for_used := false
var rescue_mode := false
var hot_hand_ready := false
var awaiting_next_player := false
var game_over := false

var _score_list: GridContainer
var _turn_badge: Label
var _status_label: Label
var _turn_score_label: Label
var _roll_detail_label: Label
var _dice_row: HBoxContainer
var _selection_label: Label
var _roll_button: Button
var _keep_button: Button
var _activity_log: RichTextLabel
var _setup_overlay: Control
var _player_count: SpinBox
var _name_edits: Array[LineEdit] = []
var _rules_overlay: Control
var _winner_overlay: Control
var _winner_label: Label
var _screen_margin: MarginContainer
var _page: VBoxContainer
var _header_panel: PanelContainer
var _header_row: HBoxContainer
var _back_button: Button
var _title_label: Label
var _subtitle_label: Label
var _rules_button: Button
var _body: GridContainer
var _scoreboard_panel: PanelContainer
var _score_heading: Label
var _score_goal: Label
var _table_panel: PanelContainer
var _table_margin: MarginContainer
var _table_column: VBoxContainer
var _dice_center: CenterContainer
var _actions: HBoxContainer
var _activity_panel: PanelContainer
var _footer_label: Label
var _setup_panel: PanelContainer
var _rules_panel: PanelContainer
var _rules_text_label: RichTextLabel
var _winner_panel: PanelContainer
var _modal_buttons: Array[Button] = []
var _portrait_layout := false


func _ready() -> void:
	_set_web_voice_visible(true)
	randomize()
	_build_interface()
	get_viewport().size_changed.connect(_queue_responsive_layout)
	_apply_responsive_layout()
	_show_setup()


func _exit_tree() -> void:
	_set_web_voice_visible(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _setup_overlay.visible or _rules_overlay.visible:
		return
	if event.keycode == KEY_SPACE and not _roll_button.disabled:
		_on_roll_pressed()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and not _roll_button.disabled:
		_on_roll_pressed()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("130f19")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.position = Vector2(-520, -330)
	glow.size = Vector2(1040, 660)
	glow.color = Color(0.16, 0.30, 0.22, 0.34)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	_screen_margin = MarginContainer.new()
	_screen_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_margins(_screen_margin, 26, 22, 26, 22)
	add_child(_screen_margin)

	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 18)
	_screen_margin.add_child(_page)
	_page.add_child(_build_header())

	_body = GridContainer.new()
	_body.columns = 3
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("h_separation", 18)
	_body.add_theme_constant_override("v_separation", 18)
	_page.add_child(_body)
	_body.add_child(_build_scoreboard())
	_body.add_child(_build_table())
	_body.add_child(_build_activity_panel())

	_footer_label = Label.new()
	_footer_label.text = "SPACE / ENTER rolls or rerolls  •  Selected dice lock in place  •  Reach 1,000 in one turn to get on the board"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_color_override("font_color", Color("b8aa91"))
	_footer_label.add_theme_font_size_override("font_size", 14)
	_page.add_child(_footer_label)

	_setup_overlay = _build_setup_overlay()
	add_child(_setup_overlay)
	_rules_overlay = _build_rules_overlay()
	add_child(_rules_overlay)
	_winner_overlay = _build_winner_overlay()
	add_child(_winner_overlay)


func _queue_responsive_layout() -> void:
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout() -> void:
	_portrait_layout = get_viewport_rect().size.y > get_viewport_rect().size.x
	if _portrait_layout:
		_set_margins(_screen_margin, 36, 30, 36, 210)
		_page.add_theme_constant_override("separation", 20)
		_header_panel.custom_minimum_size.y = 124
		_header_row.add_theme_constant_override("separation", 18)
		_back_button.custom_minimum_size = Vector2(260, 88)
		_rules_button.custom_minimum_size = Vector2(180, 88)
		_title_label.add_theme_font_size_override("font_size", 48)
		_subtitle_label.add_theme_font_size_override("font_size", 18)
		_turn_badge.custom_minimum_size.x = 300
		_turn_badge.add_theme_font_size_override("font_size", 24)
		for button in [_back_button, _rules_button]:
			button.add_theme_font_size_override("font_size", 22)

		_body.columns = 1
		_body.add_theme_constant_override("h_separation", 20)
		_body.add_theme_constant_override("v_separation", 20)
		_scoreboard_panel.custom_minimum_size = Vector2(0, 410)
		_scoreboard_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scoreboard_panel.size_flags_vertical = Control.SIZE_FILL
		_score_heading.add_theme_font_size_override("font_size", 28)
		_score_goal.hide()
		_score_list.columns = 2
		_score_list.add_theme_constant_override("h_separation", 16)
		_score_list.add_theme_constant_override("v_separation", 12)

		_table_panel.custom_minimum_size = Vector2(0, 1450)
		_set_margins(_table_margin, 30, 30, 30, 34)
		_table_column.add_theme_constant_override("separation", 28)
		_status_label.custom_minimum_size.y = 110
		_status_label.add_theme_font_size_override("font_size", 34)
		_turn_score_label.add_theme_font_size_override("font_size", 42)
		_roll_detail_label.add_theme_font_size_override("font_size", 24)
		_dice_center.custom_minimum_size.y = 360
		_dice_row.add_theme_constant_override("separation", 18)
		_selection_label.custom_minimum_size.y = 100
		_selection_label.add_theme_font_size_override("font_size", 28)
		_actions.add_theme_constant_override("separation", 24)
		for button in [_roll_button, _keep_button]:
			button.custom_minimum_size = Vector2(350, 104)
			button.add_theme_font_size_override("font_size", 28)
		_activity_panel.hide()
		_footer_label.hide()
	else:
		_set_margins(_screen_margin, 26, 22, 26, 22)
		_page.add_theme_constant_override("separation", 18)
		_header_panel.custom_minimum_size.y = 76
		_header_row.add_theme_constant_override("separation", 16)
		_back_button.custom_minimum_size = Vector2(190, 0)
		_rules_button.custom_minimum_size = Vector2(130, 0)
		_title_label.add_theme_font_size_override("font_size", 34)
		_subtitle_label.add_theme_font_size_override("font_size", 12)
		_turn_badge.custom_minimum_size.x = 270
		_turn_badge.add_theme_font_size_override("font_size", 18)
		for button in [_back_button, _rules_button]:
			button.add_theme_font_size_override("font_size", 16)

		_body.columns = 3
		_body.add_theme_constant_override("h_separation", 18)
		_body.add_theme_constant_override("v_separation", 18)
		_scoreboard_panel.custom_minimum_size = Vector2(300, 0)
		_scoreboard_panel.size_flags_horizontal = Control.SIZE_FILL
		_scoreboard_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_score_heading.add_theme_font_size_override("font_size", 20)
		_score_goal.show()
		_score_list.columns = 1
		_score_list.add_theme_constant_override("h_separation", 12)
		_score_list.add_theme_constant_override("v_separation", 9)

		_table_panel.custom_minimum_size = Vector2.ZERO
		_set_margins(_table_margin, 30, 30, 30, 30)
		_table_column.add_theme_constant_override("separation", 17)
		_status_label.custom_minimum_size.y = 60
		_status_label.add_theme_font_size_override("font_size", 22)
		_turn_score_label.add_theme_font_size_override("font_size", 27)
		_roll_detail_label.add_theme_font_size_override("font_size", 15)
		_dice_center.custom_minimum_size.y = 184
		_dice_row.add_theme_constant_override("separation", 12)
		_selection_label.custom_minimum_size.y = 44
		_selection_label.add_theme_font_size_override("font_size", 16)
		_actions.add_theme_constant_override("separation", 12)
		for button in [_roll_button, _keep_button]:
			button.custom_minimum_size = Vector2(220, 58)
			button.add_theme_font_size_override("font_size", 16)
		_activity_panel.show()
		_footer_label.show()

	for die in _dice_row.get_children():
		if die is Button:
			die.custom_minimum_size = Vector2(170, 170) if _portrait_layout else Vector2(112, 112)
	_apply_modal_layout()
	if not players.is_empty():
		_update_scoreboard()


func _apply_modal_layout() -> void:
	_setup_panel.custom_minimum_size = Vector2(980, 1500) if _portrait_layout else Vector2(560, 650)
	_rules_panel.custom_minimum_size = Vector2(1180, 2400) if _portrait_layout else Vector2(860, 720)
	_winner_panel.custom_minimum_size = Vector2(900, 760) if _portrait_layout else Vector2(580, 360)
	_rules_text_label.add_theme_font_size_override("normal_font_size", 26 if _portrait_layout else 17)
	_rules_text_label.add_theme_font_size_override("bold_font_size", 28 if _portrait_layout else 18)
	_player_count.custom_minimum_size.y = 84 if _portrait_layout else 44
	for edit in _name_edits:
		edit.custom_minimum_size.y = 84 if _portrait_layout else 44
		edit.add_theme_font_size_override("font_size", 26 if _portrait_layout else 16)
	for button in _modal_buttons:
		button.custom_minimum_size.y = 92 if _portrait_layout else 52
		button.add_theme_font_size_override("font_size", 26 if _portrait_layout else 16)


func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


func _build_header() -> Control:
	_header_panel = PanelContainer.new()
	_header_panel.custom_minimum_size.y = 76
	_header_panel.add_theme_stylebox_override("panel", _panel_style(Color("211728"), Color("694b38"), 18))

	_header_row = HBoxContainer.new()
	_header_row.add_theme_constant_override("separation", 16)
	_header_panel.add_child(_header_row)

	_back_button = _make_button("‹  GAMER PUB", false)
	_back_button.name = "BackToLauncherButton"
	_back_button.custom_minimum_size.x = 190
	_back_button.pressed.connect(back_to_launcher)
	_header_row.add_child(_back_button)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_header_row.add_child(title_box)
	_title_label = _make_label("10,000", 34, Color("f6d37a"))
	title_box.add_child(_title_label)
	_subtitle_label = _make_label("ROLL BOLDLY. BANK WISELY.", 12, Color("ad9a7a"))
	title_box.add_child(_subtitle_label)

	_turn_badge = _make_label("SET UP GAME", 18, Color("fff3ca"))
	_turn_badge.custom_minimum_size.x = 270
	_turn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_row.add_child(_turn_badge)

	_rules_button = _make_button("RULES", false)
	_rules_button.custom_minimum_size.x = 130
	_rules_button.pressed.connect(_open_rules)
	_header_row.add_child(_rules_button)
	return _header_panel


func _build_scoreboard() -> Control:
	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.custom_minimum_size.x = 300
	_scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(Color("1d1822"), Color("4f4036"), 18))
	var margin := _panel_margin(22)
	_scoreboard_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_score_heading = _make_label("SCOREBOARD", 20, Color("eac46c"))
	_score_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_score_heading)
	var rule := HSeparator.new()
	rule.modulate = Color("765b3f")
	column.add_child(rule)
	_score_list = GridContainer.new()
	_score_list.columns = 1
	_score_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_score_list.add_theme_constant_override("h_separation", 12)
	_score_list.add_theme_constant_override("v_separation", 9)
	column.add_child(_score_list)
	_score_goal = _make_label("FIRST TO 10,000 WINS", 13, Color("a9977b"))
	_score_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_score_goal)
	return _scoreboard_panel


func _build_table() -> Control:
	_table_panel = PanelContainer.new()
	_table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_panel.add_theme_stylebox_override("panel", _panel_style(Color("13251e"), Color("8c6c3f"), 24, 3))
	_table_margin = _panel_margin(30)
	_table_panel.add_child(_table_margin)
	_table_column = VBoxContainer.new()
	_table_column.add_theme_constant_override("separation", 17)
	_table_margin.add_child(_table_column)

	_status_label = _make_label("Choose players to begin.", 22, Color("fff2c3"))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 60
	_table_column.add_child(_status_label)

	_turn_score_label = _make_label("TURN SCORE  0", 27, Color("f2c95f"))
	_turn_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_column.add_child(_turn_score_label)

	_roll_detail_label = _make_label("Six dice are ready.", 15, Color("bcd2c6"))
	_roll_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_column.add_child(_roll_detail_label)

	_dice_center = CenterContainer.new()
	_dice_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dice_center.custom_minimum_size.y = 184
	_table_column.add_child(_dice_center)
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 12)
	_dice_center.add_child(_dice_row)

	_selection_label = _make_label("Roll the dice to begin your turn.", 16, Color("d8ccb2"))
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.custom_minimum_size.y = 44
	_table_column.add_child(_selection_label)

	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 12)
	_table_column.add_child(_actions)
	_roll_button = _make_button("ROLL 6 DICE", true)
	_roll_button.custom_minimum_size = Vector2(220, 58)
	_roll_button.pressed.connect(_on_roll_pressed)
	_actions.add_child(_roll_button)
	_keep_button = _make_button("KEEP IT", false)
	_keep_button.custom_minimum_size = Vector2(220, 58)
	_keep_button.pressed.connect(_on_keep_pressed)
	_actions.add_child(_keep_button)
	return _table_panel


func _build_activity_panel() -> Control:
	_activity_panel = PanelContainer.new()
	_activity_panel.custom_minimum_size.x = 300
	_activity_panel.add_theme_stylebox_override("panel", _panel_style(Color("1d1822"), Color("4f4036"), 18))
	var margin := _panel_margin(20)
	_activity_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	margin.add_child(column)
	var heading := _make_label("TABLE TALK", 20, Color("eac46c"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	_activity_log = RichTextLabel.new()
	_activity_log.bbcode_enabled = true
	_activity_log.fit_content = false
	_activity_log.scroll_active = true
	_activity_log.scroll_following = true
	_activity_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_activity_log.add_theme_font_size_override("normal_font_size", 15)
	_activity_log.add_theme_color_override("default_color", Color("d3c8b2"))
	column.add_child(_activity_log)
	return _activity_panel


func _build_setup_overlay() -> Control:
	var overlay := _modal_base("SetupOverlay")
	var center: CenterContainer = overlay.get_node("Center")
	_setup_panel = PanelContainer.new()
	_setup_panel.custom_minimum_size = Vector2(560, 650)
	_setup_panel.add_theme_stylebox_override("panel", _panel_style(Color("211923"), Color("d0a653"), 22, 3))
	center.add_child(_setup_panel)
	var margin := _panel_margin(30)
	_setup_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := _make_label("PULL UP A CHAIR", 30, Color("f3cf70"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var intro := _make_label("Choose 2–8 local players. Pass the dice when each turn ends.", 16, Color("d0c3ad"))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	count_row.add_theme_constant_override("separation", 16)
	column.add_child(count_row)
	count_row.add_child(_make_label("PLAYERS", 17, Color("f5e5bb")))
	_player_count = SpinBox.new()
	_player_count.min_value = 2
	_player_count.max_value = 8
	_player_count.step = 1
	_player_count.value = 2
	_player_count.custom_minimum_size = Vector2(110, 44)
	_player_count.value_changed.connect(_on_player_count_changed)
	count_row.add_child(_player_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 9)
	scroll.add_child(names)
	for index in range(8):
		var edit := LineEdit.new()
		edit.placeholder_text = "Player %d" % (index + 1)
		edit.text = "Player %d" % (index + 1)
		edit.custom_minimum_size.y = 44
		edit.add_theme_font_size_override("font_size", 16)
		edit.visible = index < 2
		names.add_child(edit)
		_name_edits.append(edit)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var back := _make_button("BACK", false)
	back.custom_minimum_size = Vector2(150, 52)
	back.pressed.connect(back_to_launcher)
	buttons.add_child(back)
	_modal_buttons.append(back)
	var start := _make_button("START GAME", true)
	start.custom_minimum_size = Vector2(220, 52)
	start.pressed.connect(_start_game)
	buttons.add_child(start)
	_modal_buttons.append(start)
	return overlay


func _build_rules_overlay() -> Control:
	var overlay := _modal_base("RulesOverlay")
	overlay.visible = false
	var center: CenterContainer = overlay.get_node("Center")
	_rules_panel = PanelContainer.new()
	_rules_panel.custom_minimum_size = Vector2(860, 720)
	_rules_panel.add_theme_stylebox_override("panel", _panel_style(Color("201923"), Color("c69c4b"), 22, 3))
	center.add_child(_rules_panel)
	var margin := _panel_margin(28)
	_rules_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := _make_label("HOW TO PLAY 10,000", 28, Color("f1cb67"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_rules_text_label = RichTextLabel.new()
	_rules_text_label.bbcode_enabled = true
	_rules_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules_text_label.add_theme_font_size_override("normal_font_size", 17)
	_rules_text_label.add_theme_font_size_override("bold_font_size", 18)
	_rules_text_label.add_theme_color_override("default_color", Color("ddd1bb"))
	_rules_text_label.text = _rules_text()
	column.add_child(_rules_text_label)
	var close := _make_button("BACK TO THE TABLE", true)
	close.custom_minimum_size.y = 52
	close.pressed.connect(_close_rules)
	column.add_child(close)
	_modal_buttons.append(close)
	return overlay


func _build_winner_overlay() -> Control:
	var overlay := _modal_base("WinnerOverlay")
	overlay.visible = false
	var center: CenterContainer = overlay.get_node("Center")
	_winner_panel = PanelContainer.new()
	_winner_panel.custom_minimum_size = Vector2(580, 360)
	_winner_panel.add_theme_stylebox_override("panel", _panel_style(Color("241a21"), Color("f2c85d"), 24, 4))
	center.add_child(_winner_panel)
	var margin := _panel_margin(34)
	_winner_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	margin.add_child(column)
	column.add_child(_make_label("🏆", 54, Color.WHITE))
	_winner_label = _make_label("", 28, Color("f5d573"))
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_winner_label)
	var again := _make_button("PLAY AGAIN", true)
	again.custom_minimum_size.y = 54
	again.pressed.connect(_show_setup)
	column.add_child(again)
	_modal_buttons.append(again)
	var pub := _make_button("BACK TO GAMER PUB", false)
	pub.custom_minimum_size.y = 50
	pub.pressed.connect(back_to_launcher)
	column.add_child(pub)
	_modal_buttons.append(pub)
	return overlay


func _modal_base(node_name: String) -> Control:
	var overlay := Control.new()
	overlay.name = node_name
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.018, 0.028, 0.94)
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	return overlay


func _show_setup() -> void:
	game_over = false
	if _winner_overlay:
		_winner_overlay.hide()
	_setup_overlay.show()
	_turn_badge.text = "SET UP GAME"


func _start_game() -> void:
	players.clear()
	for index in range(int(_player_count.value)):
		var player_name := _name_edits[index].text.strip_edges()
		if player_name.is_empty():
			player_name = "Player %d" % (index + 1)
		players.append({"name": player_name, "score": 0, "on_board": false})
	current_player = 0
	game_over = false
	_activity_log.clear()
	_setup_overlay.hide()
	_add_log("[color=#f2c85d]New game:[/color] first to 10,000 wins.")
	_begin_turn()


func _begin_turn() -> void:
	turn_score = 0
	dice_to_roll = 6
	current_roll.clear()
	locked_indices.clear()
	locked_batches.clear()
	go_for_used = false
	rescue_mode = false
	hot_hand_ready = false
	awaiting_next_player = false
	_clear_dice()
	var player: Dictionary = players[current_player]
	_status_label.text = "%s, roll all six dice." % player.name
	_selection_label.text = "Select scoring dice or a qualifying partial combination, then reroll."
	_roll_detail_label.text = "Six dice are ready."
	_add_log("[color=#f5e5bb]%s's turn[/color]" % player.name)
	_update_all_ui()


func _on_roll_pressed() -> void:
	if awaiting_next_player:
		return
	if current_roll.is_empty() or hot_hand_ready:
		hot_hand_ready = false
		locked_indices.clear()
		locked_batches.clear()
		current_roll = _random_dice(6)
		dice_to_roll = 6
		_present_hand(turn_score == 0 and not go_for_used)
		return
	_reroll_unselected_dice()


func _on_die_toggled(_pressed: bool, _index: int) -> void:
	_update_selection_preview()


func _update_selection_preview() -> void:
	var selected := _selected_values()
	var held := _locked_values()
	var eligible := RULES.can_lock_for_reroll(held, selected)
	var available_score := _current_hand_score()
	if selected.is_empty():
		_selection_label.text = "Select dice to lock before rerolling."
	elif eligible:
		_selection_label.text = "%d selected • current hand score %s" % [selected.size(), _number(available_score)]
	else:
		_selection_label.text = "That selection is not a scoring or qualifying partial combination."
	_update_all_ui()


func _on_keep_pressed() -> void:
	if awaiting_next_player:
		current_player = (current_player + 1) % players.size()
		_begin_turn()
		return
	var hand_score := _current_hand_score()
	if rescue_mode and hand_score <= 0:
		_finish_bust("Passed on the rescue reroll.")
		return
	if hand_score > 0 and _can_bank_score(hand_score):
		turn_score += hand_score
		_add_log("%s kept the hand for %d." % [players[current_player].name, hand_score])
		_finish_scoring_turn("Kept it")
	elif _can_bank():
		_finish_scoring_turn("Kept it")


func _reroll_unselected_dice() -> void:
	var selected := _selected_indices()
	var selected_values := _selected_values()
	if selected.is_empty() or not RULES.can_lock_for_reroll(_locked_values(), selected_values):
		return
	locked_batches.append(selected_values.duplicate())
	for index in selected:
		if not locked_indices.has(index):
			locked_indices.append(index)
	locked_indices.sort()

	if locked_indices.size() == 6:
		var full_score := RULES.score_persistent_hand(locked_batches)
		if not full_score.valid or not full_score.all_scoring:
			_finish_bust("The completed hand does not score — bust!")
			return
		turn_score += full_score.score
		dice_to_roll = 6
		hot_hand_ready = true
		rescue_mode = false
		_show_hand_dice()
		_status_label.text = "%s — AND ROLLING!" % full_score.label
		_roll_detail_label.text = "All six dice scored for %s." % _number(full_score.score)
		_selection_label.text = "Reroll all six dice, or keep it."
		_add_log("%s completed the hand for %d — and rolling." % [players[current_player].name, full_score.score])
		_update_all_ui()
		return

	if rescue_mode:
		go_for_used = true
		rescue_mode = false

	var rerolled_indices := _active_indices()
	var rolled_values: Array[int] = []
	for index in rerolled_indices:
		current_roll[index] = randi_range(1, 6)
		rolled_values.append(current_roll[index])
	dice_to_roll = rerolled_indices.size()
	var candidate := _best_lock_candidate()
	if candidate.is_empty():
		_show_hand_dice()
		_roll_detail_label.text = "Rerolled %s" % _dice_text(rolled_values)
		_finish_bust("The rerolled dice did not score or advance a combination — bust!")
		return
	_show_hand_dice(candidate)
	_status_label.text = "Select scoring dice or a qualifying partial combination, then reroll."
	_roll_detail_label.text = "Rerolled %s • %d dice remain active" % [_dice_text(rolled_values), rerolled_indices.size()]
	_update_selection_preview()


func _present_hand(opening_roll: bool) -> void:
	var best := RULES.best_scoring_selection(current_roll)
	rescue_mode = opening_roll and best.score <= 0
	var candidate := _best_lock_candidate()
	if candidate.is_empty():
		_show_hand_dice()
		_finish_bust("No scoring dice or qualifying partial combination — bust!")
		return
	_show_hand_dice(candidate)
	_roll_detail_label.text = "Rolled: %s" % _dice_text(current_roll)
	if rescue_mode:
		_status_label.text = "No score. Use the turn's one rescue reroll with a qualifying partial combination."
	else:
		_status_label.text = "Select dice to lock, then reroll every unselected die."
	_update_selection_preview()


func _best_lock_candidate() -> PackedInt32Array:
	var active := _active_indices()
	var best := PackedInt32Array()
	var best_priority := -1_000
	for mask in range(1, 1 << active.size()):
		var candidate := PackedInt32Array()
		for offset in range(active.size()):
			if mask & (1 << offset):
				candidate.append(active[offset])
		var values := _values_for_indices(candidate)
		if not RULES.can_lock_for_reroll(_locked_values(), values):
			continue
		var exact := RULES.score_selection(values)
		var combined_score := RULES.score_persistent_hand(locked_batches, values)
		if candidate.size() == active.size() and not combined_score.all_scoring:
			continue
		var priority := -candidate.size()
		if exact.valid:
			priority += 10_000 + exact.score
		if combined_score.valid:
			priority += 100_000 + combined_score.score
		if priority > best_priority:
			best_priority = priority
			best = candidate
	return best


func _finish_scoring_turn(reason: String) -> void:
	var player: Dictionary = players[current_player]
	var earned := turn_score
	var banked := _can_bank()
	if banked:
		player.score += earned
		player.on_board = true
		players[current_player] = player
		_status_label.text = "%s — %s banked %d points." % [reason, player.name, earned]
		_add_log("[color=#8ee0a7]%s banked %d (total %d).[/color]" % [player.name, earned, player.score])
		if player.score >= WINNING_SCORE:
			_show_winner(player)
			return
	else:
		_status_label.text = "%s, but %s needed 1,000 to get on the board. No points banked." % [reason, player.name]
		_add_log("[color=#dba078]%s scored %d but did not reach the 1,000-point opening.[/color]" % [player.name, earned])
		turn_score = 0

	current_roll.clear()
	locked_indices.clear()
	locked_batches.clear()
	hot_hand_ready = false
	rescue_mode = false
	awaiting_next_player = true
	_selection_label.text = "Pass the dice to the next player."
	_update_all_ui()


func _finish_bust(message: String) -> void:
	var lost := turn_score + _current_hand_score()
	turn_score = 0
	hot_hand_ready = false
	rescue_mode = false
	awaiting_next_player = true
	_status_label.text = message
	_selection_label.text = "The turn's %d point%s are lost. Pass the dice." % [lost, "" if lost == 1 else "s"]
	_add_log("[color=#e7887c]%s busted and lost %d.[/color]" % [players[current_player].name, lost])
	_update_all_ui()


func _show_winner(player: Dictionary) -> void:
	game_over = true
	awaiting_next_player = false
	_update_scoreboard()
	_winner_label.text = "%s wins with %s points!" % [player.name, _number(player.score)]
	_winner_overlay.show()
	_add_log("[color=#f5cf61][b]%s WINS![/b][/color]" % player.name)


func _show_hand_dice(preselected: PackedInt32Array = PackedInt32Array()) -> void:
	_clear_dice()
	for index in range(current_roll.size()):
		var locked := locked_indices.has(index)
		var die := Button.new()
		die.toggle_mode = not locked
		die.disabled = locked
		die.custom_minimum_size = Vector2(170, 170) if _portrait_layout else Vector2(112, 112)
		die.icon = DIE_TEXTURES[current_roll[index] - 1]
		die.expand_icon = true
		die.tooltip_text = "Die showing %d%s" % [current_roll[index], " — locked" if locked else " — click to select"]
		die.add_theme_stylebox_override("normal", _panel_style(Color("f0e5d0"), Color("7b5b42"), 15, 2))
		die.add_theme_stylebox_override("hover", _panel_style(Color("fff5df"), Color("f1cc68"), 15, 3))
		die.add_theme_stylebox_override("pressed", _panel_style(Color("f8dda0"), Color("fff0a0"), 15, 5))
		die.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("fff0a0"), 15, 3))
		die.set_pressed_no_signal(locked or preselected.has(index))
		if locked:
			die.modulate = Color(1.0, 0.82, 0.45, 0.72)
		else:
			die.toggled.connect(_on_die_toggled.bind(index))
		_dice_row.add_child(die)


func _clear_dice() -> void:
	for child in _dice_row.get_children():
		_dice_row.remove_child(child)
		child.queue_free()

func _selected_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for index in range(_dice_row.get_child_count()):
		if locked_indices.has(index):
			continue
		var die := _dice_row.get_child(index) as Button
		if die and die.button_pressed:
			indices.append(index)
	return indices


func _selected_values() -> Array[int]:
	return _values_for_indices(_selected_indices())


func _locked_values() -> Array[int]:
	return _values_for_indices(locked_indices)


func _values_for_indices(indices: PackedInt32Array) -> Array[int]:
	var values: Array[int] = []
	for index in indices:
		if index >= 0 and index < current_roll.size():
			values.append(current_roll[index])
	return values


func _active_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for index in range(current_roll.size()):
		if not locked_indices.has(index):
			indices.append(index)
	return indices


func _current_hand_score() -> int:
	if hot_hand_ready:
		return 0
	return int(RULES.score_persistent_hand(locked_batches, _selected_values()).score)


func _update_all_ui() -> void:
	_update_scoreboard()
	_update_turn_summary()
	_update_controls()


func _update_scoreboard() -> void:
	if not _score_list:
		return
	for child in _score_list.get_children():
		_score_list.remove_child(child)
		child.queue_free()
	for index in range(players.size()):
		var player: Dictionary = players[index]
		var row := PanelContainer.new()
		row.custom_minimum_size.y = 74 if _portrait_layout else 0
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var active := index == current_player and not game_over
		row.add_theme_stylebox_override("panel", _panel_style(
			Color("3a2c25") if active else Color("262129"),
			Color("e3b95b") if active else Color("443a35"),
			12,
			2 if active else 1
		))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		row.add_child(box)
		var marker := _make_label("●" if active else "○", 22 if _portrait_layout else 14, Color("f0c45b") if active else Color("756a61"))
		box.add_child(marker)
		var name_label := _make_label(player.name, 25 if _portrait_layout else 16, Color("fff0cd") if active else Color("d3c8b5"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(name_label)
		var score_text := _number(player.score)
		if not player.on_board:
			score_text = "—"
		var score_label := _make_label(score_text, 27 if _portrait_layout else 18, Color("f1ca67") if active else Color("b9aa8d"))
		box.add_child(score_label)
		_score_list.add_child(row)


func _update_turn_summary() -> void:
	if players.is_empty():
		return
	var player: Dictionary = players[current_player]
	_turn_badge.text = "%s  •  %s" % [player.name.to_upper(), _number(player.score)]
	if awaiting_next_player and turn_score > 0:
		_turn_score_label.text = "BANKED THIS TURN  %s" % _number(turn_score)
	else:
		_turn_score_label.text = "TURN SCORE  %s" % _number(turn_score + _current_hand_score())


func _update_controls() -> void:
	if players.is_empty() or game_over:
		_roll_button.disabled = true
		_keep_button.disabled = true
		return

	if awaiting_next_player:
		_roll_button.disabled = true
		_keep_button.text = "NEXT PLAYER"
		_keep_button.disabled = false
		return

	if current_roll.is_empty():
		_roll_button.text = "ROLL 6 DICE"
		_roll_button.disabled = false
	elif hot_hand_ready:
		_roll_button.text = "REROLL ALL 6"
		_roll_button.disabled = false
	else:
		_roll_button.text = "REROLL"
		var selected := _selected_values()
		var reroll_eligible := RULES.can_lock_for_reroll(_locked_values(), selected)
		if _selected_indices().size() == _active_indices().size():
			var completed_hand := RULES.score_persistent_hand(locked_batches, selected)
			reroll_eligible = completed_hand.valid and completed_hand.all_scoring
		_roll_button.disabled = not reroll_eligible

	_keep_button.text = "KEEP IT"
	var hand_score := _current_hand_score()
	if rescue_mode and hand_score <= 0:
		_keep_button.text = "END TURN (0)"
		_keep_button.disabled = false
	elif hand_score > 0:
		_keep_button.disabled = not _can_bank_score(hand_score)
	else:
		_keep_button.disabled = not _can_bank()
	if not players[current_player].on_board and turn_score + hand_score < OPENING_SCORE:
		_keep_button.tooltip_text = "Score at least 1,000 this turn to get on the board." if not players[current_player].on_board else "Select scoring dice to keep."
	else:
		_keep_button.tooltip_text = "Bank this turn's points and end the turn."


func _can_bank() -> bool:
	if players.is_empty() or turn_score <= 0:
		return false
	return players[current_player].on_board or turn_score >= OPENING_SCORE


func _can_bank_score(additional_score: int) -> bool:
	if players.is_empty() or additional_score <= 0:
		return false
	return players[current_player].on_board or turn_score + additional_score >= OPENING_SCORE


func _on_player_count_changed(value: float) -> void:
	for index in range(_name_edits.size()):
		_name_edits[index].visible = index < int(value)


func _open_rules() -> void:
	_rules_overlay.show()


func _close_rules() -> void:
	_rules_overlay.hide()


func back_to_launcher() -> void:
	_set_web_voice_visible(false)
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


func _set_web_voice_visible(visible: bool) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.GamerPubVoice?.setVisible(%s);" % ("true" if visible else "false")
	)


func _random_dice(count: int) -> Array[int]:
	var dice: Array[int] = []
	for _index in range(count):
		dice.append(randi_range(1, 6))
	return dice


func _dice_text(dice: Array[int]) -> String:
	var values: Array[String] = []
	for die in dice:
		values.append(str(die))
	return "[" + ", ".join(values) + "]"


func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = "," + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result


func _add_log(message: String) -> void:
	_activity_log.append_text(message + "\n\n")


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text_value: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)
	var normal_color := Color("d6ad51") if accent else Color("342a31")
	var hover_color := Color("f0c963") if accent else Color("493941")
	var font_color := Color("251b14") if accent else Color("f5dfad")
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", Color("21180f") if accent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color("21180f") if accent else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.54, 0.49, 0.45, 0.62))
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, Color("8a693c"), 12, 2))
	button.add_theme_stylebox_override("hover", _panel_style(hover_color, Color("f5d77f"), 12, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("f7db85") if accent else Color("5b4247"), Color("fff0a0"), 12, 3))
	button.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("fff0a0"), 12, 3))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("211e22"), Color("3c3634"), 12, 1))
	return button


func _panel_style(background: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14
	style.content_margin_top = 12
	style.content_margin_right = 14
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.01, 0.008, 0.012, 0.52)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style


func _panel_margin(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", amount)
	margin.add_theme_constant_override("margin_top", amount)
	margin.add_theme_constant_override("margin_right", amount)
	margin.add_theme_constant_override("margin_bottom", amount)
	return margin


func _rules_text() -> String:
	return """[b][color=#f2ca66]THE TURN[/color][/b]
Roll six dice. Select dice to lock, then press REROLL. Locked dice remain disabled in their original positions while every unselected die rerolls in place. Continue until all six dice score or a reroll cannot score or advance a qualifying combination. KEEP IT banks the current scoring hand and ends the turn.

REROLL is enabled when the selected dice contain at least one score, five faces toward a straight, three to five matching dice, two pairs toward the three-pair special, or one triple toward two triplets.

[b][color=#f2ca66]GETTING ON THE BOARD[/color][/b]
Your first banked turn must be worth at least 1,000 points. After that, you may bank any positive turn score. The first player to reach 10,000 wins immediately.

[b][color=#f2ca66]SCORING[/color][/b]
• Single 1: 100   • Single 5: 50
• Three 1s: 1,000
• Three of 2–6: face value × 100
• Every matching die beyond three doubles that set: four 4s = 800, five 4s = 1,600, six 4s = 3,200
• Matching sets must be rolled together. A locked pair is the exception: one matching die on the immediately following roll completes its triple.
• Straight (1–6): 1,500
• Three pairs: 1,000. Four-of-a-kind plus a pair and two triplets also count.

[b][color=#f2ca66]AND ROLLING / HOT DICE[/color][/b]
When all six dice score, pick up all six and roll again if you continue. Every new roll must score or the entire turn is lost.

[b][color=#f2ca66]NO-SCORE RESCUE — ONCE PER TURN[/color][/b]
Only when the opening six-die roll has no scoring dice, a qualifying partial combination may be locked for one rescue reroll. If the rescue does not produce a score or advance the combination, the turn busts.
"""
