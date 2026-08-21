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
var go_for_used := false
var pending_go_for_plan: Dictionary = {}
var awaiting_next_player := false
var awaiting_go_for_choice := false
var game_over := false

var _score_list: VBoxContainer
var _turn_badge: Label
var _status_label: Label
var _turn_score_label: Label
var _roll_detail_label: Label
var _dice_row: HBoxContainer
var _selection_label: Label
var _roll_button: Button
var _set_aside_button: Button
var _keep_button: Button
var _go_for_panel: PanelContainer
var _go_for_label: Label
var _go_for_buttons: HBoxContainer
var _activity_log: RichTextLabel
var _setup_overlay: Control
var _player_count: SpinBox
var _name_edits: Array[LineEdit] = []
var _rules_overlay: Control
var _winner_overlay: Control
var _winner_label: Label


func _ready() -> void:
	randomize()
	_build_interface()
	_show_setup()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _setup_overlay.visible or _rules_overlay.visible:
		return
	if event.keycode == KEY_SPACE and not _roll_button.disabled:
		_on_roll_pressed()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and not _set_aside_button.disabled:
		_on_set_aside_pressed()
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

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	page.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	page.add_child(body)
	body.add_child(_build_scoreboard())
	body.add_child(_build_table())
	body.add_child(_build_activity_panel())

	var footer := Label.new()
	footer.text = "SPACE rolls  •  ENTER sets selected dice aside  •  Reach 1,000 in one turn to get on the board"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color("b8aa91"))
	footer.add_theme_font_size_override("font_size", 14)
	page.add_child(footer)

	_setup_overlay = _build_setup_overlay()
	add_child(_setup_overlay)
	_rules_overlay = _build_rules_overlay()
	add_child(_rules_overlay)
	_winner_overlay = _build_winner_overlay()
	add_child(_winner_overlay)


func _build_header() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 76
	panel.add_theme_stylebox_override("panel", _panel_style(Color("211728"), Color("694b38"), 18))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var back := _make_button("‹  GAMER PUB", false)
	back.name = "BackToLauncherButton"
	back.custom_minimum_size.x = 190
	back.pressed.connect(back_to_launcher)
	row.add_child(back)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(title_box)
	var title := _make_label("10,000", 34, Color("f6d37a"))
	title_box.add_child(title)
	var subtitle := _make_label("ROLL BOLDLY. BANK WISELY.", 12, Color("ad9a7a"))
	title_box.add_child(subtitle)

	_turn_badge = _make_label("SET UP GAME", 18, Color("fff3ca"))
	_turn_badge.custom_minimum_size.x = 270
	_turn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_turn_badge)

	var rules_button := _make_button("RULES", false)
	rules_button.custom_minimum_size.x = 130
	rules_button.pressed.connect(_open_rules)
	row.add_child(rules_button)
	return panel


