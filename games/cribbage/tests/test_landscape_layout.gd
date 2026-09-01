extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(844, 390)
	var menu: Control = load("res://games/cribbage/scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._apply_responsive_layout()
	menu._open_setup(false)
	assert(not menu._rotate_overlay.visible)
	assert(menu._setup_panel.custom_minimum_size == Vector2(1800, 820))
	assert(menu._main_actions.get_child(0).custom_minimum_size.y == 96)
	menu.queue_free()
	await process_frame

	var game: Control = load("res://games/cribbage/scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._apply_responsive_layout()
	assert(game._compact_layout)
	assert(not game._rotate_overlay.visible)
	assert(not game._log_panel.visible)
	assert(game._hand_row.get_child_count() >= 4)
	assert(game._hand_row.get_child(0).custom_minimum_size == Vector2(120, 172))

	root.size = Vector2i(390, 844)
	await process_frame
	game._apply_responsive_layout()
	assert(game._rotate_overlay.visible)
	assert(not game._main_content.visible)
	root.size = Vector2i(1600, 900)
	print("PASS: Cribbage uses its compact landscape table and portrait rotate gate")
	game.queue_free()
	quit()
