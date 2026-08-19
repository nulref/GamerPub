class_name JokerGameController
extends Node
## Owns the match. The UI only sends commands and listens to signals.

signal round_started(round_number: int, starting_player: int)
signal hand_changed(player_index: int)
signal active_player_changed(player_index: int)
signal status_changed(message: String)
signal card_passed(from_player: int, to_player: int)
signal slap_registered(player_index: int, place: int)
signal round_ended(result: Dictionary)
signal scores_changed
signal game_finished(losers: Array[int])

enum Phase {
	SETUP,
	PASSING,
	SLAPPING,
	ROUND_RESULT,
	GAME_OVER,
}

const RANKS: Array[JokerCardDefinition] = [
	preload("res://games/joker/resources/ranks/spade_ace.tres"),
	preload("res://games/joker/resources/ranks/spade_two.tres"),
	preload("res://games/joker/resources/ranks/spade_three.tres"),
	preload("res://games/joker/resources/ranks/spade_four.tres"),
	preload("res://games/joker/resources/ranks/heart_ace.tres"),
	preload("res://games/joker/resources/ranks/heart_two.tres"),
	preload("res://games/joker/resources/ranks/heart_three.tres"),
	preload("res://games/joker/resources/ranks/heart_four.tres"),
	preload("res://games/joker/resources/ranks/club_ace.tres"),
	preload("res://games/joker/resources/ranks/club_two.tres"),
	preload("res://games/joker/resources/ranks/club_three.tres"),
	preload("res://games/joker/resources/ranks/club_four.tres"),
	preload("res://games/joker/resources/ranks/diamond_ace.tres"),
	preload("res://games/joker/resources/ranks/diamond_two.tres"),
	preload("res://games/joker/resources/ranks/diamond_three.tres"),
	preload("res://games/joker/resources/ranks/diamond_four.tres"),
]
const JOKER: JokerCardDefinition = preload("res://games/joker/resources/ranks/joker.tres")

var players: Array[JokerPlayerState] = []
var phase: Phase = Phase.SETUP
var active_player: int = 0
var round_number: int = 0
var bot_speed_scale: float = 1.0

var _rng := RandomNumberGenerator.new()
var _round_token: int = 0
var _winning_player: int = -1
var _winning_combo: JokerGameRules.Combo = JokerGameRules.Combo.NONE
var _slap_order: Array[int] = []


func _ready() -> void:
	_rng.randomize()
	players = [
		JokerPlayerState.new("You"),
		JokerPlayerState.new("Kramer"),
		JokerPlayerState.new("George"),
		JokerPlayerState.new("Elaine"),
	]


func start_game() -> void:
	for player in players:
		player.reset_for_game()
	round_number = 0
	scores_changed.emit()
	_start_round()


func start_next_round() -> void:
	if phase == Phase.ROUND_RESULT:
		_start_round()


func pass_card(card_index: int) -> void:
	if phase != Phase.PASSING or active_player != 0:
		return
	if card_index < 0 or card_index >= players[0].hand.size():
		return
	_transfer_card(0, card_index)


func request_human_slap() -> void:
	if phase == Phase.PASSING:
		var combo := JokerGameRules.evaluate_hand(players[0].hand)
		if combo == JokerGameRules.Combo.NONE:
			status_changed.emit("No complete set yet — keep passing.")
			return
		_begin_slap(0, combo)
	elif phase == Phase.SLAPPING and not _slap_order.has(0):
		_register_slap(0)


func human_can_pass() -> bool:
	return phase == Phase.PASSING and active_player == 0


func human_has_slapped() -> bool:
	return _slap_order.has(0)


func _start_round() -> void:
	_round_token += 1
	round_number += 1
	phase = Phase.SETUP
	_winning_player = -1
	_winning_combo = JokerGameRules.Combo.NONE
	_slap_order.clear()

	for player in players:
		player.hand.clear()

	var deck: Array[JokerCardDefinition] = []
	for definition in RANKS:
		deck.append(definition)
	deck.append(JOKER)
	_shuffle(deck)

	active_player = _rng.randi_range(0, players.size() - 1)
	for player_index in players.size():
		for card_number in 4:
			players[player_index].hand.append(deck.pop_back())
	players[active_player].hand.append(deck.pop_back())

	phase = Phase.PASSING
	round_started.emit(round_number, active_player)
	for player_index in players.size():
		hand_changed.emit(player_index)
	active_player_changed.emit(active_player)
	status_changed.emit(_turn_message())
	queue_next_turn()


func queue_next_turn() -> void:
	var token := _round_token
	await get_tree().create_timer(0.22).timeout
	if token != _round_token or phase != Phase.PASSING:
		return

	var completed_player := _find_completed_player()
	if completed_player >= 0:
		if completed_player == 0:
			status_changed.emit("You have %s — SLAP!" % JokerGameRules.combo_title(
				JokerGameRules.evaluate_hand(players[0].hand)
			))
		else:
			_schedule_bot_discovery(completed_player, token)
		return

	if active_player == 0:
		status_changed.emit("Your turn — click a card or press 1-5 to pass it right.")
		return

	await get_tree().create_timer(_rng.randf_range(0.42, 0.82) / bot_speed_scale).timeout
	if token != _round_token or phase != Phase.PASSING or active_player == 0:
		return
	_transfer_card(active_player, _choose_bot_card(active_player))