func _build_scoreboard() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.add_theme_stylebox_override("panel", _panel_style(Color("1d1822"), Color("4f4036"), 18))
	var margin := _panel_margin(22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var heading := _make_label("SCOREBOARD", 20, Color("eac46c"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var rule := HSeparator.new()
	rule.modulate = Color("765b3f")
	column.add_child(rule)
	_score_list = VBoxContainer.new()
	_score_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_score_list.add_theme_constant_override("separation", 9)
	column.add_child(_score_list)
	var goal := _make_label("FIRST TO 10,000 WINS", 13, Color("a9977b"))
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(goal)
	return panel


func _build_table() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("13251e"), Color("8c6c3f"), 24, 3))
	var margin := _panel_margin(30)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 17)
	margin.add_child(column)

	_status_label = _make_label("Choose players to begin.", 22, Color("fff2c3"))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 60
	column.add_child(_status_label)

	_turn_score_label = _make_label("TURN SCORE  0", 27, Color("f2c95f"))
	_turn_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_turn_score_label)

	_roll_detail_label = _make_label("Six dice are ready.", 15, Color("bcd2c6"))
	_roll_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_roll_detail_label)

	var dice_center := CenterContainer.new()
	dice_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dice_center.custom_minimum_size.y = 184
	column.add_child(dice_center)
	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 12)
	dice_center.add_child(_dice_row)

	_selection_label = _make_label("Roll the dice to begin your turn.", 16, Color("d8ccb2"))
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.custom_minimum_size.y = 44
	column.add_child(_selection_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_roll_button = _make_button("ROLL 6 DICE", true)
	_roll_button.custom_minimum_size = Vector2(190, 58)
	_roll_button.pressed.connect(_on_roll_pressed)
	actions.add_child(_roll_button)
	_set_aside_button = _make_button("SET ASIDE", false)
	_set_aside_button.custom_minimum_size = Vector2(170, 58)
	_set_aside_button.pressed.connect(_on_set_aside_pressed)
	actions.add_child(_set_aside_button)
	_keep_button = _make_button("KEEP IT", false)
	_keep_button.custom_minimum_size = Vector2(170, 58)
	_keep_button.pressed.connect(_on_keep_pressed)
	actions.add_child(_keep_button)

	_go_for_panel = PanelContainer.new()
	_go_for_panel.visible = false
	_go_for_panel.add_theme_stylebox_override("panel", _panel_style(Color("342018"), Color("d89a50"), 14, 2))
	var go_margin := _panel_margin(14)
	_go_for_panel.add_child(go_margin)
	var go_column := VBoxContainer.new()
	go_column.add_theme_constant_override("separation", 9)
	go_margin.add_child(go_column)
	_go_for_label = _make_label("", 15, Color("ffdca0"))
	_go_for_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	go_column.add_child(_go_for_label)
	_go_for_buttons = HBoxContainer.new()
	_go_for_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_go_for_buttons.add_theme_constant_override("separation", 10)
	go_column.add_child(_go_for_buttons)
	column.add_child(_go_for_panel)
	return panel


func _build_activity_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	panel.add_theme_stylebox_override("panel", _panel_style(Color("1d1822"), Color("4f4036"), 18))
	var margin := _panel_margin(20)
	panel.add_child(margin)
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
	return panel


func _build_setup_overlay() -> Control:
	var overlay := _modal_base("SetupOverlay")
	var center: CenterContainer = overlay.get_node("Center")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 650)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("211923"), Color("d0a653"), 22, 3))
	center.add_child(panel)
	var margin := _panel_margin(30)
	panel.add_child(margin)
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
	var start := _make_button("START GAME", true)
	start.custom_minimum_size = Vector2(220, 52)
	start.pressed.connect(_start_game)
	buttons.add_child(start)
	return overlay


