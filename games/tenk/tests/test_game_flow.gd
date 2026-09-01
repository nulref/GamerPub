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
	assert(game._activity_log.get_parsed_text().contains("event=GAME_START"))
	assert(game._activity_log.get_parsed_text().contains("event=TURN_START"))

	game.turn_score = 950
	assert(not game._can_bank())
	game.turn_score = 0
	game.current_roll = [1, 2, 3, 4, 5, 6]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game._present_hand(false)
	var first_die := game._dice_row.get_child(0) as Button
	var idle_die_style := first_die.get_theme_stylebox("normal") as StyleBoxFlat
	var selected_die_style := first_die.get_theme_stylebox("pressed") as StyleBoxFlat
	assert(idle_die_style.border_width_left == 0)
	assert(idle_die_style.bg_color == Color.TRANSPARENT)
	assert(selected_die_style.border_width_left == 6)
	assert(selected_die_style.border_color == Color.WHITE)
	assert(game._selected_indices().is_empty())
	assert(game._roll_button.disabled)
	assert(game._keep_button.disabled)
	assert(game._turn_score_label.text == "TURN SCORE  0")
	game._show_hand_dice(PackedInt32Array([0]))
	game._update_selection_preview()
	assert(not game._roll_button.disabled)
	assert(game._keep_button.disabled)
	assert(game._turn_score_label.text == "TURN SCORE  100")
	game._show_hand_dice(PackedInt32Array([0, 1, 2, 3, 4, 5]))
	game._update_selection_preview()
	assert(not game._keep_button.disabled)
	game._reroll_unselected_dice()
	assert(game.turn_score == 1500)
	assert(game.dice_to_roll == 6)
	assert(game.hot_hand_ready)
	assert(game._roll_button.text == "REROLL ALL 6")
	assert(game._can_bank())
	assert(game._activity_log.get_parsed_text().contains("event=ROLL | dice=[1, 2, 3, 4, 5, 6]"))
	assert(game._activity_log.get_parsed_text().contains("event=ACTION | action=REROLL"))
	assert(game._activity_log.get_parsed_text().contains("points=1500"))
	game._on_keep_pressed()
	assert(game.players[0].score == 1500)
	assert(game.players[0].on_board)
	assert(not game.awaiting_next_player)
	assert(game.current_player == 1)
	assert(game.turn_score == 0)
	assert(game._turn_score_label.text == "TURN SCORE  0")
	assert(game._status_label.text.contains("Ada banked 1500 points"))
	assert(game._activity_log.get_parsed_text().contains("action=KEEP | selected=[] | points=0 | hand_points=0 | turn_points=1500"))
	assert(game._activity_log.get_parsed_text().contains("outcome=BANKED | points=1500"))
	assert(game._activity_log.get_parsed_text().contains("action=AUTO_NEXT_PLAYER"))

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
	assert(not game.awaiting_next_player)
	assert(game.current_player == 0)

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
	assert(not game.awaiting_next_player)
	assert(game.current_player == 1)
	assert(game._roll_button.text == "ROLL 6 DICE")
	assert(not game._roll_button.disabled)
	assert(game._status_label.text.contains("bust"))
	assert(game._activity_log.get_parsed_text().contains("outcome=BUST | points=0"))

	# At 9,000 or below, locking two 1s commits the player to completing
	# three 1s on the immediately following roll. Above 9,000 they remain
	# ordinary 100-point singles because a 1,000-point result would overshoot.
	game.players[1].score = 9000
	assert(game._is_forced_thousand_try([1, 1]))
	game.players[1].score = 9050
	assert(not game._is_forced_thousand_try([1, 1]))

	# An opening 1,000 is an immediate bust for a player already over 9,000.
	game.players[1].score = 9050
	game.turn_score = 0
	game.awaiting_next_player = false
	game.current_roll = [1, 1, 1, 2, 3, 4]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game._present_hand(true)
	assert(not game.awaiting_next_player)
	assert(game.current_player == 0)
	assert(game.players[1].score == 9050)
	assert(game._status_label.text.contains("opening roll scored 1,000"))
	game.current_player = 1
	game.players[1].score = 9000
	game.awaiting_next_player = false
	game.current_roll = [1, 1, 1, 2, 3, 4]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game._present_hand(true)
	assert(not game.awaiting_next_player)

	# A straight that would take the player over exactly 10,000 busts as soon
	# as it is rolled, then immediately starts the next player's turn.
	game.current_player = 1
	game.players[1].score = 9600
	game.current_roll = [1, 2, 3, 4, 5, 6]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game.turn_score = 0
	game.awaiting_next_player = false
	game._present_hand(true)
	assert(not game.awaiting_next_player)
	assert(game.current_player == 0)
	assert(game._status_label.text.contains("opening roll scored 1,500"))
	assert(game._dice_row.get_child_count() == 0)

	# Above 9,000, a pair of carried 1s and a later 1 remain three singles.
	game.current_player = 1
	game.players[1].score = 9600
	game.awaiting_next_player = false
	game.current_roll = [1, 1, 1, 6, 4, 2]
	game.locked_indices = PackedInt32Array([0, 1])
	game.locked_batches = [[1, 1]]
	game.go_for_used = false
	game._show_hand_dice(PackedInt32Array([2]))
	game._update_controls()
	assert(game._current_hand_score() == 300)
	assert(not game._roll_button.disabled)

	# A lone pair can be locked once as a qualifying three-of-a-kind attempt.
	game.players[1].score = 5450
	game.current_roll = [1, 5, 4, 6, 6, 5]
	game.locked_indices.clear()
	game.locked_batches.clear()
	game.go_for_used = false
	game._show_hand_dice(PackedInt32Array([3, 4]))
	game._update_controls()
	assert(not game._roll_button.disabled)

	# Two locked 5s plus a newly rolled triple of 5s must leave Reroll enabled.
	game.current_roll = [5, 5, 5, 4, 5, 5]
	game.locked_indices = PackedInt32Array([4, 5])
	game.locked_batches = [[5, 5]]
	game.go_for_used = false
	game._show_hand_dice(PackedInt32Array([0, 1, 2]))
	game._update_controls()
	assert(not game._roll_button.disabled)

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
	assert(game._selected_indices().is_empty())
	assert(game._roll_button.disabled)
	assert(game._keep_button.disabled)
	game._show_hand_dice(PackedInt32Array([0, 1]))
	game._update_selection_preview()
	assert(game._selected_indices().size() == 2)
	assert(game._selected_values()[0] == game._selected_values()[1])
	assert(game._roll_button.text == "REROLL")
	assert(not game._roll_button.disabled)
	assert(game._keep_button.disabled)

	# Browser-room snapshots replace local setup and enable only the active
	# player's device while keeping every table synchronized.
	game._online_mode = true
	game._web_bridge = game.get_node("/root/TenkWebBridge")
	game._web_bridge.set("context", {"currentUser": {"userId": "online-one", "name": "Online One"}})
	game._configure_online_setup()
	var online_room := {
		"phase": "waiting",
		"hostId": "online-one",
		"players": [
			{"id": "online-one", "name": "Online One", "ready": true, "connected": true},
			{"id": "online-two", "name": "Online Two", "ready": true, "connected": true},
		],
	}
	game._on_online_room_state(online_room)
	assert(game._ready_button.visible)
	assert(not game._start_button.disabled)
	var online_game := {
		"players": [
			{"id": "online-one", "name": "Online One", "score": 0, "onBoard": false, "connected": true},
			{"id": "online-two", "name": "Online Two", "score": 0, "onBoard": false, "connected": true},
		],
		"currentPlayer": 0,
		"turnScore": 0,
		"diceToRoll": 6,
		"currentRoll": [],
		"lockedIndices": [],
		"lockedBatches": [],
		"selectedIndices": [],
		"goForUsed": false,
		"rescueMode": false,
		"hotHandReady": false,
		"awaitingNextPlayer": false,
		"gameOver": false,
		"winnerId": null,
		"status": "Online One, roll all six dice.",
		"rollDetail": "Six dice are ready.",
		"selection": "Roll to begin.",
		"activity": ["Online One's turn"],
	}
	game._on_online_game_state(online_game)
	assert(not game._roll_button.disabled)
	online_game.currentPlayer = 1
	game._on_online_game_state(online_game)
	assert(game._roll_button.disabled)
	assert(game._keep_button.disabled)
	var sound_count := game._dice_audio.play_count
	online_game.currentPlayer = 0
	online_game.currentRoll = [1, 2, 3, 4, 5, 6]
	online_game.diceToRoll = 6
	online_game.rollNumber = 1
	game._on_online_game_state(online_game)
	assert(game._dice_audio.play_count == sound_count + 1)
	assert(game._selected_indices().is_empty())
	assert(game._roll_button.disabled)
	assert(game._keep_button.disabled)
	online_game.selectedIndices = [0, 4]
	online_game.displayTurnScore = 150
	online_game.selection = "2 selected • current hand score 150"
	game._on_online_game_state(online_game)
	assert(game._selected_indices() == PackedInt32Array([0, 4]))
	assert((game._dice_row.get_child(0) as Button).button_pressed)
	assert((game._dice_row.get_child(4) as Button).button_pressed)
	game._web_bridge.set("context", {"currentUser": {"userId": "online-two", "name": "Online Two"}})
	game._on_online_game_state(online_game)
	assert((game._dice_row.get_child(0) as Button).disabled)
	assert((game._dice_row.get_child(0) as Button).button_pressed)
	assert(game._turn_score_label.text == "TURN SCORE  150")
	game._web_bridge.set("context", {"currentUser": {"userId": "online-one", "name": "Online One"}})
	game._on_online_game_state(online_game)
	assert(game._dice_audio.play_count == sound_count + 1)
	game._online_mode = false

	# Portrait layouts stack the scoreboard above the table, hide Table Talk,
	# enlarge touch targets, and reserve space above mobile host overlays.
	root.size = Vector2i(900, 1600)
	await process_frame
	await process_frame
	game._apply_responsive_layout()
	assert(game._portrait_layout)
	assert(game._body.columns == 1)
	assert(game._score_list.columns == 2)
	assert(not game._activity_panel.visible)
	assert(not game._footer_label.visible)
	assert(game._screen_margin.get_theme_constant("margin_bottom") == 500)
	assert(game._roll_button.custom_minimum_size.y == 208)
	assert(game._roll_button.get_theme_font_size("font_size") == 56)
	for die in game._dice_row.get_children():
		assert((die as Button).custom_minimum_size == Vector2(170, 170))
	root.size = Vector2i(1600, 900)
	await process_frame
	game._apply_responsive_layout()
	assert(not game._portrait_layout)
	assert(game._roll_button.custom_minimum_size.y == 58)
	assert(game._roll_button.get_theme_font_size("font_size") == 16)

	# Winning requires exactly 10,000. Overshooting busts the entire turn and
	# leaves the player's banked score where it was at the start of the turn.
	game.current_player = 0
	game.players[0].score = 9500
	game.players[0].on_board = true
	game.game_over = false
	game.awaiting_next_player = false
	game.turn_score = 550
	game.current_roll.clear()
	game.locked_indices.clear()
	game.locked_batches.clear()
	game._finish_scoring_turn("Kept it")
	assert(game.players[0].score == 9500)
	assert(game.turn_score == 0)
	assert(not game.awaiting_next_player)
	assert(game.current_player == 1)
	assert(not game.game_over)
	assert(game._status_label.text.contains("over exactly 10,000"))
	assert(game._activity_log.get_parsed_text().contains("outcome=BUST | points=0 | points_lost=550"))

	game.current_player = 0
	game.awaiting_next_player = false
	game.turn_score = 500
	game._finish_scoring_turn("Kept it")
	assert(game.players[0].score == 10_000)
	assert(game.game_over)

	assert(game.find_child("BackToLauncherButton", true, false) != null)
	assert(game.find_child("RulesOverlay", true, false) != null)
	print("PASS: 10,000 game scene and opening-score flow")
	game._dice_audio.stop()
	game._dice_audio.stream = null
	game._dice_audio._roll_stream = null
	game.queue_free()
	current_scene = null
	await process_frame
	quit()
