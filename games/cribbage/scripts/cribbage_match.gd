class_name CribbageMatch
extends RefCounted
## Authoritative local Cribbage match state. The browser server mirrors these rules.

const RULES := preload("res://games/cribbage/scripts/cribbage_rules.gd")

var mode := "standard"
var player_count := 2
var players: Array[Dictionary] = []
var team_scores: Dictionary = {}
var dealer := 0
var active_player := -1
var phase := "setup"
var hands: Array = []
var kept_hands: Array = []
var crib: Array = []
var starter: Dictionary = {}
var required_discards: Array[int] = []
var discarded: Array[bool] = []
var peg_sequence: Array = []
var peg_total := 0
var last_pegger := -1
var play_history: Array[Dictionary] = []
var show_items: Array[Dictionary] = []
var status := ""
var winner_team := -1
var deal_number := 0
var revision := 0
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


func start(match_mode: String, names: Array[String], bot_flags: Array[bool] = []) -> void:
	assert(RULES.is_valid_config(match_mode, names.size()))
	mode = match_mode
	player_count = names.size()
	players.clear()
	team_scores.clear()
	for index in player_count:
		var team := RULES.team_for_player(mode, player_count, index)
		players.append({
			"id": "player_%d" % index,
			"name": names[index],
			"team": team,
			"is_bot": bool(bot_flags[index]) if index < bot_flags.size() else false,
			"connected": true,
		})
		team_scores[team] = 0
	dealer = _rng.randi_range(0, player_count - 1)
	winner_team = -1
	deal_number = 0
	_deal()


func discard_cards(player_index: int, indices: Array[int]) -> bool:
	if phase != "discarding" or player_index < 0 or player_index >= player_count:
		return false
	if discarded[player_index] or indices.size() != required_discards[player_index]:
		return false
	var unique := indices.duplicate()
	unique.sort()
	for index in range(1, unique.size()):
		if unique[index] == unique[index - 1]:
			return false
	for index in unique:
		if index < 0 or index >= hands[player_index].size():
			return false
	unique.reverse()
	for index in unique:
		crib.append(hands[player_index].pop_at(index))
	discarded[player_index] = true
	status = "%s is ready for the cut." % players[player_index].name
	_touch()
	if _all_discarded():
		_start_pegging()
	return true


func play_card(player_index: int, hand_index: int) -> bool:
	if phase != "pegging" or player_index != active_player:
		return false
	if hand_index < 0 or hand_index >= hands[player_index].size():
		return false
	var card: Dictionary = hands[player_index][hand_index]
	if RULES.card_value(card) + peg_total > 31:
		return false
	hands[player_index].remove_at(hand_index)
	peg_sequence.append(card)
	peg_total += RULES.card_value(card)
	last_pegger = player_index
	var pegging := RULES.score_pegging(peg_sequence, peg_total)
	var points := int(pegging.total)
	play_history.append({
		"player": player_index,
		"card": card.duplicate(true),
		"count": peg_total,
		"points": points,
	})
	if points > 0 and _award_points(int(players[player_index].team), points):
		return true
	if _all_hands_empty():
		if peg_total != 31 and _award_points(int(players[player_index].team), 1):
			return true
		_finish_pegging()
		return true
	if peg_total == 31:
		_reset_peg_sequence()
		active_player = _next_player_with_cards(player_index)
	else:
		var next := _next_legal_player(player_index)
		if next < 0:
			if _award_points(int(players[player_index].team), 1):
				return true
			_reset_peg_sequence()
			active_player = _next_player_with_cards(player_index)
		else:
			active_player = next
	if active_player >= 0:
		status = "%s to play — count is %d." % [players[active_player].name, peg_total]
	_touch()
	return true


func continue_after_show() -> bool:
	if phase != "show":
		return false
	dealer = (dealer + 1) % player_count
	_deal()
	return true


func legal_card_indices(player_index: int) -> Array[int]:
	var legal: Array[int] = []
	if player_index < 0 or player_index >= hands.size():
		return legal
	for index in hands[player_index].size():
		if RULES.card_value(hands[player_index][index]) + peg_total <= 31:
			legal.append(index)
	return legal


func bot_discard_indices(player_index: int) -> Array[int]:
	var needed := required_discards[player_index]
	if needed == 0:
		return []
	var combinations: Array = _index_combinations(hands[player_index].size(), needed)
	var best: Array[int] = combinations[0]
	var best_value := -INF
	var owns_crib := int(players[player_index].team) == int(players[dealer].team)
	for raw_combo in combinations:
		var combo: Array[int] = raw_combo
		var remaining: Array = []
		var thrown: Array = []
		for index in hands[player_index].size():
			if combo.has(index): thrown.append(hands[player_index][index])
			else: remaining.append(hands[player_index][index])
		var starter_total := 0.0
		var starter_count := 0
		for candidate in RULES.make_deck():
			var already_held := false
			for held in hands[player_index]:
				if held.id == candidate.id:
					already_held = true
					break
			if already_held:
				continue
			starter_total += int(RULES.score_hand(remaining, candidate, false).total)
			starter_count += 1
		var value := starter_total / maxf(starter_count, 1)
		var crib_weight := 0.0
		for card in thrown:
			crib_weight += RULES.card_value(card) * 0.16
		value += crib_weight if owns_crib else -crib_weight
		if value > best_value:
			best_value = value
			best = combo.duplicate()
	return best


