extends Control
## Presentation layer. It renders JokerGameController state and forwards player input.

const CARD_VIEW_SCENE: PackedScene = preload("res://games/joker/scenes/ui/card_view.tscn")
const GAME_WORD := "JOKER"
const MOBILE_PORTRAIT_OPPONENT_HEIGHT := 258.0
const MOBILE_PORTRAIT_TABLE_HEIGHT := 416.0
const MOBILE_PORTRAIT_HAND_HEIGHT := 426.0
const NETWORK_CARDS: Dictionary = {
	"spade_ace": preload("res://games/joker/resources/ranks/spade_ace.tres"),
	"spade_two": preload("res://games/joker/resources/ranks/spade_two.tres"),
	"spade_three": preload("res://games/joker/resources/ranks/spade_three.tres"),
	"spade_four": preload("res://games/joker/resources/ranks/spade_four.tres"),
	"heart_ace": preload("res://games/joker/resources/ranks/heart_ace.tres"),
	"heart_two": preload("res://games/joker/resources/ranks/heart_two.tres"),
	"heart_three": preload("res://games/joker/resources/ranks/heart_three.tres"),
	"heart_four": preload("res://games/joker/resources/ranks/heart_four.tres"),
	"club_ace": preload("res://games/joker/resources/ranks/club_ace.tres"),
	"club_two": preload("res://games/joker/resources/ranks/club_two.tres"),
	"club_three": preload("res://games/joker/resources/ranks/club_three.tres"),
	"club_four": preload("res://games/joker/resources/ranks/club_four.tres"),
	"diamond_ace": preload("res://games/joker/resources/ranks/diamond_ace.tres"),
	"diamond_two": preload("res://games/joker/resources/ranks/diamond_two.tres"),
	"diamond_three": preload("res://games/joker/resources/ranks/diamond_three.tres"),
	"diamond_four": preload("res://games/joker/resources/ranks/diamond_four.tres"),
	"joker": preload("res://games/joker/resources/ranks/joker.tres"),
}

@onready var game: JokerGameController = %GameController
@onready var audio_manager: JokerAudioManager = %AudioManager
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var round_label: Label = %RoundLabel
@onready var status_label: Label = %StatusLabel
@onready var score_label: Label = %ScoreLabel
@onready var hand_container: HBoxContainer = %HandContainer
@onready var slap_button: Button = %SlapButton
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_body: Label = %ResultBody
@onready var next_round_button: Button = %NextRoundButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var rules_overlay: JokerRulesOverlay = %RulesOverlay
@onready var sound_toggle: CheckButton = %SoundToggle
@onready var bot_speed_slider: HSlider = %BotSpeedSlider
@onready var bot_speed_value: Label = %BotSpeedValue
@onready var main_menu_button: Button = %MainMenuButton
@onready var waiting_overlay: JokerWaitingOverlay = %WaitingOverlay

var _opponent_names: Array[Label]
var _opponent_counts: Array[Label]
var _opponent_scores: Array[Label]
var _slap_places: Array[Label]
var _settings := JokerSettingsStore.new()
var _is_multiplayer := false
var _network_state: Dictionary = {}
var _last_network_revision := -1
var _opponent_seats: Array[int] = []
var _discord_bridge: Node


func _ready() -> void:
	_discord_bridge = get_node("/root/JokerDiscordBridge")
	_discord_bridge.connect("shell_command_requested", _on_shell_command_requested)
	_opponent_names = [%Opponent1Name, %Opponent2Name, %Opponent3Name]
	_opponent_counts = [%Opponent1Count, %Opponent2Count, %Opponent3Count]
	_opponent_scores = [%Opponent1Score, %Opponent2Score, %Opponent3Score]
	_slap_places = [%SlapPlace1, %SlapPlace2, %SlapPlace3, %SlapPlace4]

	_apply_mobile_layout()
	if JokerMobileUI.is_active():
		get_viewport().size_changed.connect(_apply_mobile_layout)
	_connect_signals()
	_load_settings()
	waiting_overlay.bot_speed_scale = _settings.bot_speed_scale
	_is_multiplayer = bool(_discord_bridge.get("multiplayer_requested"))
	if _is_multiplayer:
		_discord_bridge.connect("game_state_changed", _on_network_game_state)
		waiting_overlay.cancelled.connect(_return_to_main_menu)
		waiting_overlay.begin()
	else:
		game.start_game()