func _transfer_card(from_player: int, card_index: int) -> void:
	var to_player := (from_player + 1) % players.size()
	var card: JokerCardDefinition = players[from_player].hand.pop_at(card_index)
	players[to_player].hand.append(card)
	hand_changed.emit(from_player)
	hand_changed.emit(to_player)
	card_passed.emit(from_player, to_player)
	active_player = to_player
	active_player_changed.emit(active_player)
	status_changed.emit(_turn_message())
	queue_next_turn()


func _choose_bot_card(player_index: int) -> int:
	var hand := players[player_index].hand
	var counts: Dictionary = {}
	for card in hand:
		if not card.is_joker:
			counts[card.id] = counts.get(card.id, 0) + 1

	var choices: Array[int] = []
	var smallest_group := 99
	for index in hand.size():
		var card := hand[index]
		if card.is_joker:
			continue
		var group_size: int = counts[card.id]
		if group_size < smallest_group:
			smallest_group = group_size
			choices = [index]
		elif group_size == smallest_group:
			choices.append(index)

	if choices.is_empty():
		return 0
	return choices[_rng.randi_range(0, choices.size() - 1)]


func _find_completed_player() -> int:
	# Check the current player first: they are the person who just received a card.
	for offset in players.size():
		var player_index := (active_player + offset) % players.size()
		if JokerGameRules.evaluate_hand(players[player_index].hand) != JokerGameRules.Combo.NONE:
			return player_index
	return -1


func _schedule_bot_discovery(player_index: int, token: int) -> void:
	status_changed.emit("Watch the table…")
	await get_tree().create_timer(_rng.randf_range(0.32, 0.72) / bot_speed_scale).timeout
	if token != _round_token or phase != Phase.PASSING:
		return
	var combo := JokerGameRules.evaluate_hand(players[player_index].hand)
	if combo != JokerGameRules.Combo.NONE:
		_begin_slap(player_index, combo)
	else:
		queue_next_turn()


func _begin_slap(player_index: int, combo: JokerGameRules.Combo) -> void:
	if phase != Phase.PASSING:
		return
	phase = Phase.SLAPPING
	_winning_player = player_index
	_winning_combo = combo
	status_changed.emit("%s slapped! Hit SPACE or SLAP now!" % players[player_index].display_name)
	_register_slap(player_index)

	var token := _round_token
	for bot_index in range(1, players.size()):
		if bot_index == player_index:
			continue
		_schedule_bot_slap(bot_index, _rng.randf_range(0.30, 1.25) / bot_speed_scale, token)
	_schedule_human_timeout(token)


func _schedule_bot_slap(player_index: int, delay: float, token: int) -> void:
	await get_tree().create_timer(delay).timeout
	if token == _round_token and phase == Phase.SLAPPING and not _slap_order.has(player_index):
		_register_slap(player_index)


func _schedule_human_timeout(token: int) -> void:
	await get_tree().create_timer(3.25 / bot_speed_scale).timeout
	if token == _round_token and phase == Phase.SLAPPING and not _slap_order.has(0):
		status_changed.emit("Too slow — you slapped last.")
		_register_slap(0)


func _register_slap(player_index: int) -> void:
	if _slap_order.has(player_index) or phase != Phase.SLAPPING:
		return
	_slap_order.append(player_index)
	slap_registered.emit(player_index, _slap_order.size())
	if _slap_order.size() == players.size():
		_finish_round_after_beat(_round_token)


func _finish_round_after_beat(token: int) -> void:
	await get_tree().create_timer(0.48).timeout
	if token != _round_token or phase != Phase.SLAPPING:
		return
	_resolve_round()


func _resolve_round() -> void:
	var penalized := JokerGameRules.penalized_players(
		_winning_combo,
		_winning_player,
		_slap_order,
		players.size()
	)

	for player_index in penalized:
		players[player_index].add_letter()
	scores_changed.emit()

	var result := {
		"winner": _winning_player,
		"combo": _winning_combo,
		"slap_order": _slap_order.duplicate(),
		"penalized": penalized,
	}
	phase = Phase.ROUND_RESULT
	round_ended.emit(result)

	var losers: Array[int] = []
	for player_index in players.size():
		if players[player_index].is_out():
			losers.append(player_index)
	if not losers.is_empty():
		phase = Phase.GAME_OVER
		game_finished.emit(losers)


func _shuffle(cards: Array[JokerCardDefinition]) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temporary := cards[index]
		cards[index] = cards[other]
		cards[other] = temporary


func _turn_message() -> String:
	if active_player == 0:
		return "Your turn — click a card or press 1-5 to pass it right."
	return "%s is choosing a card…" % players[active_player].display_name
