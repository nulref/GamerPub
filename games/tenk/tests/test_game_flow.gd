extends SceneTree
## Smoke-checks setup, opening-score eligibility, and scene construction.

const GAME_SCENE := preload("res://games/tenk/scenes/game.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := GAME_SCENE.instantiate() as TenkGame
	root.add_child(game)
	current_scene = game
	await process_frame

	assert(game.players.is_empty())
	assert(game.get_node("SetupOverlay").visible)
	game._name_edits[0].text = "Ada"
	game._name_edits[1].text = "Lin"
	game._start_game()
	await process_frame
	assert(not game.get_node("SetupOverlay").visible)
	assert(game.players.size() == 2)
	assert(game.players[0].name == "Ada")
	assert(game._roll_button.get_parent().get_child_count() == 2)

	game.turn_score = 950
	assert(not game._can_bank())
	game.turn_score = 0
	game.current_roll = [1, 2, 3, 4, 5, 6]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game._show_hand_dice(PackedInt32Array([0, 1, 2, 3, 4, 5]))
	game._reroll_unselected_dice()
	assert(game.turn_score == 1500)
	assert(game.dice_to_roll == 6)
	assert(game.hot_hand_ready)
	assert(game._roll_button.text == "REROLL ALL 6")
	assert(game._can_bank())
	game._on_keep_pressed()
	assert(game.players[0].score == 1500)
	assert(game.players[0].on_board)
	assert(game.awaiting_next_player)
	assert(game.turn_score == 1500)
	assert(game._turn_score_label.text == "BANKED THIS TURN  1,500")

	game._on_keep_pressed()
	assert(game.current_player == 1)
	assert(game.turn_score == 0)
	game.players[1].score = 1400
	game.players[1].on_board = true
	game.current_player = 1
	game.turn_score = 50
	assert(game._can_bank())
	game.current_roll = [5, 2, 3, 4, 6, 2]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game.hot_hand_ready = false
	game._show_hand_dice(PackedInt32Array([0]))
	game._update_controls()
	assert(not game._keep_button.disabled)
	game._on_keep_pressed()
	assert(game.players[1].score == 1500)
	assert(game.awaiting_next_player)

	# Ordinary scoring rerolls can repeat until all six dice have scored.
	game.turn_score = 0
	game.dice_to_roll = 6
	game.go_for_used = false
	game.awaiting_next_player = false
	game.rescue_mode = false
	game.hot_hand_ready = false
	game.locked_indices.clear()
	game.locked_batches.clear()
	game.current_roll = [4, 6, 4, 2, 4, 4]
	game._show_hand_dice(PackedInt32Array([0, 2, 4, 5]))
	game._update_selection_preview()
	assert(game._roll_button.text == "REROLL")
	assert(not game._roll_button.disabled)
	game.locked_indices = PackedInt32Array([0, 2, 4, 5])
	game.locked_batches = [[4, 4, 4, 4]]
	game.current_roll[1] = 3
	game.current_roll[3] = 5
	game._show_hand_dice(PackedInt32Array([3]))
	assert((game._dice_row.get_child(0) as Button).disabled)
	assert(not (game._dice_row.get_child(1) as Button).disabled)
	assert(game._current_hand_score() == 850)
	game.locked_indices.append(3)
	game.locked_indices.sort()
	game.locked_batches.append([5])
	game.current_roll[1] = 1
	game._show_hand_dice(PackedInt32Array([1]))
	assert(game._current_hand_score() == 950)
	game._reroll_unselected_dice()
	assert(game.turn_score == 950)
	assert(game.dice_to_roll == 6)
	assert(game.hot_hand_ready)
	assert(game.locked_indices.size() == 6)
	assert(game._status_label.text.contains("AND ROLLING!"))
	for die in game._dice_row.get_children():
		assert((die as Button).disabled)

	# Matching dice from separate rerolls remain singles unless a carried pair
	# is completed by one matching die on a later roll.
	game.turn_score = 400
	game.dice_to_roll = 4
	game.awaiting_next_player = false
	game.hot_hand_ready = false
	game.rescue_mode = false
	game.current_roll = [1, 1, 5, 6, 1, 2]
	game.locked_indices = PackedInt32Array([2, 4])
	game.locked_batches = [[1, 5]]
	game._show_hand_dice(PackedInt32Array([0, 1]))
	game._update_selection_preview()
	assert(game._current_hand_score() == 350)
	assert(game._turn_score_label.text == "TURN SCORE  750")

	game.current_roll = [1, 5, 1, 6, 1, 3]
	game.locked_indices = PackedInt32Array([0, 2])
	game.locked_batches = [[1, 1]]
	game._show_hand_dice(PackedInt32Array([4]))
	assert(game._current_hand_score() == 1000)

	game.turn_score = 0
	game.current_roll = [1, 1, 1, 1, 5, 6]
	game.locked_indices = PackedInt32Array([2, 3, 4])
	game.locked_batches = [[1, 1], [5]]
	game._show_hand_dice(PackedInt32Array([0, 1]))
	game._update_selection_preview()
	assert(game._current_hand_score() == 450)
	assert(game._turn_score_label.text == "TURN SCORE  450")

	# A scoring final die still busts when it fails to finish a locked partial
	# combination, instead of leaving the turn with both actions disabled.
	game.turn_score = 0
	game.dice_to_roll = 1
	game.awaiting_next_player = false
	game.hot_hand_ready = false
	game.rescue_mode = false
	game.current_roll = [1, 2, 6, 3, 5, 1]
	game.locked_indices = PackedInt32Array([0, 1, 2, 3, 4])
	game.locked_batches = [[1, 2, 6, 3, 5]]
	assert(game._best_lock_candidate().is_empty())
	game.current_roll[5] = 4
	assert(game._best_lock_candidate() == PackedInt32Array([5]))
	game.current_roll[5] = 1
	game._present_hand(false)
	assert(game.awaiting_next_player)
	assert(game._keep_button.text == "NEXT PLAYER")
	assert(not game._keep_button.disabled)
	assert(game._status_label.text.contains("bust"))

	# The player-directed one-time reroll remains available as a no-score rescue.
	game.turn_score = 0
	game.dice_to_roll = 6
	game.current_roll = [2, 2, 3, 3, 4, 6]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game.go_for_used = false
	game.awaiting_next_player = false
	game.hot_hand_ready = false
	game._present_hand(true)
	assert(game.rescue_mode)
	assert(game._selected_indices().size() == 4)
	assert(game._roll_button.text == "REROLL")
	assert(not game._roll_button.disabled)

	assert(game.find_child("BackToLauncherButton", true, false) != null)
	assert(game.find_child("RulesOverlay", true, false) != null)
	print("PASS: 10,000 game scene and opening-score flow")
	game.queue_free()
	current_scene = null
	await process_frame
	quit()
