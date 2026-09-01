class_name CribbageGame
extends Control

const MENU_SCENE := "res://games/cribbage/scenes/main_menu.tscn"
const RULES := preload("res://games/cribbage/scripts/cribbage_rules.gd")
const MATCH := preload("res://games/cribbage/scripts/cribbage_match.gd")
const BOT_NAMES := ["Muggins", "Peggy", "Noddy", "Cribbs", "Jack"]

var _session: Node
var _bridge: Node
var _match: CribbageMatch
var _online := false
var _room: Dictionary = {}
var _game_state: Dictionary = {}
var _selected_indices: Array[int] = []
var _bot_busy := false
var _configuration_sent := false

var _main_content: Control
var _rotate_overlay: Control
var _mode_label: Label
var _status_label: Label
var _count_label: Label
var _starter_texture: TextureRect
var _starter_label: Label
var _opponents: HBoxContainer
var _score_list: VBoxContainer
var _history: RichTextLabel
var _hand_row: HBoxContainer
var _hand_hint: Label
var _action_button: Button
var _ready_overlay: Control
var _ready_panel: PanelContainer
var _ready_status: Label
var _ready_mode: Label
var _ready_name: LineEdit
var _ready_button: Button
var _start_button: Button
var _seat_grid: GridContainer
var _rules_overlay: Control
var _winner_overlay: Control
var _winner_label: Label
var _score_panel: PanelContainer
var _table_panel: PanelContainer
var _log_panel: PanelContainer
var _header: HBoxContainer
var _table_margin: MarginContainer
var _table_column: VBoxContainer
var _hand_title: Label
var _compact_layout := false