func _build_rules_overlay() -> Control:
	var overlay := _modal_base("RulesOverlay")
	overlay.visible = false
	var center: CenterContainer = overlay.get_node("Center")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 720)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("201923"), Color("c69c4b"), 22, 3))
	center.add_child(panel)
	var margin := _panel_margin(28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := _make_label("HOW TO PLAY 10,000", 28, Color("f1cb67"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.add_theme_color_override("default_color", Color("ddd1bb"))
	text.text = _rules_text()
	column.add_child(text)
	var close := _make_button("BACK TO THE TABLE", true)
	close.custom_minimum_size.y = 52
	close.pressed.connect(_close_rules)
	column.add_child(close)
	return overlay


func _build_winner_overlay() -> Control:
	var overlay := _modal_base("WinnerOverlay")
	overlay.visible = false
	var center: CenterContainer = overlay.get_node("Center")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("241a21"), Color("f2c85d"), 24, 4))
	center.add_child(panel)
	var margin := _panel_margin(34)
	panel.add_child(margin)
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
	var pub := _make_button("BACK TO GAMER PUB", false)
	pub.custom_minimum_size.y = 50
	pub.pressed.connect(back_to_launcher)
	column.add_child(pub)
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
	go_for_used = false
	pending_go_for_plan.clear()
	awaiting_next_player = false
	awaiting_go_for_choice = false
	_clear_go_for_options()
	_clear_dice()
	var player: Dictionary = players[current_player]
	_status_label.text = "%s, roll all six dice." % player.name
	_selection_label.text = "Select at least one scoring die after every roll."
	_roll_detail_label.text = "Six dice are ready."
	_add_log("[color=#f5e5bb]%s's turn[/color]" % player.name)
	_update_all_ui()


func _on_roll_pressed() -> void:
	if not pending_go_for_plan.is_empty():
		_roll_go_for_dice()
		return
	if not current_roll.is_empty() or awaiting_next_player:
		return

	current_roll = _random_dice(dice_to_roll)
	var best := RULES.best_scoring_selection(current_roll)
	_show_dice(current_roll, true, best.indices)
	_roll_detail_label.text = "Rolled: %s" % _dice_text(current_roll)
	_roll_button.disabled = true
	var can_rescue := _can_offer_rescue_reroll()

	if best.score <= 0:
		if not can_rescue:
			_finish_bust("No scoring dice — bust!")
		else:
			awaiting_go_for_choice = true
			_status_label.text = "No score yet. Lock any dice you want and reroll the rest, or end the turn."
			_selection_label.text = "Select 1–5 dice to lock for the turn's one reroll."
			_show_rescue_reroll_option()
			_update_controls()
		return

	_status_label.text = "Choose scoring dice to set aside, keep, or reroll the unselected dice."
	_selection_label.text = "Best selection: %d points — %s" % [best.score, best.label]
	if current_roll.size() > 1:
		_show_scoring_reroll_option()
	_update_controls()


func _on_die_toggled(_pressed: bool, _index: int) -> void:
	_update_selection_preview()


func _update_selection_preview() -> void:
	var selection := _selected_values()
	var scored := RULES.score_selection(selection)
	if selection.is_empty():
		_selection_label.text = "Select 1–5 dice to lock for the rescue reroll." if awaiting_go_for_choice else "Select scoring dice to set aside, keep, or reroll."
	elif scored.valid:
		_selection_label.text = "%d points selected — set aside, keep it, or reroll the unselected dice." % scored.score
	elif awaiting_go_for_choice and selection.size() < current_roll.size():
		_selection_label.text = "%d dice locked. Reroll the remaining %d once." % [selection.size(), current_roll.size() - selection.size()]
	else:
		_selection_label.text = "That selection contains a die that does not score."
	_update_selected_reroll_button()
	_update_controls()


func _on_set_aside_pressed() -> void:
	var selected_indices := _selected_indices()
	var selected_values := _selected_values()
	var scored := RULES.score_selection(selected_values)
	if not scored.valid:
		return

	turn_score += scored.score
	dice_to_roll = current_roll.size() - selected_indices.size()
	var description := "%s set aside %s for %d" % [players[current_player].name, _dice_text(selected_values), scored.score]
	_add_log(description)
	if dice_to_roll == 0:
		dice_to_roll = 6
		_status_label.text = "AND ROLLING! All six dice scored. Roll all six again or keep it."
		_roll_detail_label.text = "%s • hot dice" % scored.label
	else:
		_status_label.text = "%d point%s secured this roll. Roll the remaining dice or keep it." % [scored.score, "" if scored.score == 1 else "s"]
		_roll_detail_label.text = "%d die%s ready to roll." % [dice_to_roll, "" if dice_to_roll == 1 else "s"]
	current_roll.clear()
	awaiting_go_for_choice = false
	_clear_go_for_options()
	_clear_dice()
	_selection_label.text = "Turn total: %d. The next roll must score." % turn_score
	_update_all_ui()


func _on_keep_pressed() -> void:
	if awaiting_next_player:
		current_player = (current_player + 1) % players.size()
		_begin_turn()
		return
	if awaiting_go_for_choice:
		_finish_bust("Passed on the go-for attempt.")
		return
	if not current_roll.is_empty():
		var selected_values := _selected_values()
		var scored := RULES.score_selection(selected_values)
		if scored.valid and _can_bank_score(scored.score):
			turn_score += scored.score
			_add_log("%s kept %s for %d." % [players[current_player].name, _dice_text(selected_values), scored.score])
			_clear_go_for_options()
			_finish_scoring_turn("Kept it")
		return
	if _can_bank() and current_roll.is_empty():
		_finish_scoring_turn("Kept it")


func _score_and_reroll_selected() -> void:
	var selected_count := _selected_indices().size()
	var scored := RULES.score_selection(_selected_values())
	if not scored.valid or selected_count <= 0 or selected_count >= current_roll.size():
		return
	_on_set_aside_pressed()
	_on_roll_pressed()


func _choose_selected_reroll() -> void:
	var locked_dice := _selected_values()
	if locked_dice.is_empty() or locked_dice.size() >= current_roll.size():
		return
	go_for_used = true
	pending_go_for_plan = {
		"locked_dice": locked_dice,
		"reroll_count": current_roll.size() - locked_dice.size(),
	}
	awaiting_go_for_choice = false
	current_roll.clear()
	_clear_go_for_options()
	_show_locked_go_for_dice(locked_dice)
	var reroll_count := int(pending_go_for_plan.reroll_count)
	_status_label.text = "Locked %d dice. Roll the remaining %s." % [
		locked_dice.size(),
		"die" if reroll_count == 1 else "%d dice" % reroll_count,
	]
	_roll_detail_label.text = "Locked %s" % _dice_text(locked_dice)
	_selection_label.text = "The resulting six-die hand will be scored. This reroll is spent for the turn."
	_update_controls()


func _roll_go_for_dice() -> void:
	var plan := pending_go_for_plan.duplicate(true)
	pending_go_for_plan.clear()
	var reroll_count := int(plan.reroll_count)
	var locked_dice := _dictionary_int_array(plan, "locked_dice")
	var rolled := _random_dice(reroll_count)
	_show_dice(rolled, false)
	_roll_detail_label.text = "Locked %s • rolled %s" % [_dice_text(locked_dice), _dice_text(rolled)]
	var result := RULES.resolve_selected_reroll(locked_dice, rolled)
	if not result.success:
		_finish_bust("The rerolled hand did not score — bust!")
		return

	turn_score += result.score
	_add_log("%s rerolled %d dice and scored %d." % [players[current_player].name, reroll_count, result.score])
	if result.and_rolling:
		dice_to_roll = 6
		current_roll.clear()
		_status_label.text = "%s — AND ROLLING!" % result.label
		_selection_label.text = "All six dice scored. Roll all six again or keep it."
		_update_all_ui()
	else:
		_finish_scoring_turn("Reroll scored %d" % result.score)


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
	awaiting_next_player = true
	awaiting_go_for_choice = false
	_clear_go_for_options()
	_selection_label.text = "Pass the dice to the next player."
	_update_all_ui()


func _finish_bust(message: String) -> void:
	var lost := turn_score
	turn_score = 0
	pending_go_for_plan.clear()
	awaiting_next_player = true
	awaiting_go_for_choice = false
	_clear_go_for_options()
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


func _show_dice(values: Array[int], selectable: bool, preselected: PackedInt32Array = PackedInt32Array()) -> void:
	_clear_dice()
	for index in range(values.size()):
		var die := Button.new()
		die.toggle_mode = selectable
		die.disabled = not selectable
		die.custom_minimum_size = Vector2(112, 112)
		die.icon = DIE_TEXTURES[values[index] - 1]
		die.expand_icon = true
		die.tooltip_text = "Die showing %d%s" % [values[index], " — click to select" if selectable else ""]
		die.add_theme_stylebox_override("normal", _panel_style(Color("f0e5d0"), Color("7b5b42"), 15, 2))
		die.add_theme_stylebox_override("hover", _panel_style(Color("fff5df"), Color("f1cc68"), 15, 3))
		die.add_theme_stylebox_override("pressed", _panel_style(Color("f8dda0"), Color("fff0a0"), 15, 5))
		die.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("fff0a0"), 15, 3))
		die.set_pressed_no_signal(preselected.has(index))
		die.toggled.connect(_on_die_toggled.bind(index))
		_dice_row.add_child(die)


