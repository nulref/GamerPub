class_name SesquipGame
extends Control
## First playable local hot-seat version of Sesquip.

const LAUNCHER_SCENE := "res://launcher/main_menu.tscn"
const TURN_SECONDS := 5.0
const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const LEXICON_SCRIPT := preload("res://games/sesquip/scripts/sesquip_lexicon.gd")
const LEXICON_DATA := preload("res://games/sesquip/data/starter_words.gd")
const KEY_ROWS := ["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"]

var lexicon
var players: Array[Dictionary] = []
var current_player := 0
var current_sequence := ""
var round_number := 0
var round_active := false
var seconds_left := TURN_SECONDS
var consecutive_timeouts := 0
var last_player := -1

var _round_starter := -1
var _turn_message := ""
var _portrait_layout := false
var _letter_buttons: Dictionary = {}
var _name_edits: Array[LineEdit] = []

var _screen_margin: MarginContainer
var _page: VBoxContainer
var _body: GridContainer
var _title_label: Label
var _subtitle_label: Label
var _scoreboard_panel: PanelContainer
var _score_list: VBoxContainer
var _table_panel: PanelContainer
var _table_margin: MarginContainer
var _turn_badge: Label
var _sequence_flow: HFlowContainer
var _sequence_hint: Label
var _status_label: Label
var _timer_label: Label
var _timer_progress: ProgressBar
var _keyboard_column: VBoxContainer
var _possibility_panel: PanelContainer
var _paths_label: Label
var _legal_label: Label
var _word_state_label: Label
var _footer_label: Label
var _setup_overlay: Control
var _player_count: SpinBox
var _rules_overlay: Control
var _round_overlay: Control
var _round_title: Label
var _round_result: Label


func _ready() -> void:
	lexicon = LEXICON_SCRIPT.new(LEXICON_DATA.all())
	_build_interface()
	get_viewport().size_changed.connect(_queue_responsive_layout)
	_apply_responsive_layout()
	_show_setup()


func _process(delta: float) -> void:
	if not round_active or _rules_overlay.visible or _setup_overlay.visible or _round_overlay.visible:
		return
	seconds_left = maxf(seconds_left - delta, 0.0)
	_timer_progress.value = seconds_left
	_timer_label.text = "%0.1f" % seconds_left
	if is_zero_approx(seconds_left):
		_on_turn_timeout()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or not round_active or _rules_overlay.visible:
		return
	if event.keycode >= KEY_A and event.keycode <= KEY_Z:
		var letter := String.chr(event.keycode)
		if play_letter(letter):
			get_viewport().set_input_as_handled()


func start_game(player_names: PackedStringArray) -> void:
	players.clear()
	var accepted_count := clampi(maxi(player_names.size(), MIN_PLAYERS), MIN_PLAYERS, MAX_PLAYERS)
	for index in range(accepted_count):
		var player_name := player_names[index].strip_edges() if index < player_names.size() else ""
		if player_name.is_empty():
			player_name = "Player %d" % (index + 1)
		players.append({"name": player_name, "score": 0})

	_round_starter = -1
	round_number = 0
	_setup_overlay.visible = false
	_begin_next_round()


func play_letter(raw_letter: String) -> bool:
	if not round_active or _rules_overlay.visible:
		return false
	var letter: String = LEXICON_SCRIPT.normalize(raw_letter)
	if letter.length() != 1 or not lexicon.legal_letters(current_sequence).has(letter):
		return false

	var mover := current_player
	var mover_name := String(players[mover]["name"])
	current_sequence += letter
	last_player = mover
	consecutive_timeouts = 0

	if lexicon.is_terminal_word(current_sequence):
		players[mover]["score"] = int(players[mover]["score"]) + current_sequence.length()
		_finish_round(
			"WORD CLAIMED",
			"%s completed %s and earns %d points." % [
				mover_name,
				current_sequence,
				current_sequence.length(),
			]
		)
		return true

	current_player = (current_player + 1) % players.size()
	seconds_left = TURN_SECONDS
	var next_name := String(players[current_player]["name"])
	_turn_message = "%s played %s. %s is up." % [mover_name, letter, next_name]
	_update_game_display()
	return true


