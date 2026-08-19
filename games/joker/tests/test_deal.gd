extends SceneTree
## A small integration check for the Node-based match controller.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := JokerGameController.new()
	root.add_child(game)
	await process_frame
	game.start_game()

	var total_cards := 0
	var five_card_hands := 0
	for player in game.players:
		total_cards += player.hand.size()
		if player.hand.size() == 5:
			five_card_hands += 1

	assert(game.players.size() == 4)
	assert(total_cards == 17)
	assert(five_card_hands == 1)
	assert(game.players[game.active_player].hand.size() == 5)
	print("PASS: deal contains 17 cards and one active five-card hand")
	quit()