func _show_locked_go_for_dice(locked_dice: Array[int]) -> void:
	_show_dice(locked_dice, false)
	for child in _dice_row.get_children():
		child.modulate = Color(1.0, 0.86, 0.55, 1.0)


func _clear_dice() -> void:
	for child in _dice_row.get_children():
		_dice_row.remove_child(child)
		child.queue_free()


func _show_scoring_reroll_option() -> void:
	_clear_go_for_options()
	_go_for_panel.show()
	_go_for_label.text = "Score the selected dice and reroll every unselected die:"
	var button := _make_button("SELECT SCORING DICE", false)
	button.custom_minimum_size = Vector2(210, 42)
	button.pressed.connect(_score_and_reroll_selected)
	_go_for_buttons.add_child(button)
	_update_selected_reroll_button()


func _show_rescue_reroll_option() -> void:
	_clear_go_for_options()
	_go_for_panel.show()
	_go_for_label.text = "Opening roll has no score: lock any dice and reroll the rest once:"
	var button := _make_button("SELECT DICE TO LOCK", false)
	button.custom_minimum_size = Vector2(210, 42)
	button.pressed.connect(_choose_selected_reroll)
	_go_for_buttons.add_child(button)
	_update_selected_reroll_button()


func _update_selected_reroll_button() -> void:
	if not _go_for_panel.visible or _go_for_buttons.get_child_count() == 0:
		return
	var button := _go_for_buttons.get_child(0) as Button
	var locked_count := _selected_indices().size()
	var reroll_count := current_roll.size() - locked_count
	var selection_scores: bool = RULES.score_selection(_selected_values()).valid
	button.disabled = locked_count == 0 or reroll_count <= 0 or (not awaiting_go_for_choice and not selection_scores)
	if button.disabled:
		button.text = "SELECT 1–5 DICE TO LOCK" if awaiting_go_for_choice else "SELECT SCORING DICE"
	else:
		button.text = "REROLL %d %s" % [reroll_count, "DIE" if reroll_count == 1 else "DICE"]


func _clear_go_for_options() -> void:
	if not _go_for_buttons:
		return
	for child in _go_for_buttons.get_children():
		_go_for_buttons.remove_child(child)
		child.queue_free()
	_go_for_panel.hide()