func back_to_launcher() -> void:
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("100F17")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var warm_glow := ColorRect.new()
	warm_glow.set_anchors_preset(Control.PRESET_CENTER)
	warm_glow.position = Vector2(-680, -420)
	warm_glow.size = Vector2(760, 620)
	warm_glow.color = Color(0.37, 0.19, 0.06, 0.22)
	warm_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warm_glow)

	var cool_glow := ColorRect.new()
	cool_glow.set_anchors_preset(Control.PRESET_CENTER)
	cool_glow.position = Vector2(80, -180)
	cool_glow.size = Vector2(760, 620)
	cool_glow.color = Color(0.03, 0.32, 0.27, 0.16)
	cool_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cool_glow)

	_screen_margin = MarginContainer.new()
	_screen_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_margin)

	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 16)
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
	_body.add_child(_build_possibility_panel())

	_footer_label = Label.new()
	_footer_label.text = "ONLY LIT LETTERS ARE LEGAL  •  FIVE SECONDS PER TURN  •  THE PLAYER WHO FINISHES A TERMINAL WORD SCORES ITS LENGTH"
	_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer_label.add_theme_font_size_override("font_size", 13)
	_footer_label.add_theme_color_override("font_color", Color("A99E89"))
	_page.add_child(_footer_label)

	_build_rules_overlay()
	_build_round_overlay()
	_build_setup_overlay()


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 72
	header.add_theme_constant_override("separation", 18)

	var back_button := _make_button("‹  GAMER PUB", false)
	back_button.name = "BackToLauncherButton"
	back_button.custom_minimum_size = Vector2(180, 54)
	back_button.pressed.connect(back_to_launcher)
	header.add_child(back_button)

	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", -2)
	header.add_child(heading)

	_title_label = Label.new()
	_title_label.text = "SESQUIP"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 46)
	_title_label.add_theme_color_override("font_color", Color("F5D77F"))
	_title_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.03, 0.9))
	_title_label.add_theme_constant_override("shadow_offset_x", 3)
	_title_label.add_theme_constant_override("shadow_offset_y", 4)
	heading.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = "OUTLAST THE WORD"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 13)
	_subtitle_label.add_theme_color_override("font_color", Color("74DFC2"))
	heading.add_child(_subtitle_label)

	var rules_button := _make_button("HOW TO PLAY", false)
	rules_button.custom_minimum_size = Vector2(180, 54)
	rules_button.pressed.connect(_show_rules)
	header.add_child(rules_button)
	return header


func _build_scoreboard() -> PanelContainer:
	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.custom_minimum_size.x = 260
	_scoreboard_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(Color("18141F"), Color("6E5530"), 18, 2))
	var margin := _panel_margin(18)
	_scoreboard_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var eyebrow := _section_label("SCOREBOARD")
	column.add_child(eyebrow)
	var rule := HSeparator.new()
	rule.modulate = Color("6E5530")
	column.add_child(rule)
	_score_list = VBoxContainer.new()
	_score_list.add_theme_constant_override("separation", 9)
	column.add_child(_score_list)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var note := Label.new()
	note.text = "Each terminal letter is worth one point for every letter in the word."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color("AFA899"))
	column.add_child(note)
	return _scoreboard_panel


