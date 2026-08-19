extends SceneTree
## Verifies that the composed game scene can build its hand and target presentation nodes.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://games/joker/scenes/game.tscn")
	var main: Control = packed_scene.instantiate()
	root.add_child(main)
	await process_frame

	var hand: HBoxContainer = main.get_node("%HandContainer")
	assert(hand.get_child_count() in [4, 5])
	var one_key := InputEventKey.new()
	one_key.pressed = true
	one_key.keycode = KEY_1
	assert(main._card_index_from_key(one_key) == 0)
	var five_key := InputEventKey.new()
	five_key.pressed = true
	five_key.keycode = KEY_5
	assert(main._card_index_from_key(five_key) == 4)
	var six_key := InputEventKey.new()
	six_key.pressed = true
	six_key.keycode = KEY_6
	assert(main._card_index_from_key(six_key) == -1)

	if hand.get_child_count() == 5:
		assert(main._try_pass_card_by_number(0))
		await process_frame
	assert(hand.get_child_count() == 4)
	assert(not main._try_pass_card_by_number(4))

	var animation: AnimationPlayer = main.get_node("%AnimationPlayer")
	var table: PanelContainer = main.get_node("%TablePanel")
	animation.play("slap_flash")
	animation.advance(0.08)
	assert(table.modulate != Color.WHITE)

	var audio: JokerAudioManager = main.get_node("%AudioManager")
	var tone: AudioStreamWAV = audio._build_tone(115.0, 0.10, 0.48)
	assert(tone.data.size() > 0)

	var game_rules_button: Button = main.get_node("%RulesButton")
	var game_rules_overlay: Control = main.get_node("%RulesOverlay")
	assert(game_rules_button.get_index() == main.get_node("%SettingsButton").get_index() + 1)
	game_rules_button.pressed.emit()
	assert(game_rules_overlay.visible)
	game_rules_overlay.get_node("%CloseRulesButton").pressed.emit()
	assert(not game_rules_overlay.visible)

	main.queue_free()
	await process_frame

	var menu_scene: PackedScene = load("res://games/joker/scenes/main_menu.tscn")
	var menu: Control = menu_scene.instantiate()
	# The menu music is unrelated to this UI check and otherwise leaves the
	# headless audio driver holding a playback object during shutdown.
	var menu_music: AudioStreamPlayer = menu.get_node("MenuMusic")
	menu_music.stream = null
	root.add_child(menu)
	await process_frame
	var menu_rules_button: Button = menu.get_node("%RulesButton")
	var menu_rules_overlay: Control = menu.get_node("%RulesOverlay")
	assert(menu_rules_button.get_index() == menu.get_node("%SettingsButton").get_index() + 1)
	menu_rules_button.pressed.emit()
	assert(menu_rules_overlay.visible)
	menu_rules_overlay.get_node("%CloseRulesButton").pressed.emit()
	assert(not menu_rules_overlay.visible)

	print("PASS: game and menu presentation, rules overlays, and audio are wired")
	menu.queue_free()
	await process_frame
	menu_music = null
	menu = null
	menu_scene = null
	quit()