func _apply_mobile_layout() -> void:
	if OS.has_feature("web"):
		%SettingsButton.hide()
	if not JokerMobileUI.is_active():
		return

	var portrait := get_viewport_rect().size.y > get_viewport_rect().size.x
	for control: Control in [
		%SettingsButton,
		%RulesButton,
		next_round_button,
		sound_toggle,
		%CloseSettingsButton,
		main_menu_button,
	]:
		JokerMobileUI.enlarge_control(control)
	JokerMobileUI.enlarge_control(bot_speed_slider, 72.0, 0)
	JokerMobileUI.enlarge_control(slap_button, 112.0 if portrait else 82.0, 32)
	slap_button.text = "SLAP THE TABLE"
	slap_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	$MainMargin/MainColumn/TablePanel/Margin/Column/SlapOrder.hide()

	$MainMargin/MainColumn.alignment = (
		BoxContainer.ALIGNMENT_CENTER if portrait else BoxContainer.ALIGNMENT_BEGIN
	)
	_set_minimum_height($MainMargin/MainColumn/Header, 70.0 if portrait else 0.0)
	%Branded.add_theme_font_size_override("font_size", 36)
	%Subtitle.add_theme_font_size_override("font_size", 20)
	round_label.add_theme_font_size_override("font_size", 24)

	for panel: PanelContainer in [
		$MainMargin/MainColumn/Opponents/Opponent1,
		$MainMargin/MainColumn/Opponents/Opponent2,
		$MainMargin/MainColumn/Opponents/Opponent3,
	]:
		_set_minimum_height(panel, MOBILE_PORTRAIT_OPPONENT_HEIGHT if portrait else 110.0)
	for label in _opponent_names:
		label.add_theme_font_size_override("font_size", 26)
	for label in _opponent_counts + _opponent_scores:
		label.add_theme_font_size_override("font_size", 20)

	var table_panel: PanelContainer = %TablePanel
	table_panel.size_flags_vertical = Control.SIZE_FILL if portrait else Control.SIZE_EXPAND_FILL
	_set_minimum_height(table_panel, MOBILE_PORTRAIT_TABLE_HEIGHT if portrait else 218.0)
	status_label.add_theme_font_size_override("font_size", 28)
	for place in _slap_places:
		place.add_theme_font_size_override("font_size", 20)
	$MainMargin/MainColumn/TablePanel/Margin/Column/RuleHint.add_theme_font_size_override(
		"font_size", 18
	)

	var human_panel: PanelContainer = $MainMargin/MainColumn/HumanPanel
	human_panel.size_flags_vertical = Control.SIZE_FILL
	_set_minimum_height(human_panel, MOBILE_PORTRAIT_HAND_HEIGHT if portrait else 220.0)
	$MainMargin/MainColumn/HumanPanel/Margin.add_theme_constant_override("margin_left", 8)
	$MainMargin/MainColumn/HumanPanel/Margin.add_theme_constant_override("margin_right", 8)
	$MainMargin/MainColumn/HumanPanel/Margin/Column/HumanHeader/YouLabel.add_theme_font_size_override(
		"font_size", 26
	)
	score_label.add_theme_font_size_override("font_size", 22)
	hand_container.add_theme_constant_override("separation", 7 if portrait else 12)
	for card in hand_container.get_children():
		if card is JokerCardView:
			card.apply_mobile_layout()


func _set_minimum_height(control: Control, height: float) -> void:
	var minimum := control.custom_minimum_size
	minimum.y = height
	control.custom_minimum_size = minimum