func _build_table() -> PanelContainer:
	_table_panel = PanelContainer.new()
	_table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_panel.add_theme_stylebox_override("panel", _panel_style(Color("161923"), Color("3E8C7A"), 22, 2))
	_table_margin = _panel_margin(24)
	_table_panel.add_child(_table_margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 13)
	_table_margin.add_child(column)

	_turn_badge = Label.new()
	_turn_badge.text = "READY"
	_turn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_badge.add_theme_font_size_override("font_size", 18)
	_turn_badge.add_theme_color_override("font_color", Color("74DFC2"))
	column.add_child(_turn_badge)

	_sequence_hint = Label.new()
	_sequence_hint.text = "CHOOSE A STARTING LETTER"
	_sequence_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sequence_hint.add_theme_font_size_override("font_size", 13)
	_sequence_hint.add_theme_color_override("font_color", Color("9C9488"))
	column.add_child(_sequence_hint)

	var sequence_center := CenterContainer.new()
	sequence_center.custom_minimum_size.y = 82
	sequence_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(sequence_center)
	_sequence_flow = HFlowContainer.new()
	_sequence_flow.custom_minimum_size.x = 700
	_sequence_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_sequence_flow.add_theme_constant_override("h_separation", 7)
	_sequence_flow.add_theme_constant_override("v_separation", 7)
	sequence_center.add_child(_sequence_flow)

	_status_label = Label.new()
	_status_label.text = "Set up players to begin."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color("E8E0D0"))
	column.add_child(_status_label)

	var timer_row := HBoxContainer.new()
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.add_theme_constant_override("separation", 12)
	column.add_child(timer_row)
	var timer_caption := Label.new()
	timer_caption.text = "TURN"
	timer_caption.add_theme_font_size_override("font_size", 12)
	timer_caption.add_theme_color_override("font_color", Color("9C9488"))
	timer_row.add_child(timer_caption)
	_timer_progress = ProgressBar.new()
	_timer_progress.custom_minimum_size = Vector2(300, 18)
	_timer_progress.min_value = 0.0
	_timer_progress.max_value = TURN_SECONDS
	_timer_progress.value = TURN_SECONDS
	_timer_progress.show_percentage = false
	_timer_progress.add_theme_stylebox_override("background", _panel_style(Color("25212C"), Color("423A47"), 9, 1))
	_timer_progress.add_theme_stylebox_override("fill", _panel_style(Color("D5A83E"), Color("F5D77F"), 9, 1))
	timer_row.add_child(_timer_progress)
	_timer_label = Label.new()
	_timer_label.custom_minimum_size.x = 42
	_timer_label.text = "5.0"
	_timer_label.add_theme_font_size_override("font_size", 17)
	_timer_label.add_theme_color_override("font_color", Color("F5D77F"))
	timer_row.add_child(_timer_label)

	_keyboard_column = VBoxContainer.new()
	_keyboard_column.add_theme_constant_override("separation", 8)
	column.add_child(_keyboard_column)
	_build_keyboard()
	return _table_panel


func _build_keyboard() -> void:
	for row_letters in KEY_ROWS:
		var center := CenterContainer.new()
		_keyboard_column.add_child(center)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		center.add_child(row)
		for index in range(row_letters.length()):
			var letter: String = row_letters.substr(index, 1)
			var key := _make_letter_button(letter)
			key.pressed.connect(_on_letter_pressed.bind(letter))
			row.add_child(key)
			_letter_buttons[letter] = key