func _ready() -> void:
	_session = get_node("/root/CribbageSession")
	_bridge = get_node("/root/CribbageWebBridge")
	_online = bool(_session.get("multiplayer_requested"))
	_bridge.call("request_landscape", true)
	_build_interface()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	if _online:
		_bridge.connect("context_changed", _on_context_changed)
		_bridge.connect("room_status_changed", _on_room_status)
		_bridge.connect("room_state_changed", _on_room_state)
		_bridge.connect("game_state_changed", _on_game_state)
		_bridge.connect("room_error", _on_room_error)
		_ready_name.text = String(_session.get("player_name"))
		_ready_overlay.show()
		_bridge.call("begin_multiplayer", _ready_name.text)
		_on_room_state(_bridge.get("room_state"))
		_on_game_state(_bridge.get("game_state"))
	else:
		_start_local_game()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("0c1712")
	add_child(background)
	var felt := ColorRect.new()
	felt.set_anchors_preset(Control.PRESET_CENTER)
	felt.position = Vector2(-600, -400)
	felt.size = Vector2(1200, 800)
	felt.color = Color(0.04, 0.23, 0.13, 0.72)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(felt)

	_main_content = MarginContainer.new()
	_main_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_margins(_main_content, 18)
	add_child(_main_content)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_main_content.add_child(page)
	_header = HBoxContainer.new()
	_header.custom_minimum_size.y = 58
	_header.add_theme_constant_override("separation", 12)
	page.add_child(_header)
	var back := _button("‹ CRIBBAGE MENU", false)
	back.custom_minimum_size = Vector2(190, 50)
	back.pressed.connect(back_to_menu)
	_header.add_child(back)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(titles)
	var title := _label("CRIBBAGE", 34, Color("f4dda3"))
	titles.add_child(title)
	_mode_label = _label("", 15, Color("b8c9bd"))
	titles.add_child(_mode_label)
	var rules := _button("RULES", false)
	rules.custom_minimum_size = Vector2(110, 50)
	rules.pressed.connect(func() -> void: _rules_overlay.show())
	_header.add_child(rules)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	page.add_child(body)
	_score_panel = _panel(Color("16251e"), Color("6d8a70"))
	_score_panel.custom_minimum_size.x = 245
	body.add_child(_score_panel)
	var score_margin := _margin(14)
	_score_panel.add_child(score_margin)
	var score_column := VBoxContainer.new()
	score_column.add_theme_constant_override("separation", 8)
	score_margin.add_child(score_column)
	score_column.add_child(_label("THE BOARD  •  121", 18, Color("e8c96f")))
	_score_list = VBoxContainer.new()
	_score_list.add_theme_constant_override("separation", 7)
	score_column.add_child(_score_list)

	_table_panel = _panel(Color("103a27"), Color("ae8d43"))
	_table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_table_panel)
	_table_margin = _margin(14)
	_table_panel.add_child(_table_margin)
	_table_column = VBoxContainer.new()
	_table_column.add_theme_constant_override("separation", 8)
	_table_margin.add_child(_table_column)
	_opponents = HBoxContainer.new()
	_opponents.alignment = BoxContainer.ALIGNMENT_CENTER
	_opponents.add_theme_constant_override("separation", 8)
	_table_column.add_child(_opponents)
	var starter_row := HBoxContainer.new()
	starter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	starter_row.add_theme_constant_override("separation", 10)
	_table_column.add_child(starter_row)
	_starter_label = _label("STARTER", 14, Color("c3d0c6"))
	starter_row.add_child(_starter_label)
	_starter_texture = TextureRect.new()
	_starter_texture.custom_minimum_size = Vector2(48, 68)
	_starter_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_starter_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	starter_row.add_child(_starter_texture)
	_count_label = _label("COUNT  0", 30, Color("f2d06e"))
	starter_row.add_child(_count_label)
	_status_label = _label("", 23, Color("f7e8bf"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 56
	_table_column.add_child(_status_label)
	var divider := HSeparator.new()
	_table_column.add_child(divider)
	_hand_title = _label("YOUR HAND", 15, Color("d7bb6d"))
	_hand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_column.add_child(_hand_title)
	var hand_center := CenterContainer.new()
	hand_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_column.add_child(hand_center)
	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", 8)
	hand_center.add_child(_hand_row)
	_hand_hint = _label("", 15, Color("c5d1c8"))
	_hand_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hand_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_table_column.add_child(_hand_hint)
	_action_button = _button("", true)
	_action_button.custom_minimum_size.y = 52
	_action_button.pressed.connect(_on_action_pressed)
	_table_column.add_child(_action_button)

	_log_panel = _panel(Color("16211d"), Color("5f7764"))
	_log_panel.custom_minimum_size.x = 285
	body.add_child(_log_panel)
	var log_margin := _margin(14)
	_log_panel.add_child(log_margin)
	var log_column := VBoxContainer.new()
	log_column.add_theme_constant_override("separation", 8)
	log_margin.add_child(log_column)
	log_column.add_child(_label("TABLE TALK", 18, Color("e6c66d")))
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.add_theme_font_size_override("normal_font_size", 15)
	log_column.add_child(_history)

	_ready_overlay = _build_ready_overlay()
	add_child(_ready_overlay)
	_rules_overlay = _build_rules_overlay()
	add_child(_rules_overlay)
	_winner_overlay = _build_winner_overlay()
	add_child(_winner_overlay)
	_rotate_overlay = _build_rotate_overlay()
	add_child(_rotate_overlay)


func _build_ready_overlay() -> Control:
	var overlay := _modal_base()
	overlay.hide()
	_ready_panel = _panel(Color("17251f"), Color("c19b49"), 3)
	_ready_panel.custom_minimum_size = Vector2(840, 660)
	overlay.get_node("Center").add_child(_ready_panel)
	var margin := _margin(24)
	_ready_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 11)
	margin.add_child(column)
	var title := _label("MULTIPLAYER READY-UP", 30, Color("f2d37a"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_ready_mode = _label("Waiting for the host to choose the table…", 17, Color("c7d2ca"))
	_ready_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_ready_mode)
	_ready_status = _label("Connecting…", 16, Color("e8dfc5"))
	_ready_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_ready_status)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	column.add_child(name_row)
	_ready_name = LineEdit.new()
	_ready_name.placeholder_text = "Player name"
	_ready_name.max_length = 32
	_ready_name.custom_minimum_size = Vector2(330, 48)
	_ready_name.text_submitted.connect(func(_value: String) -> void: _submit_name())
	name_row.add_child(_ready_name)
	var apply := _button("UPDATE NAME", false)
	apply.custom_minimum_size = Vector2(170, 48)
	apply.pressed.connect(_submit_name)
	name_row.add_child(apply)
	_seat_grid = GridContainer.new()
	_seat_grid.columns = 2
	_seat_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_seat_grid.add_theme_constant_override("h_separation", 10)
	_seat_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_seat_grid)
	for index in range(6):
		var seat := _label("%d. Waiting for player…" % (index + 1), 16, Color("cbd6ce"))
		seat.name = "Seat%d" % (index + 1)
		seat.custom_minimum_size = Vector2(360, 36)
		seat.add_theme_stylebox_override("normal", _panel_style(Color("20352b"), Color("4f6958"), 9, 1))
		_seat_grid.add_child(seat)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var cancel := _button("CANCEL", false)
	cancel.custom_minimum_size.x = 150
	cancel.pressed.connect(back_to_menu)
	buttons.add_child(cancel)
	_ready_button = _button("READY UP", false)
	_ready_button.custom_minimum_size.x = 180
	_ready_button.disabled = true
	_ready_button.pressed.connect(_toggle_ready)
	buttons.add_child(_ready_button)
	_start_button = _button("WAITING FOR HOST", true)
	_start_button.custom_minimum_size.x = 230
	_start_button.disabled = true
	_start_button.pressed.connect(func() -> void: _bridge.call("send_room_command", "start_game"))
	buttons.add_child(_start_button)
	return overlay