func _unhandled_input(event: InputEvent) -> void:
	if rules_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			rules_overlay.close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("joker_slap"):
		_on_slap_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and settings_overlay.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var card_index := _card_index_from_key(event)
		if card_index >= 0 and _try_pass_card_by_number(card_index):
			get_viewport().set_input_as_handled()


func _card_index_from_key(event: InputEventKey) -> int:
	if (
		not event.pressed
		or event.echo
		or event.alt_pressed
		or event.ctrl_pressed
		or event.meta_pressed
		or event.shift_pressed
	):
		return -1

	for key_code in [event.keycode, event.physical_keycode, event.key_label]:
		match key_code:
			KEY_1, KEY_KP_1:
				return 0
			KEY_2, KEY_KP_2:
				return 1
			KEY_3, KEY_KP_3:
				return 2
			KEY_4, KEY_KP_4:
				return 3
			KEY_5, KEY_KP_5:
				return 4
	return -1


func _try_pass_card_by_number(card_index: int) -> bool:
	if card_index < 0 or card_index >= hand_container.get_child_count():
		return false
	var card_view := hand_container.get_child(card_index) as JokerCardView
	if card_view == null or card_view.disabled:
		return false
	_on_card_chosen(card_index)
	return true


func _connect_signals() -> void:
	game.round_started.connect(_on_round_started)
	game.hand_changed.connect(_on_hand_changed)
	game.active_player_changed.connect(_on_active_player_changed)
	game.status_changed.connect(_on_status_changed)
	game.card_passed.connect(_on_card_passed)
	game.slap_registered.connect(_on_slap_registered)
	game.round_ended.connect(_on_round_ended)
	game.scores_changed.connect(_refresh_all_scores)
	game.game_finished.connect(_on_game_finished)
	game.card_passed.connect(_play_by_play.unbind(2))

	%SettingsButton.pressed.connect(_open_settings)
	%RulesButton.pressed.connect(_open_rules)
	%CloseSettingsButton.pressed.connect(_close_settings)
	slap_button.pressed.connect(_on_slap_pressed)
	next_round_button.pressed.connect(_on_next_round_pressed)
	sound_toggle.toggled.connect(_on_sound_toggled)
	bot_speed_slider.value_changed.connect(_on_bot_speed_changed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

func _load_settings() -> void:
	_settings.load_from_disk()
	audio_manager.sound_enabled = _settings.sound_enabled
	game.bot_speed_scale = _settings.bot_speed_scale
	sound_toggle.set_pressed_no_signal(_settings.sound_enabled)
	bot_speed_slider.set_value_no_signal(_settings.bot_speed_scale)
	_update_speed_label(_settings.bot_speed_scale)


func _on_round_started(new_round_number: int, starting_player: int) -> void:
	round_label.text = "ROUND %d" % new_round_number
	result_overlay.hide()
	next_round_button.text = "NEXT ROUND"
	for place in _slap_places:
		place.text = "—"
	_on_active_player_changed(starting_player)


func _on_hand_changed(player_index: int) -> void:
	if player_index == 0:
		_refresh_human_hand()
	else:
		_refresh_opponent(player_index)


func _on_active_player_changed(player_index: int) -> void:
	_refresh_human_hand()
	for opponent_index in range(1, game.players.size()):
		_refresh_opponent(opponent_index)
	slap_button.disabled = game.phase not in [JokerGameController.Phase.PASSING, JokerGameController.Phase.SLAPPING]
	if game.phase == JokerGameController.Phase.SLAPPING and game.human_has_slapped():
		slap_button.disabled = true


func _on_status_changed(message: String) -> void:
	status_label.text = _mobile_instruction(message)


func _on_card_passed(_from_player: int, _to_player: int) -> void:
	audio_manager.play_pass()


func _on_slap_registered(player_index: int, place: int) -> void:
	animation_player.stop()
	animation_player.play("slap_flash")
	audio_manager.play_slap()
	_slap_places[place - 1].text = "%d · %s" % [place, game.players[player_index].display_name]
	if player_index == 0:
		slap_button.disabled = true


func _on_round_ended(result: Dictionary) -> void:
	var winner_index: int = result["winner"]
	var combo: JokerGameRules.Combo = result["combo"]
	var slap_order: Array = result["slap_order"]
	var penalized: Array = result["penalized"]

	var order_names: PackedStringArray = []
	for player_index: int in slap_order:
		order_names.append(game.players[player_index].display_name)
	var penalty_names: PackedStringArray = []
	for player_index: int in penalized:
		penalty_names.append(game.players[player_index].display_name)

	result_title.text = JokerGameRules.combo_title(combo)
	result_body.text = (
		"%s completed the set.\n\nSlap order: %s\n\nLetter%s: %s\n%s"
		% [
			game.players[winner_index].display_name,
			" > ".join(order_names),
			"s" if penalized.size() > 1 else "",
			", ".join(penalty_names),
			JokerGameRules.penalty_description(combo),
		]
	)
	result_overlay.show()
	if penalized.has(0):
		audio_manager.play_letter()
	else:
		audio_manager.play_round_win()


func _on_game_finished(losers: Array[int]) -> void:
	var names: PackedStringArray = []
	for player_index in losers:
		names.append(game.players[player_index].display_name)
	result_title.text = "GAME OVER"
	result_body.text += "\n\n%s completed JOKER." % ", ".join(names)
	next_round_button.text = "NEW GAME"


func _refresh_human_hand() -> void:
	if game.players.is_empty():
		return
	for old_card in hand_container.get_children():
		hand_container.remove_child(old_card)
		old_card.queue_free()

	var can_pass := game.human_can_pass()
	for card_index in game.players[0].hand.size():
		var card_view := CARD_VIEW_SCENE.instantiate() as JokerCardView
		hand_container.add_child(card_view)
		card_view.setup(game.players[0].hand[card_index], card_index, can_pass)
		card_view.card_chosen.connect(_on_card_chosen)

	_refresh_all_scores()


func _refresh_opponent(player_index: int) -> void:
	if game.players.is_empty():
		return
	var ui_index := player_index - 1
	var turn_marker := "  <" if game.active_player == player_index and game.phase == JokerGameController.Phase.PASSING else ""
	_opponent_names[ui_index].text = game.players[player_index].display_name + turn_marker
	_opponent_counts[ui_index].text = "CARDS  %d" % game.players[player_index].hand.size()
	_opponent_scores[ui_index].text = "LETTERS  %s" % game.players[player_index].score_label()


func _refresh_all_scores() -> void:
	if game.players.is_empty():
		return
	score_label.text = "YOUR LETTERS  %s" % game.players[0].score_label()
	for player_index in range(1, game.players.size()):
		_refresh_opponent(player_index)


func _on_card_chosen(card_index: int) -> void:
	if _is_multiplayer:
		_discord_bridge.call("send_room_command", "pass_card", {"cardIndex": card_index})
	else:
		game.pass_card(card_index)


func _on_next_round_pressed() -> void:
	if _is_multiplayer:
		_discord_bridge.call("send_room_command", "advance_round")
		return
	if game.phase == JokerGameController.Phase.GAME_OVER:
		game.start_game()
	else:
		game.start_next_round()


func _open_settings() -> void:
	rules_overlay.close()
	settings_overlay.show()


func _open_rules() -> void:
	settings_overlay.hide()
	rules_overlay.open()


func _on_shell_command_requested(command: String) -> void:
	if command == "open_settings":
		_open_settings()


func _close_settings() -> void:
	_settings.save_to_disk()
	settings_overlay.hide()


func _on_sound_toggled(enabled: bool) -> void:
	_settings.sound_enabled = enabled
	audio_manager.sound_enabled = enabled


func _on_bot_speed_changed(value: float) -> void:
	_settings.bot_speed_scale = value
	game.bot_speed_scale = value
	waiting_overlay.bot_speed_scale = value
	if _is_multiplayer and not _network_state.is_empty():
		var room: Dictionary = _discord_bridge.get("room_state")
		if String(room.get("hostId", "")) == String(_discord_bridge.call("current_user_id")):
			_discord_bridge.call(
				"send_room_command",
				"set_bot_speed",
				{"botSpeedScale": value}
			)
	_update_speed_label(value)


func _update_speed_label(value: float) -> void:
	if value < 0.85:
		bot_speed_value.text = "RELAXED"
	elif value > 1.25:
		bot_speed_value.text = "FAST"
	else:
		bot_speed_value.text = "NORMAL"

func _on_main_menu_pressed() -> void:
	if _is_multiplayer:
		_discord_bridge.call("end_multiplayer")
	get_tree().change_scene_to_file("res://games/joker/scenes/main_menu.tscn")


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://games/joker/scenes/main_menu.tscn")


func _on_slap_pressed() -> void:
	if _is_multiplayer:
		_discord_bridge.call("send_room_command", "slap")
	else:
		game.request_human_slap()


func _on_network_game_state(state: Dictionary) -> void:
	_network_state = state
	waiting_overlay.hide()
	var revision := int(state.get("revision", 0))
	if revision > _last_network_revision:
		_play_network_event(state.get("lastEvent", {}))
		_last_network_revision = revision
	_render_network_state()


func _render_network_state() -> void:
	var players: Array = _network_state.get("players", [])
	var local_seat := int(_network_state.get("localSeat", -1))
	if local_seat < 0 or local_seat >= players.size():
		return

	round_label.text = "ROUND %d" % int(_network_state.get("roundNumber", 1))
	_opponent_seats.clear()
	for offset in range(1, players.size()):
		_opponent_seats.append((local_seat + offset) % players.size())

	var phase := String(_network_state.get("phase", "passing"))
	var active_seat := int(_network_state.get("activeSeat", -1))
	var slap_order: Array = _network_state.get("slapOrder", [])
	var local_hand := _network_hand()
	var combo := JokerGameRules.evaluate_hand(local_hand)
	if phase == "passing" and combo != JokerGameRules.Combo.NONE:
		status_label.text = "You have %s - SLAP!" % JokerGameRules.combo_title(combo)
	elif phase == "passing" and active_seat == local_seat:
		status_label.text = _mobile_instruction(
			"Your turn - click a card or press 1-5 to pass it right."
		)
	elif phase == "passing" and active_seat >= 0:
		status_label.text = "%s is choosing a card..." % String(players[active_seat].get("name", "Player"))
	elif phase == "slapping":
		var winner := int(_network_state.get("winningSeat", 0))
		status_label.text = _mobile_instruction(
			"%s slapped! Hit SPACE or SLAP now!" % String(players[winner].get("name", "Player"))
		)

	for place in _slap_places:
		place.text = "—"
	for place_index in slap_order.size():
		var seat := int(slap_order[place_index])
		_slap_places[place_index].text = "%d · %s" % [
			place_index + 1,
			String(players[seat].get("name", "Player")),
		]

	_refresh_network_hand(local_hand, phase == "passing" and active_seat == local_seat)
	for ui_index in _opponent_seats.size():
		_refresh_network_opponent(ui_index, _opponent_seats[ui_index], active_seat, phase, players)
	score_label.text = "YOUR LETTERS  %s" % _score_text(int(players[local_seat].get("letters", 0)))

	slap_button.disabled = phase not in ["passing", "slapping"]
	if phase == "slapping" and slap_order.has(local_seat):
		slap_button.disabled = true
	if phase in ["round_result", "game_over"]:
		_render_network_result(players, local_seat, phase)
	else:
		result_overlay.hide()


func _network_hand() -> Array[JokerCardDefinition]:
	var hand: Array[JokerCardDefinition] = []
	for card_id: String in _network_state.get("hand", []):
		var card: JokerCardDefinition = NETWORK_CARDS.get(card_id)
		if card != null:
			hand.append(card)
	return hand


func _refresh_network_hand(hand: Array[JokerCardDefinition], can_pass: bool) -> void:
	for old_card in hand_container.get_children():
		hand_container.remove_child(old_card)
		old_card.queue_free()
	for card_index in hand.size():
		var card_view := CARD_VIEW_SCENE.instantiate() as JokerCardView
		hand_container.add_child(card_view)
		card_view.setup(hand[card_index], card_index, can_pass)
		card_view.card_chosen.connect(_on_card_chosen)


func _refresh_network_opponent(
	ui_index: int,
	seat: int,
	active_seat: int,
	phase: String,
	players: Array
) -> void:
	var player: Dictionary = players[seat]
	var marker := "  <" if phase == "passing" and seat == active_seat else ""
	_opponent_names[ui_index].text = String(player.get("name", "Player")) + marker
	_opponent_counts[ui_index].text = "CARDS  %d" % int(player.get("cardCount", 0))
	_opponent_scores[ui_index].text = "LETTERS  %s" % _score_text(int(player.get("letters", 0)))


func _render_network_result(players: Array, local_seat: int, phase: String) -> void:
	var result: Dictionary = _network_state.get("result", {})
	if result.is_empty():
		return
	var winner := int(result.get("winner", 0))
	var combo := String(result.get("combo", "four_of_a_kind"))
	var order_names: PackedStringArray = []
	for seat_value in result.get("slapOrder", []):
		order_names.append(String(players[int(seat_value)].get("name", "Player")))
	var penalty_names: PackedStringArray = []
	for seat_value in result.get("penalized", []):
		penalty_names.append(String(players[int(seat_value)].get("name", "Player")))
	result_title.text = _network_combo_title(combo)
	result_body.text = "%s completed the set.\n\nSlap order: %s\n\nLetters: %s\n%s" % [
		String(players[winner].get("name", "Player")),
		" > ".join(order_names),
		", ".join(penalty_names),
		_network_penalty_description(combo),
	]
	if phase == "game_over":
		var loser_names: PackedStringArray = []
		for player: Dictionary in players:
			if int(player.get("letters", 0)) >= GAME_WORD.length():
				loser_names.append(String(player.get("name", "Player")))
		result_body.text += "\n\n%s completed JOKER." % ", ".join(loser_names)
		next_round_button.text = "NEW GAME"
	else:
		next_round_button.text = "NEXT ROUND"
	result_overlay.show()
	if result.get("penalized", []).has(local_seat):
		audio_manager.play_letter()
	else:
		audio_manager.play_round_win()


func _play_network_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"card_passed":
			audio_manager.play_pass()
		"slap":
			animation_player.stop()
			animation_player.play("slap_flash")
			audio_manager.play_slap()


func _score_text(letters: int) -> String:
	return "—" if letters <= 0 else GAME_WORD.substr(0, mini(letters, GAME_WORD.length()))


func _mobile_instruction(message: String) -> String:
	if not JokerMobileUI.is_active():
		return message
	return (
		message.replace(" or press 1-5", "")
		.replace("click", "tap")
		.replace("Hit SPACE or SLAP", "Tap SLAP")
	)


func _network_combo_title(combo: String) -> String:
	match combo:
		"four_of_a_kind": return "Four of a kind"
		"three_with_joker": return "Three plus the Joker"
		"four_with_joker": return "Four of a kind plus the Joker"
		_: return "Round complete"


func _network_penalty_description(combo: String) -> String:
	match combo:
		"four_of_a_kind": return "The last player to slap takes a letter."
		"three_with_joker": return "The last two players to slap take a letter."
		"four_with_joker": return "Every player except the winner takes a letter."
		_: return ""

func _play_by_play() -> void:
	print("A card was passed.")