func _build_possibility_panel() -> PanelContainer:
	_possibility_panel = PanelContainer.new()
	_possibility_panel.custom_minimum_size.x = 260
	_possibility_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_possibility_panel.add_theme_stylebox_override("panel", _panel_style(Color("18141F"), Color("6E5530"), 18, 2))
	var margin := _panel_margin(18)
	_possibility_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(_section_label("POSSIBILITY SPACE"))
	var rule := HSeparator.new()
	rule.modulate = Color("6E5530")
	column.add_child(rule)

	_paths_label = _metric_label("—", "WORDS REMAIN")
	column.add_child(_paths_label)
	_legal_label = _metric_label("—", "LEGAL LETTERS")
	column.add_child(_legal_label)
	_word_state_label = Label.new()
	_word_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_word_state_label.add_theme_font_size_override("font_size", 14)
	_word_state_label.add_theme_color_override("font_color", Color("74DFC2"))
	column.add_child(_word_state_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var explainer := Label.new()
	explainer.text = "The keyboard shows every letter that keeps at least one word alive. A complete word only scores when no lit letters remain."
	explainer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explainer.add_theme_font_size_override("font_size", 14)
	explainer.add_theme_color_override("font_color", Color("AFA899"))
	column.add_child(explainer)
	return _possibility_panel


func _build_setup_overlay() -> void:
	_setup_overlay = Control.new()
	_setup_overlay.name = "SetupOverlay"
	_setup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_setup_overlay)
	_add_modal_shade(_setup_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_setup_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 600)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("17131D"), Color("D5A83E"), 22, 3))
	center.add_child(panel)
	var margin := _panel_margin(30)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = "GATHER THE WORDSMITHS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("F5D77F"))
	column.add_child(title)
	var intro := Label.new()
	intro.text = "Take turns extending one shared sequence. Only letters that begin a word in the prototype lexicon will light up."
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 15)
	intro.add_theme_color_override("font_color", Color("C6BEB0"))
	column.add_child(intro)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 12)
	column.add_child(count_row)
	var count_label := Label.new()
	count_label.text = "Players"
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", 17)
	count_row.add_child(count_label)
	_player_count = SpinBox.new()
	_player_count.custom_minimum_size = Vector2(120, 48)
	_player_count.min_value = MIN_PLAYERS
	_player_count.max_value = MAX_PLAYERS
	_player_count.step = 1
	_player_count.value = 2
	_player_count.value_changed.connect(_update_name_edit_visibility)
	count_row.add_child(_player_count)

	for index in range(MAX_PLAYERS):
		var edit := LineEdit.new()
		edit.custom_minimum_size.y = 50
		edit.placeholder_text = "Player %d name" % (index + 1)
		edit.text = "Player %d" % (index + 1)
		edit.max_length = 20
		edit.add_theme_font_size_override("font_size", 17)
		edit.add_theme_color_override("font_color", Color("F4ECDD"))
		edit.add_theme_color_override("caret_color", Color("74DFC2"))
		edit.add_theme_stylebox_override("normal", _panel_style(Color("211C27"), Color("574A59"), 10, 1))
		edit.add_theme_stylebox_override("focus", _panel_style(Color("211C27"), Color("74DFC2"), 10, 2))
		column.add_child(edit)
		_name_edits.append(edit)

	var start_button := _make_button("START ROUND", true)
	start_button.custom_minimum_size.y = 58
	start_button.pressed.connect(_start_from_setup)
	column.add_child(start_button)
	var lexicon_note := Label.new()
	lexicon_note.text = "Prototype vocabulary: %s curated words • minimum length 3" % _formatted_number(lexicon.word_count)
	lexicon_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lexicon_note.add_theme_font_size_override("font_size", 12)
	lexicon_note.add_theme_color_override("font_color", Color("857F78"))
	column.add_child(lexicon_note)
	_update_name_edit_visibility(_player_count.value)


func _build_rules_overlay() -> void:
	_rules_overlay = Control.new()
	_rules_overlay.name = "RulesOverlay"
	_rules_overlay.visible = false
	_rules_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rules_overlay)
	_add_modal_shade(_rules_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rules_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 680)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("17131D"), Color("3E8C7A"), 22, 3))
	center.add_child(panel)
	var margin := _panel_margin(28)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "HOW TO PLAY SESQUIP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("F5D77F"))
	column.add_child(title)
	var rules := RichTextLabel.new()
	rules.bbcode_enabled = true
	rules.fit_content = true
	rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules.add_theme_font_size_override("normal_font_size", 17)
	rules.add_theme_font_size_override("bold_font_size", 17)
	rules.text = _rules_text()
	column.add_child(rules)
	var close_button := _make_button("BACK TO THE WORD", true)
	close_button.custom_minimum_size.y = 56
	close_button.pressed.connect(_hide_rules)
	column.add_child(close_button)


