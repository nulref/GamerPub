extends SceneTree
## Smoke-checks setup, legal-key play, scoring, timeouts, and layout.

const GAME_SCENE := preload("res://games/sesquip/scenes/game.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Variant = GAME_SCENE.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame

	assert(game.get_node("SetupOverlay").visible)
	assert(game.lexicon.word_count > 500)
	assert(game.lexicon.is_terminal_word("SESQUIPEDALIAN"))
	game.start_game(PackedStringArray(["Ada", "Lin"]))
	assert(game.players.size() == 2)
	assert(game.current_player == 0)
	assert(game.round_active)
	assert(game.play_letter("Z"))
	assert(game.current_sequence == "Z")
	assert(game.current_player == 1)
	assert(not game.play_letter("Q"))
	assert(game.play_letter("E"))
	assert(game.play_letter("B"))
	assert(game.play_letter("R"))
	assert(game.play_letter("A"))
	assert(not game.round_active)
	assert(game.current_sequence == "ZEBRA")
	assert(game.players[0].score == 5)
	assert(game.get_node("RoundOverlay").visible)

	game._begin_next_round()
	assert(game.current_player == 1)
	game._on_turn_timeout()
	assert(game.current_player == 0)
	assert(game.consecutive_timeouts == 1)
	game._on_turn_timeout()
	assert(not game.round_active)
	assert(game._round_title.text == "ROUND ABANDONED")

	root.size = Vector2i(900, 1600)
	await process_frame
	await process_frame
	game._apply_responsive_layout()
	assert(game._portrait_layout)
	assert(game._body.columns == 1)
	assert((game._letter_buttons["Q"] as Button).custom_minimum_size == Vector2(72, 72))
	root.size = Vector2i(1600, 900)
	await process_frame
	game._apply_responsive_layout()
	assert(not game._portrait_layout)
	assert(game._body.columns == 3)

	assert(game.find_child("BackToLauncherButton", true, false) != null)
	assert(game.find_child("RulesOverlay", true, false) != null)
	print("PASS: Sesquip game setup, turn flow, scoring, and layout")
	game.queue_free()
	current_scene = null
	await process_frame
	quit()
