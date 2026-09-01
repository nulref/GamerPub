extends SceneTree

const MATCH := preload("res://games/cribbage/scripts/cribbage_match.gd")


func _init() -> void:
	for config in [
		["standard", 2], ["standard", 3], ["standard", 4],
		["partnership", 2], ["partnership", 4],
		["variant", 5], ["variant", 6],
	]:
		_run_deal(String(config[0]), int(config[1]))
	print("PASS: every Cribbage table deals, pegs, and counts")
	quit()


func _run_deal(mode: String, player_count: int) -> void:
	var game_match = MATCH.new(12345 + player_count)
	var names: Array[String] = []
	var bots: Array[bool] = []
	for index in player_count:
		names.append("Player %d" % (index + 1))
		bots.append(true)
	game_match.start(mode, names, bots)
	for player in player_count:
		if not game_match.discarded[player]:
			assert(game_match.discard_cards(player, game_match.bot_discard_indices(player)))
	assert(game_match.phase == "pegging")
	assert(game_match.crib.size() == 4)
	for hand in game_match.hands:
		assert(hand.size() == 4)
	assert(not game_match.starter.is_empty())
	var safety := 0
	while game_match.phase == "pegging" and safety < 100:
		var player: int = game_match.active_player
		var legal: Array[int] = game_match.legal_card_indices(player)
		assert(not legal.is_empty())
		assert(game_match.play_card(player, legal[0]))
		safety += 1
	assert(safety < 100)
	assert(game_match.phase == "show" or game_match.phase == "game_over")
	if game_match.phase == "show":
		assert(game_match.show_items.size() == player_count + 1)