func _build_round_overlay() -> void:
	_round_overlay = Control.new()
	_round_overlay.name = "RoundOverlay"
	_round_overlay.visible = false
	_round_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_round_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_round_overlay)
	_add_modal_shade(_round_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_round_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(590, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("17131D"), Color("D5A83E"), 22, 3))
	center.add_child(panel)
	var margin := _panel_margin(30)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_round_title = Label.new()
	_round_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_title.add_theme_font_size_override("font_size", 29)
	_round_title.add_theme_color_override("font_color", Color("F5D77F"))
	column.add_child(_round_title)
	_round_result = Label.new()
	_round_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_round_result.add_theme_font_size_override("font_size", 20)
	_round_result.add_theme_color_override("font_color", Color("E8E0D0"))
	column.add_child(_round_result)
	var next_button := _make_button("NEXT ROUND", true)
	next_button.custom_minimum_size.y = 58
	next_button.pressed.connect(_begin_next_round)
	column.add_child(next_button)
	var players_button := _make_button("CHANGE PLAYERS", false)
	players_button.custom_minimum_size.y = 50
	players_button.pressed.connect(_show_setup)
	column.add_child(players_button)


func _start_from_setup() -> void:
	var names := PackedStringArray()
	for index in range(int(_player_count.value)):
		names.append(_name_edits[index].text)
	start_game(names)


func _begin_next_round() -> void:
	if players.is_empty():
		return
	_round_overlay.visible = false
	round_number += 1
	_round_starter = (_round_starter + 1) % players.size()
	current_player = _round_starter
	current_sequence = ""
	last_player = -1
	consecutive_timeouts = 0
	seconds_left = TURN_SECONDS
	round_active = true
	_turn_message = "%s begins. Choose any lit letter." % String(players[current_player]["name"])
	_update_game_display()


func _on_letter_pressed(letter: String) -> void:
	play_letter(letter)


func _on_turn_timeout() -> void:
	if not round_active:
		return
	var timed_out_name := String(players[current_player]["name"])
	consecutive_timeouts += 1
	if consecutive_timeouts >= players.size():
		_finish_round(
			"ROUND ABANDONED",
			"Every player timed out on %s. No points are awarded." % (
				"the opening" if current_sequence.is_empty() else current_sequence
			)
		)
		return
	current_player = (current_player + 1) % players.size()
	seconds_left = TURN_SECONDS
	_turn_message = "%s timed out. Turn passes to %s." % [
		timed_out_name,
		String(players[current_player]["name"]),
	]
	_update_game_display()


func _finish_round(title_text: String, result_text: String) -> void:
	round_active = false
	_turn_message = result_text
	_round_title.text = title_text
	_round_result.text = result_text
	_update_game_display()
	_round_overlay.visible = true


func _update_game_display() -> void:
	_update_scoreboard()
	_render_sequence()
	_update_keyboard()
	if players.is_empty():
		return

	_turn_badge.text = "ROUND %d  •  %s'S TURN" % [round_number, String(players[current_player]["name"]).to_upper()]
	_status_label.text = _turn_message
	_timer_progress.value = seconds_left
	_timer_label.text = "%0.1f" % seconds_left
	var legal_letters: PackedStringArray = lexicon.legal_letters(current_sequence)
	_paths_label.text = "%s\nWORDS REMAIN" % _formatted_number(lexicon.completion_count(current_sequence))
	_legal_label.text = "%d\nLEGAL LETTER%s" % [legal_letters.size(), "" if legal_letters.size() == 1 else "S"]
	if current_sequence.is_empty():
		_word_state_label.text = "OPENING POSITION"
	elif lexicon.is_word(current_sequence):
		_word_state_label.text = "VALID WORD — STILL EXTENDABLE"
	else:
		_word_state_label.text = "VALID PREFIX"


