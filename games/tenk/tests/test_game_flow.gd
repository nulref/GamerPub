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

	game.turn_score = 950
	assert(not game._can_bank())
	game.turn_score = 0
	game.current_roll = [1, 2, 3, 4, 5, 6]
	game._show_dice(game.current_roll, true, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	game._on_set_aside_pressed()
	assert(game.turn_score == 1500)
	assert(game.dice_to_roll == 6)
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
	game._show_dice(game.current_roll, true, PackedInt32Array([0]))
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
	game.awaiting_go_for_choice = false
	game.current_roll = [4, 6, 4, 2, 4, 4]
	game._show_dice(game.current_roll, true, PackedInt32Array([0, 2, 4, 5]))
	game._show_scoring_reroll_option()
	assert(game._go_for_label.text == "Score the selected dice and reroll every unselected die:")
	assert((game._go_for_buttons.get_child(0) as Button).text == "REROLL 2 DICE")
	game._on_set_aside_pressed()
	assert(game.turn_score == 800)
	assert(game.dice_to_roll == 2)
	assert(not game.go_for_used)
	game.current_roll = [3, 5]
	game._show_dice(game.current_roll, true, PackedInt32Array([1]))
	game._on_set_aside_pressed()
	assert(game.turn_score == 850)
	assert(game.dice_to_roll == 1)
	game.current_roll = [1]
	game._show_dice(game.current_roll, true, PackedInt32Array([0]))
	game._on_set_aside_pressed()
	assert(game.turn_score == 950)
	assert(game.dice_to_roll == 6)
	assert(game.current_roll.is_empty())
	assert(game._status_label.text.begins_with("AND ROLLING!"))

	# The player-directed one-time reroll remains available as a no-score rescue.
	game.turn_score = 0
	game.dice_to_roll = 6
	game.current_roll = [2, 4, 3, 4, 6, 2]
	game.go_for_used = false
	game.awaiting_next_player = false
	game.awaiting_go_for_choice = false
	game._show_dice(game.current_roll, true, PackedInt32Array([0, 2, 3, 4, 5]))
	game.awaiting_go_for_choice = true
	game._show_rescue_reroll_option()
	game._choose_selected_reroll()
	assert(game.go_for_used)
	assert(game.pending_go_for_plan.reroll_count == 1)
	assert(game._dice_row.get_child_count() == 5)
	assert(game._roll_button.text == "ROLL 1 DIE")
	assert(not game._can_offer_rescue_reroll())

	assert(game.find_child("BackToLauncherButton", true, false) != null)
	assert(game.find_child("RulesOverlay", true, false) != null)
	print("PASS: 10,000 game scene and opening-score flow")
	game.queue_free()
	current_scene = null
	await process_frame
	quit()