func bot_play_index(player_index: int) -> int:
	var legal := legal_card_indices(player_index)
	if legal.is_empty():
		return -1
	var best := legal[0]
	var best_value := -INF
	for index in legal:
		var card: Dictionary = hands[player_index][index]
		var next_sequence := peg_sequence.duplicate(true)
		next_sequence.append(card)
		var next_total := peg_total + RULES.card_value(card)
		var immediate := int(RULES.score_pegging(next_sequence, next_total).total)
		var value := immediate * 100.0 + RULES.card_value(card)
		if next_total == 5 or next_total == 21:
			value -= 24.0
		if value > best_value:
			best_value = value
			best = index
	return best


func score_for_player(player_index: int) -> int:
	return int(team_scores.get(int(players[player_index].team), 0))


func _deal() -> void:
	deal_number += 1
	phase = "discarding"
	hands.clear()
	kept_hands.clear()
	crib.clear()
	starter.clear()
	peg_sequence.clear()
	play_history.clear()
	show_items.clear()
	peg_total = 0
	last_pegger = -1
	active_player = -1
	var plan := RULES.deal_plan(mode, player_count, dealer)
	required_discards = plan.discards.duplicate()
	discarded.clear()
	for index in player_count:
		hands.append([])
		kept_hands.append([])
		discarded.append(required_discards[index] == 0)
	var deck := RULES.make_deck()
	_shuffle(deck)
	var dealt: Array = plan.dealt
	var remaining := 0
	for count in dealt:
		remaining += int(count)
	var seat := (dealer + 1) % player_count
	while remaining > 0:
		if hands[seat].size() < int(dealt[seat]):
			hands[seat].append(deck.pop_back())
			remaining -= 1
		seat = (seat + 1) % player_count
	for _extra in int(plan.crib_extra):
		crib.append(deck.pop_back())
	# Keep the undealt deck only long enough to cut after everyone discards.
	set_meta("cut_deck", deck)
	status = "%s deals. Choose %d card%s for the crib." % [
		players[dealer].name,
		required_discards[0],
		"" if required_discards[0] == 1 else "s",
	]
	_touch()
	if _all_discarded():
		_start_pegging()


func _start_pegging() -> void:
	for index in player_count:
		kept_hands[index] = hands[index].duplicate(true)
	var deck: Array = get_meta("cut_deck", [])
	starter = deck.pop_back() if not deck.is_empty() else {}
	remove_meta("cut_deck")
	if int(starter.get("rank", 0)) == 11:
		if _award_points(int(players[dealer].team), 2):
			return
	phase = "pegging"
	active_player = _next_player_with_cards(dealer)
	status = "%s leads. Count starts at zero." % players[active_player].name
	_touch()


func _finish_pegging() -> void:
	phase = "show"
	show_items.clear()
	for offset in range(1, player_count + 1):
		var player_index := (dealer + offset) % player_count
		var score := RULES.score_hand(kept_hands[player_index], starter, false)
		show_items.append({
			"kind": "hand",
			"player": player_index,
			"name": players[player_index].name,
			"cards": kept_hands[player_index].duplicate(true),
			"points": int(score.total),
			"detail": score.detail,
		})
		if int(score.total) > 0 and _award_points(int(players[player_index].team), int(score.total)):
			return
	var crib_score := RULES.score_hand(crib, starter, true)
	show_items.append({
		"kind": "crib",
		"player": dealer,
		"name": "%s's crib" % players[dealer].name,
		"cards": crib.duplicate(true),
		"points": int(crib_score.total),
		"detail": crib_score.detail,
	})
	if int(crib_score.total) > 0 and _award_points(int(players[dealer].team), int(crib_score.total)):
		return
	status = "Hands counted. %s deals next." % players[(dealer + 1) % player_count].name
	_touch()


func _award_points(team: int, points: int) -> bool:
	team_scores[team] = int(team_scores.get(team, 0)) + points
	if int(team_scores[team]) >= RULES.WINNING_SCORE:
		winner_team = team
		phase = "game_over"
		status = "%s wins with %d points!" % [_team_name(team), int(team_scores[team])]
		_touch()
		return true
	return false


func _team_name(team: int) -> String:
	var names: Array[String] = []
	for player in players:
		if int(player.team) == team:
			names.append(String(player.name))
	return " & ".join(names)


func _all_discarded() -> bool:
	for ready in discarded:
		if not ready:
			return false
	return true


func _all_hands_empty() -> bool:
	for hand in hands:
		if not hand.is_empty():
			return false
	return true


func _next_player_with_cards(after_player: int) -> int:
	for offset in range(1, player_count + 1):
		var candidate := (after_player + offset) % player_count
		if not hands[candidate].is_empty():
			return candidate
	return -1


func _next_legal_player(after_player: int) -> int:
	for offset in range(1, player_count + 1):
		var candidate := (after_player + offset) % player_count
		if not legal_card_indices(candidate).is_empty():
			return candidate
	return -1


func _reset_peg_sequence() -> void:
	peg_sequence.clear()
	peg_total = 0
	last_pegger = -1


func _shuffle(deck: Array) -> void:
	for index in range(deck.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temporary = deck[index]
		deck[index] = deck[other]
		deck[other] = temporary


func _index_combinations(size: int, choose: int) -> Array:
	var results: Array = []
	_build_combinations(results, [], 0, size, choose)
	return results


func _build_combinations(results: Array, current: Array[int], start: int, size: int, choose: int) -> void:
	if current.size() == choose:
		results.append(current.duplicate())
		return
	for index in range(start, size):
		current.append(index)
		_build_combinations(results, current, index + 1, size, choose)
		current.pop_back()


func _touch() -> void:
	revision += 1