func _update_scoreboard() -> void:
	if _score_list == null:
		return
	for child in _score_list.get_children():
		_score_list.remove_child(child)
		child.queue_free()
	if players.is_empty():
		var waiting := Label.new()
		waiting.text = "Players appear here when the first round begins."
		waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		waiting.add_theme_color_override("font_color", Color("8E877E"))
		_score_list.add_child(waiting)
		return

	for index in range(players.size()):
		var row := PanelContainer.new()
		var is_current := round_active and index == current_player
		row.add_theme_stylebox_override(
			"panel",
			_panel_style(
				Color("20352F") if is_current else Color("211C27"),
				Color("74DFC2") if is_current else Color("3F3844"),
				12,
				2 if is_current else 1
			)
		)
		var margin := _panel_margin(11)
		row.add_child(margin)
		var content := HBoxContainer.new()
		margin.add_child(content)
		var name_label := Label.new()
		name_label.text = ("› " if is_current else "  ") + String(players[index]["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color("EDE5D7"))
		content.add_child(name_label)
		var score_label := Label.new()
		score_label.text = str(players[index]["score"])
		score_label.add_theme_font_size_override("font_size", 22)
		score_label.add_theme_color_override("font_color", Color("F5D77F"))
		content.add_child(score_label)
		_score_list.add_child(row)


func _render_sequence() -> void:
	for child in _sequence_flow.get_children():
		_sequence_flow.remove_child(child)
		child.queue_free()
	if current_sequence.is_empty():
		_sequence_hint.text = "CHOOSE A STARTING LETTER"
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_font_size_override("font_size", 48)
		dash.add_theme_color_override("font_color", Color("4C4651"))
		_sequence_flow.add_child(dash)
		return

	_sequence_hint.text = "THE WORD SO FAR"
	for index in range(current_sequence.length()):
		var tile := Label.new()
		tile.custom_minimum_size = Vector2(54, 62)
		tile.text = current_sequence.substr(index, 1)
		tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_theme_font_size_override("font_size", 30)
		tile.add_theme_color_override("font_color", Color("17131D"))
		tile.add_theme_stylebox_override("normal", _panel_style(Color("F5D77F"), Color("FFF0B5"), 9, 2))
		_sequence_flow.add_child(tile)


func _update_keyboard() -> void:
	var legal: PackedStringArray = lexicon.legal_letters(current_sequence) if lexicon != null else PackedStringArray()
	for letter in _letter_buttons.keys():
		var button := _letter_buttons[letter] as Button
		button.disabled = not round_active or not legal.has(String(letter))


func _show_setup() -> void:
	round_active = false
	_round_overlay.visible = false
	_rules_overlay.visible = false
	_setup_overlay.visible = true
	_update_keyboard()
	_update_scoreboard()


func _show_rules() -> void:
	_rules_overlay.visible = true


func _hide_rules() -> void:
	_rules_overlay.visible = false


func _update_name_edit_visibility(value: float) -> void:
	var count := int(value)
	for index in range(_name_edits.size()):
		_name_edits[index].visible = index < count


func _queue_responsive_layout() -> void:
	_apply_responsive_layout.call_deferred()


func _apply_responsive_layout() -> void:
	_portrait_layout = get_viewport_rect().size.y > get_viewport_rect().size.x
	if _portrait_layout:
		_set_margins(_screen_margin, 34, 28, 34, 430)
		_body.columns = 1
		_scoreboard_panel.custom_minimum_size = Vector2(0, 190)
		_table_panel.custom_minimum_size = Vector2(0, 720)
		_possibility_panel.custom_minimum_size = Vector2(0, 190)
		_title_label.add_theme_font_size_override("font_size", 52)
		_footer_label.visible = false
		_set_margins(_table_margin, 18, 20, 18, 20)
		for button in _letter_buttons.values():
			(button as Button).custom_minimum_size = Vector2(72, 72)
			(button as Button).add_theme_font_size_override("font_size", 25)
	else:
		_set_margins(_screen_margin, 42, 24, 42, 24)
		_body.columns = 3
		_scoreboard_panel.custom_minimum_size = Vector2(260, 0)
		_table_panel.custom_minimum_size = Vector2(0, 0)
		_possibility_panel.custom_minimum_size = Vector2(260, 0)
		_title_label.add_theme_font_size_override("font_size", 46)
		_footer_label.visible = true
		_set_margins(_table_margin, 24, 24, 24, 24)
		for button in _letter_buttons.values():
			(button as Button).custom_minimum_size = Vector2(64, 54)
			(button as Button).add_theme_font_size_override("font_size", 21)


func _make_letter_button(letter: String) -> Button:
	var button := Button.new()
	button.text = letter
	button.tooltip_text = "%s is a legal continuation" % letter
	button.accessibility_name = "Play letter %s" % letter
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("17201E"))
	button.add_theme_color_override("font_hover_color", Color("0D1513"))
	button.add_theme_color_override("font_pressed_color", Color("0D1513"))
	button.add_theme_color_override("font_disabled_color", Color("514B55"))
	button.add_theme_stylebox_override("normal", _panel_style(Color("74DFC2"), Color("B7FFE9"), 10, 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("A4F3DD"), Color("FFFFFF"), 10, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("F5D77F"), Color("FFF0B5"), 10, 3))
	button.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("FFF0B5"), 10, 3))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("211E27"), Color("342F38"), 10, 1))
	return button