func _build_rules_overlay() -> Control:
	var overlay := _modal_base()
	overlay.hide()
	var panel := _panel(Color("17221d"), Color("b99445"), 3)
	panel.custom_minimum_size = Vector2(880, 690)
	overlay.get_node("Center").add_child(panel)
	var margin := _margin(24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := _label("CRIBBAGE RULES", 28, Color("f1d37d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.text = """[b][color=#f1d37d]PEGGING[/color][/b]  Play without passing 31. Score 2 for 15/31, 2/6/12 for pairs, and the length of a run. Last card before a go scores 1.

[b][color=#f1d37d]SHOW[/color][/b]  Every combination totaling 15 scores 2. Pairs score 2, runs score their length, a four-card flush scores 4 (five with the starter), and nobs scores 1. A crib flush requires all five cards.

[b][color=#f1d37d]FIVE PLAYERS[/color][/b]  Dealer gets 4. The other four get 5 and each discard 1 to the dealer's crib.

[b][color=#f1d37d]SIX PLAYERS[/color][/b]  Three teams sit A1–B1–C1–A2–B2–C2. Dealer and partner get 4. The other four get 5 and discard 1 each. The dealer's team owns the crib.

First player or team to 121 wins immediately."""
	column.add_child(text)
	var close := _button("BACK TO TABLE", true)
	close.pressed.connect(func() -> void: overlay.hide())
	column.add_child(close)
	return overlay


func _build_winner_overlay() -> Control:
	var overlay := _modal_base()
	overlay.hide()
	var panel := _panel(Color("1d2b23"), Color("e0b953"), 4)
	panel.custom_minimum_size = Vector2(570, 350)
	overlay.get_node("Center").add_child(panel)
	var margin := _margin(30)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	column.add_child(_label("🏆", 56, Color.WHITE))
	_winner_label = _label("", 28, Color("f2d277"))
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_winner_label)
	var again := _button("PLAY AGAIN", true)
	again.pressed.connect(_play_again)
	column.add_child(again)
	var menu := _button("CRIBBAGE MENU", false)
	menu.pressed.connect(back_to_menu)
	column.add_child(menu)
	return overlay


func _build_rotate_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color("09130f")
	overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var message := _label("↻\nROTATE TO LANDSCAPE\nThe cribbage table is waiting.", 34, Color("f2d37b"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(message)
	return overlay


func _start_local_game() -> void:
	_match = MATCH.new()
	var names: Array[String] = [String(_session.get("player_name"))]
	var bots: Array[bool] = [false]
	for index in range(1, int(_session.get("player_count"))):
		names.append(BOT_NAMES[index - 1])
		bots.append(true)
	_match.start(String(_session.get("mode")), names, bots)
	_ready_overlay.hide()
	_render_local()


func _local_snapshot() -> Dictionary:
	var shown_hand: Array = []
	if _match.phase == "show" or _match.phase == "game_over":
		shown_hand = _match.kept_hands[0].duplicate(true)
	elif not _match.hands.is_empty():
		shown_hand = _match.hands[0].duplicate(true)
	var player_views: Array[Dictionary] = []
	for index in _match.player_count:
		player_views.append({
			"id": _match.players[index].id,
			"name": _match.players[index].name,
			"team": _match.players[index].team,
			"score": _match.score_for_player(index),
			"connected": true,
			"cardCount": _match.hands[index].size(),
		})
	return {
		"mode": _match.mode,
		"playerCount": _match.player_count,
		"players": player_views,
		"selfIndex": 0,
		"dealer": _match.dealer,
		"activePlayer": _match.active_player,
		"phase": _match.phase,
		"hand": shown_hand,
		"starter": _match.starter.duplicate(true),
		"pegTotal": _match.peg_total,
		"playHistory": _match.play_history.duplicate(true),
		"showItems": _match.show_items.duplicate(true),
		"requiredDiscard": _match.required_discards[0],
		"discarded": _match.discarded[0],
		"status": _match.status,
		"winnerTeam": _match.winner_team,
		"revision": _match.revision,
	}


func _render_local() -> void:
	_game_state = _local_snapshot()
	_render_game_state()
	_queue_local_bot()


func _queue_local_bot() -> void:
	if _online or _bot_busy or _match == null:
		return
	var bot_index := -1
	if _match.phase == "discarding":
		for index in range(1, _match.player_count):
			if not _match.discarded[index]:
				bot_index = index
				break
	elif _match.phase == "pegging" and _match.active_player > 0:
		bot_index = _match.active_player
	if bot_index < 0:
		return
	_bot_busy = true
	_run_local_bot(bot_index)


func _run_local_bot(player_index: int) -> void:
	await get_tree().create_timer(0.38).timeout
	if not is_instance_valid(self) or _match == null:
		return
	if _match.phase == "discarding" and not _match.discarded[player_index]:
		_match.discard_cards(player_index, _match.bot_discard_indices(player_index))
	elif _match.phase == "pegging" and _match.active_player == player_index:
		var card_index := _match.bot_play_index(player_index)
		if card_index >= 0:
			_match.play_card(player_index, card_index)
	_bot_busy = false
	_render_local()


func _render_game_state() -> void:
	if _game_state.is_empty():
		return
	_selected_indices.clear()
	var mode := String(_game_state.get("mode", "standard"))
	var count := int(_game_state.get("playerCount", 2))
	_mode_label.text = "%s  •  %d players%s" % [
		RULES.mode_title(mode), count,
		"  •  ONLINE" if _online else "  •  BOTS",
	]
	_status_label.text = String(_game_state.get("status", ""))
	_count_label.text = "COUNT  %d" % int(_game_state.get("pegTotal", 0))
	var starter: Dictionary = _game_state.get("starter", {})
	_starter_texture.texture = _card_texture(starter) if not starter.is_empty() else null
	_starter_label.text = "STARTER" if not starter.is_empty() else "WAITING FOR CUT"
	_render_scores()
	_render_opponents()
	_render_history()
	_render_hand()
	_update_action()
	var phase := String(_game_state.get("phase", ""))
	if phase == "game_over":
		_winner_label.text = String(_game_state.get("status", "Game over"))
		_winner_overlay.show()
	else:
		_winner_overlay.hide()


func _render_scores() -> void:
	for child in _score_list.get_children():
		child.queue_free()
	var players: Array = _game_state.get("players", [])
	var dealer := int(_game_state.get("dealer", -1))
	var active := int(_game_state.get("activePlayer", -1))
	for index in players.size():
		var player: Dictionary = players[index]
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)
		card.add_theme_stylebox_override("panel", _panel_style(Color("20342a"), Color("5c7865"), 9, 1))
		var markers: Array[String] = []
		if index == dealer: markers.append("DEALER")
		if index == active: markers.append("TURN")
		if int(player.get("team", index)) != index: markers.append("TEAM %s" % char(65 + int(player.team)))
		var name := _label(String(player.get("name", "Player")), 26 if _compact_layout else 15, Color("f0e0b9"))
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.add_child(name)
		var score := int(player.get("score", 0))
		if not _compact_layout:
			var progress := ProgressBar.new()
			progress.max_value = RULES.WINNING_SCORE
			progress.value = score
			progress.custom_minimum_size.y = 20
			progress.show_percentage = false
			card.add_child(progress)
		var detail := _label("%d / 121%s" % [score, "  •  " + "/".join(markers) if not markers.is_empty() else ""], 21 if _compact_layout else 12, Color("b7c6bc"))
		card.add_child(detail)
		_score_list.add_child(card)


func _render_opponents() -> void:
	for child in _opponents.get_children():
		child.queue_free()
	var players: Array = _game_state.get("players", [])
	var self_index := int(_game_state.get("selfIndex", 0))
	for index in players.size():
		if index == self_index:
			continue
		var player: Dictionary = players[index]
		var display_name := String(player.get("name", "Player"))
		if _compact_layout and display_name.length() > 8:
			display_name = display_name.left(8)
		var text := "%s • %d" % [display_name, int(player.get("cardCount", 0))]
		if index == int(_game_state.get("dealer", -1)):
			text += "  •  CRIB"
		var badge := _label(text, 22 if _compact_layout else 13, Color("d6e0d8"))
		badge.add_theme_stylebox_override("normal", _panel_style(Color("1a4b34"), Color("6f9278"), 8, 1))
		_opponents.add_child(badge)


func _render_history() -> void:
	var lines: Array[String] = []
	var show_items: Array = _game_state.get("showItems", [])
	if not show_items.is_empty():
		lines.append("[color=#e8c96f][b]THE SHOW[/b][/color]\n")
		for raw_item in show_items:
			var item: Dictionary = raw_item
			lines.append("[b]%s[/b] — %d\n%s\n%s\n" % [
				String(item.get("name", "Hand")),
				int(item.get("points", 0)),
				_cards_text(item.get("cards", [])),
				String(item.get("detail", "")),
			])
	else:
		lines.append("[color=#e8c96f][b]PEGGING[/b][/color]\n")
		var history: Array = _game_state.get("playHistory", [])
		var players: Array = _game_state.get("players", [])
		for start in range(maxi(0, history.size() - 12), history.size()):
			var play: Dictionary = history[start]
			var player_index := int(play.get("player", 0))
			var player_name := String(players[player_index].get("name", "Player")) if player_index < players.size() else "Player"
			lines.append("%s played [b]%s[/b]  →  %d%s" % [
				player_name,
				RULES.card_label(play.get("card", {})),
				int(play.get("count", 0)),
				"  [color=#e8c96f]+%d[/color]" % int(play.get("points", 0)) if int(play.get("points", 0)) > 0 else "",
			])
	_history.text = "\n".join(lines)


func _render_hand() -> void:
	for child in _hand_row.get_children():
		child.queue_free()
	var hand: Array = _game_state.get("hand", [])
	var phase := String(_game_state.get("phase", ""))
	var self_index := int(_game_state.get("selfIndex", 0))
	var active := int(_game_state.get("activePlayer", -1))
	var legal: Array[int] = []
	if phase == "pegging":
		for index in hand.size():
			if RULES.card_value(hand[index]) + int(_game_state.get("pegTotal", 0)) <= 31:
				legal.append(index)
	for index in hand.size():
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 172) if _compact_layout else Vector2(86, 124)
		button.icon = _card_texture(hand[index])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 112 if _compact_layout else 80)
		button.tooltip_text = RULES.card_label(hand[index])
		button.toggle_mode = phase == "discarding"
		button.disabled = (
			phase == "discarding" and bool(_game_state.get("discarded", false))
			or phase == "pegging" and (self_index != active or not legal.has(index))
			or phase != "discarding" and phase != "pegging"
		)
		button.toggled.connect(_on_card_toggled.bind(index))
		button.pressed.connect(_on_card_pressed.bind(index))
		button.add_theme_stylebox_override("normal", _panel_style(Color("efe8d7"), Color("9e8955"), 8, 2))
		button.add_theme_stylebox_override("hover", _panel_style(Color("fff9e8"), Color("f4cf63"), 8, 3))
		button.add_theme_stylebox_override("pressed", _panel_style(Color("fff4bf"), Color("ffd659"), 8, 4))
		button.add_theme_stylebox_override("disabled", _panel_style(Color("8d958f"), Color("56625a"), 8, 1))
		_hand_row.add_child(button)


func _update_action() -> void:
	var phase := String(_game_state.get("phase", ""))
	var required := int(_game_state.get("requiredDiscard", 0))
	var self_index := int(_game_state.get("selfIndex", 0))
	match phase:
		"discarding":
			if bool(_game_state.get("discarded", false)) or required == 0:
				_hand_hint.text = "Your cards are set. Waiting for the rest of the table."
				_action_button.text = "WAITING FOR DISCARD"
				_action_button.disabled = true
			else:
				_hand_hint.text = "Choose %d card%s to send to %s's crib." % [
					required, "" if required == 1 else "s",
					_game_state.players[int(_game_state.dealer)].name,
				]
				_action_button.text = "SEND %d TO THE CRIB" % required
				_action_button.disabled = _selected_indices.size() != required
		"pegging":
			if int(_game_state.get("activePlayer", -1)) == self_index:
				_hand_hint.text = "Your play. Choose a card that keeps the count at 31 or less."
			else:
				var active := int(_game_state.get("activePlayer", -1))
				var active_name := String(_game_state.players[active].name) if active >= 0 else "table"
				_hand_hint.text = "Waiting for %s." % active_name
			_action_button.text = "PLAY A CARD FROM YOUR HAND"
			_action_button.disabled = true
		"show":
			_hand_hint.text = "Hands count left of the dealer first; the crib counts last."
			_action_button.text = "DEAL NEXT HAND"
			_action_button.disabled = _online and not _is_online_host()
		"game_over":
			_hand_hint.text = "Game complete."
			_action_button.text = "PLAY AGAIN"
			_action_button.disabled = _online and not _is_online_host()
		_:
			_action_button.disabled = true


func _on_card_toggled(pressed: bool, index: int) -> void:
	if String(_game_state.get("phase", "")) != "discarding":
		return
	if pressed and not _selected_indices.has(index):
		_selected_indices.append(index)
	elif not pressed:
		_selected_indices.erase(index)
	var required := int(_game_state.get("requiredDiscard", 0))
	if _selected_indices.size() > required:
		var removed: int = _selected_indices.pop_front()
		var old_button: Button = _hand_row.get_child(removed)
		old_button.set_pressed_no_signal(false)
	_update_action()


func _on_card_pressed(index: int) -> void:
	if String(_game_state.get("phase", "")) != "pegging":
		return
	if _online:
		_bridge.call("send_room_command", "play_card", {"cardIndex": index})
	else:
		_match.play_card(0, index)
		_render_local()


func _on_action_pressed() -> void:
	var phase := String(_game_state.get("phase", ""))
	if phase == "discarding":
		var selected := _selected_indices.duplicate()
		selected.sort()
		if _online:
			_bridge.call("send_room_command", "discard", {"cardIndices": selected})
		else:
			_match.discard_cards(0, selected)
			_render_local()
	elif phase == "show":
		if _online:
			_bridge.call("send_room_command", "next_deal")
		else:
			_match.continue_after_show()
			_render_local()
	elif phase == "game_over":
		_play_again()


func _play_again() -> void:
	if _online:
		if _is_online_host():
			_bridge.call("send_room_command", "reset_game")
	else:
		_start_local_game()


func _on_context_changed(context: Dictionary) -> void:
	var user: Dictionary = context.get("currentUser", {})
	if not _ready_name.has_focus() and not String(user.get("name", "")).is_empty():
		_ready_name.text = String(user.name)


func _on_room_status(status: String) -> void:
	if not _online:
		return
	match status:
		"connecting": _ready_status.text = "Connecting to the Cribbage room…"
		"reconnecting": _ready_status.text = "Connection lost — reconnecting…"
		"disconnected": _ready_status.text = "Disconnected from the room."


func _on_room_error(message: String) -> void:
	_ready_status.text = message
	_status_label.text = message


func _on_room_state(room: Dictionary) -> void:
	if not _online or room.is_empty():
		return
	_room = room.duplicate(true)
	var players: Array = room.get("players", [])
	var local_id := String(_bridge.call("current_user_id"))
	var local_player: Dictionary = {}
	for index in range(6):
		var seat: Label = _seat_grid.get_node("Seat%d" % (index + 1))
		if index < players.size():
			var player: Dictionary = players[index]
			var marks: Array[String] = []
			if String(player.id) == String(room.get("hostId", "")): marks.append("HOST")
			if bool(player.get("ready", false)): marks.append("READY")
			if not bool(player.get("connected", true)): marks.append("OFFLINE")
			seat.text = "%d. %s%s" % [index + 1, String(player.name), "  •  " + " / ".join(marks) if not marks.is_empty() else ""]
			seat.show()
			if String(player.id) == local_id:
				local_player = player
		else:
			seat.text = "%d. Waiting for player…" % (index + 1)
			seat.visible = index < int(room.get("playerCount", 6)) if bool(room.get("configured", false)) else true
	var configured := bool(room.get("configured", false))
	var is_host := local_id == String(room.get("hostId", ""))
	if is_host and not configured and not _configuration_sent:
		_configuration_sent = true
		_bridge.call("send_room_command", "configure", {
			"mode": String(_session.get("mode")),
			"playerCount": int(_session.get("player_count")),
		})
	if configured:
		_ready_mode.text = "%s  •  %d players" % [RULES.mode_title(String(room.mode)), int(room.playerCount)]
	else:
		_ready_mode.text = "Waiting for the host to choose the table…"
	var self_ready := bool(local_player.get("ready", false))
	_ready_button.text = "NOT READY" if self_ready else "READY UP"
	_ready_button.disabled = local_player.is_empty() or not configured
	var required_count := int(room.get("playerCount", 0))
	var all_ready := configured and players.size() == required_count
	for player in players:
		if not bool(player.get("connected", false)) or not bool(player.get("ready", false)):
			all_ready = false
	_start_button.visible = is_host
	_start_button.text = "START GAME" if is_host else "WAITING FOR HOST"
	_start_button.disabled = not is_host or not all_ready
	_ready_status.text = (
		"Everyone is ready. Start the game!" if all_ready and is_host
		else "%d of %d seats filled. Everyone must ready up." % [players.size(), required_count] if configured
		else "The host is choosing a game type and table size."
	)
	if String(room.get("phase", "waiting")) == "waiting":
		_ready_overlay.show()
	else:
		_ready_overlay.hide()


func _on_game_state(game_state: Dictionary) -> void:
	if not _online or game_state.is_empty():
		return
	_game_state = game_state.duplicate(true)
	_ready_overlay.hide()
	_render_game_state()


func _toggle_ready() -> void:
	var local_id := String(_bridge.call("current_user_id"))
	for player in _room.get("players", []):
		if String(player.get("id", "")) == local_id:
			_bridge.call("send_room_command", "set_ready", {"ready": not bool(player.get("ready", false))})
			return


func _submit_name() -> void:
	var value := _ready_name.text.strip_edges()
	if not value.is_empty():
		_bridge.call("send_room_command", "set_name", {"name": value})


func _is_online_host() -> bool:
	return String(_room.get("hostId", "")) == String(_bridge.call("current_user_id"))


func _apply_responsive_layout() -> void:
	var viewport := get_viewport_rect().size
	var window_size := Vector2(get_window().size)
	var portrait := window_size.y > window_size.x
	_rotate_overlay.visible = portrait
	_main_content.visible = not portrait
	if portrait:
		return
	_compact_layout = window_size.x < 1050 or window_size.y < 620
	_set_margins(_main_content, 14 if _compact_layout else 18)
	_header.custom_minimum_size.y = 96 if _compact_layout else 58
	for header_child in _header.get_children():
		if header_child is Button:
			header_child.custom_minimum_size.y = 90 if _compact_layout else 50
			header_child.add_theme_font_size_override("font_size", 28 if _compact_layout else 15)
	_score_panel.custom_minimum_size.x = 340 if _compact_layout else 245
	_log_panel.visible = not _compact_layout
	_ready_panel.custom_minimum_size = Vector2(minf(1800, viewport.x - 30), minf(840, viewport.y - 30)) if _compact_layout else Vector2(840, 660)
	var ready_margin: MarginContainer = _ready_panel.get_child(0)
	_set_margins(ready_margin, 20 if _compact_layout else 24)
	var ready_column: VBoxContainer = ready_margin.get_child(0)
	ready_column.add_theme_constant_override("separation", 8 if _compact_layout else 11)
	var ready_title: Label = ready_column.get_child(0)
	ready_title.add_theme_font_size_override("font_size", 50 if _compact_layout else 30)
	_ready_mode.add_theme_font_size_override("font_size", 28 if _compact_layout else 17)
	_ready_status.add_theme_font_size_override("font_size", 25 if _compact_layout else 16)
	_ready_name.custom_minimum_size.y = 84 if _compact_layout else 48
	_ready_name.add_theme_font_size_override("font_size", 28 if _compact_layout else 16)
	for seat in _seat_grid.get_children():
		seat.custom_minimum_size.y = 68 if _compact_layout else 36
		seat.add_theme_font_size_override("font_size", 26 if _compact_layout else 16)
	var ready_buttons: HBoxContainer = ready_column.get_child(5)
	for button in ready_buttons.get_children():
		button.custom_minimum_size.y = 90 if _compact_layout else 48
		button.add_theme_font_size_override("font_size", 27 if _compact_layout else 15)
	_set_margins(_table_margin, 12 if _compact_layout else 14)
	_table_column.add_theme_constant_override("separation", 7 if _compact_layout else 8)
	_starter_texture.custom_minimum_size = Vector2(68, 96) if _compact_layout else Vector2(48, 68)
	_status_label.custom_minimum_size.y = 72 if _compact_layout else 56
	_status_label.add_theme_font_size_override("font_size", 32 if _compact_layout else 23)
	_count_label.add_theme_font_size_override("font_size", 42 if _compact_layout else 30)
	_hand_title.visible = not _compact_layout
	_hand_hint.add_theme_font_size_override("font_size", 25 if _compact_layout else 15)
	_action_button.custom_minimum_size.y = 92 if _compact_layout else 52
	_action_button.add_theme_font_size_override("font_size", 28 if _compact_layout else 15)
	for child in _hand_row.get_children():
		if child is Button:
			child.custom_minimum_size = Vector2(120, 172) if _compact_layout else Vector2(86, 124)
			child.add_theme_constant_override("icon_max_width", 112 if _compact_layout else 80)
	if not _game_state.is_empty():
		_render_scores()
		_render_opponents()


func back_to_menu() -> void:
	if _online:
		_bridge.call("end_multiplayer")
	_session.call("reset")
	get_tree().change_scene_to_file(MENU_SCENE)


func _card_texture(card: Dictionary) -> Texture2D:
	if card.is_empty():
		return null
	var texture_suit: String = {
		"clubs": "clubs",
		"diamonds": "diamond",
		"hearts": "heart",
		"spades": "spade",
	}.get(String(card.get("suit", "clubs")), "clubs")
	var path := "res://shared/assets/Cards/card_%s_%d.png" % [texture_suit, int(card.get("rank", 1))]
	return load(path) as Texture2D


func _cards_text(cards: Array) -> String:
	var labels: Array[String] = []
	for card in cards:
		labels.append(RULES.card_label(card))
	return "  ".join(labels)


func _modal_base() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.03, 0.022, 0.95)
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
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("172019") if accent else Color("f0ddb0"))
	button.add_theme_color_override("font_hover_color", Color("101611") if accent else Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(Color("d6b65e") if accent else Color("263830"), Color("8c7137"), 10, 2))
	button.add_theme_stylebox_override("hover", _panel_style(Color("efd27a") if accent else Color("355047"), Color("f3da8c"), 10, 3))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("f6de8e") if accent else Color("416055"), Color("fff0aa"), 10, 3))
	button.add_theme_stylebox_override("focus", _panel_style(Color.TRANSPARENT, Color("fff0aa"), 10, 3))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("1b2520"), Color("39453d"), 10, 1))
	return button


func _panel(background: Color, border: Color, border_width: int = 2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(background, border, 14, border_width))
	return panel


func _panel_style(background: Color, border: Color, radius: int, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	return style


func _margin(amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	_set_margins(margin, amount)
	return margin


func _set_margins(container: MarginContainer, amount: int) -> void:
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_%s" % side, amount)