func _selected_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for index in range(_dice_row.get_child_count()):
		var die := _dice_row.get_child(index) as Button
		if die and die.button_pressed:
			indices.append(index)
	return indices


func _selected_values() -> Array[int]:
	var values: Array[int] = []
	for index in _selected_indices():
		if index < current_roll.size():
			values.append(current_roll[index])
	return values


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
		var marker := _make_label("●" if active else "○", 14, Color("f0c45b") if active else Color("756a61"))
		box.add_child(marker)
		var name_label := _make_label(player.name, 16, Color("fff0cd") if active else Color("d3c8b5"))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(name_label)
		var score_text := _number(player.score)
		if not player.on_board:
			score_text = "—"
		var score_label := _make_label(score_text, 18, Color("f1ca67") if active else Color("b9aa8d"))
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
		_turn_score_label.text = "TURN SCORE  %s" % _number(turn_score)


func _update_controls() -> void:
	if players.is_empty() or game_over:
		_roll_button.disabled = true
		_set_aside_button.disabled = true
		_keep_button.disabled = true
		return

	if awaiting_next_player:
		_roll_button.disabled = true
		_set_aside_button.disabled = true
		_keep_button.text = "NEXT PLAYER"
		_keep_button.disabled = false
		return

	if awaiting_go_for_choice:
		_roll_button.disabled = true
		_set_aside_button.disabled = true
		_keep_button.text = "END TURN (0)"
		_keep_button.disabled = false
		return

	if not pending_go_for_plan.is_empty():
		var go_for_dice := int(pending_go_for_plan.reroll_count)
		_roll_button.text = "ROLL %d %s" % [go_for_dice, "DIE" if go_for_dice == 1 else "DICE"]
	else:
		_roll_button.text = "ROLL %d %s" % [dice_to_roll, "DIE" if dice_to_roll == 1 else "DICE"]
	_roll_button.disabled = not current_roll.is_empty()
	var selection := _selected_values()
	var selected_score := RULES.score_selection(selection)
	_set_aside_button.disabled = current_roll.is_empty() or not selected_score.valid
	_keep_button.text = "KEEP IT"
	if current_roll.is_empty():
		_keep_button.disabled = not _can_bank()
	else:
		_keep_button.disabled = not selected_score.valid or not _can_bank_score(selected_score.score)
	if not _can_bank():
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


func _can_offer_rescue_reroll() -> bool:
	return (
		current_roll.size() == 6
		and dice_to_roll == 6
		and turn_score == 0
		and not go_for_used
		and not awaiting_next_player
	)


func _on_player_count_changed(value: float) -> void:
	for index in range(_name_edits.size()):
		_name_edits[index].visible = index < int(value)


func _open_rules() -> void:
	_rules_overlay.show()


func _close_rules() -> void:
	_rules_overlay.hide()


func back_to_launcher() -> void:
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


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


func _dictionary_int_array(source: Dictionary, key: String) -> Array[int]:
	var values: Array[int] = []
	for value in source.get(key, []):
		values.append(int(value))
	return values


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
Roll six dice. After every scoring roll, select at least one scoring die or combination and set it aside. Reroll every unselected die, or bank the selected score with KEEP IT. Keep scoring and rerolling the remaining dice for as long as each roll scores. A roll with no score is a bust and loses every point from that turn.

[b][color=#f2ca66]GETTING ON THE BOARD[/color][/b]
Your first banked turn must be worth at least 1,000 points. After that, you may bank any positive turn score. The first player to reach 10,000 wins immediately.

[b][color=#f2ca66]SCORING[/color][/b]
• Single 1: 100   • Single 5: 50
• Three 1s: 1,000
• Three of 2–6: face value × 100
• Every matching die beyond three doubles that set: four 4s = 800, five 4s = 1,600, six 4s = 3,200
• Straight (1–6): 1,500
• Three pairs: 1,000. Four-of-a-kind plus a pair and two triplets also count.

[b][color=#f2ca66]AND ROLLING / HOT DICE[/color][/b]
When all six dice score, pick up all six and roll again if you continue. Every new roll must score or the entire turn is lost.

[b][color=#f2ca66]GO FOR IT — ONCE PER TURN[/color][/b]
Only when the opening six-die roll has no scoring dice, select any 1–5 dice to lock and reroll every unselected die once. The locked and rerolled dice are combined into a six-die hand and scored. This lets you rescue the turn by chasing a straight, matching set, or another scoring result.

The reroll is spent for the rest of the turn. A hand with no score busts. A scoring hand ends the turn automatically unless all six dice score.

[color=#a99b84]House-rule note: if every die scores during a go-for attempt, it is treated as “and rolling,” matching the general all-six-dice rule.[/color]"""