func _make_button(text_value: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	var normal_color := Color("D5A83E") if accent else Color("29232E")
	var hover_color := Color("F5D77F") if accent else Color("3C3341")
	button.add_theme_color_override("font_color", Color("17131D") if accent else Color("E9DFD0"))
	button.add_theme_color_override("font_hover_color", Color("17131D") if accent else Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, Color("8A693C"), 11, 2))
	button.add_theme_stylebox_override("hover", _panel_style(hover_color, Color("F5D77F"), 11, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("E7C35E") if accent else Color("4A3E4E"), Color("FFF0A0"), 11, 3))
	button.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("FFF0A0"), 11, 3))
	return button


func _section_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("F5D77F"))
	return label


func _metric_label(value: String, caption: String) -> Label:
	var label := Label.new()
	label.text = "%s\n%s" % [value, caption]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("EDE5D7"))
	return label


func _add_modal_shade(parent: Control) -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.018, 0.03, 0.91)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(shade)


func _panel_style(background: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_top = 10
	style.content_margin_right = 12
	style.content_margin_bottom = 10
	style.shadow_color = Color(0.01, 0.008, 0.012, 0.5)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 4)
	return style


func _panel_margin(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	_set_margins(margin, amount, amount, amount, amount)
	return margin


func _set_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)


func _formatted_number(value: int) -> String:
	var digits := str(value)
	var output := ""
	while digits.length() > 3:
		output = "," + digits.right(3) + output
		digits = digits.left(-3)
	return digits + output


func _rules_text() -> String:
	return """[b][color=#F5D77F]BUILD ONE SHARED WORD[/color][/b]
Players add one letter at a time. Every move must leave the full sequence as the beginning of at least one word. The lit keyboard shows every legal choice.

[b][color=#F5D77F]KEEP GOING THROUGH COMPLETE WORDS[/color][/b]
Making a valid word does not end the round if that word can still grow. CAR can continue to CARD, CARE, CART, and beyond. The round ends only at a complete word with no legal extension in the lexicon.

[b][color=#F5D77F]CLAIM THE TERMINAL WORD[/color][/b]
The player who adds the final legal letter earns one point per letter in the finished word. Scores carry into the next round, and the opening player rotates.

[b][color=#F5D77F]BEAT THE CLOCK[/color][/b]
You have five seconds to choose a lit letter. A timeout passes the turn without changing the sequence. If every player times out consecutively on the same position, the round is abandoned with no score.

[b][color=#74DFC2]PROTOTYPE NOTE[/color][/b]
This build uses a curated local vocabulary of common words with a three-letter minimum. It is intended to test whether the core strategy is fun; it is not an official Scrabble dictionary.
"""
