extends SceneTree
## Verifies the collection launches 10,000 and the game returns to the launcher.

const LAUNCHER_SCENE_PATH := "res://launcher/main_menu.tscn"
const TENK_SCENE_PATH := "res://games/tenk/scenes/game.tscn"


func _init() -> void:
	assert(ProjectSettings.get_setting("application/config/icon") == "res://launcher/assets/art/gp_logo.webp")
	call_deferred("_run")


func _run() -> void:
	var launcher_scene: PackedScene = load(LAUNCHER_SCENE_PATH)
	var launcher: Control = launcher_scene.instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame

	var cards: HBoxContainer = launcher.get_node("%Cards")
	assert(cards.get_child_count() == 10)
	assert(cards.get_child(1).game_id == &"tenk")
	root.size = Vector2i(900, 1600)
	await process_frame
	await process_frame
	launcher._update_card_layout()
	assert(launcher._portrait_layout)
	assert(launcher._visible_count == 2)
	assert(cards.get_child(0).custom_minimum_size.y == 400)
	assert(launcher.previous_button.custom_minimum_size == Vector2(130, 190))
	launcher._on_game_selected(&"tenk")
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == TENK_SCENE_PATH)
	cards = null
	launcher = null
	launcher_scene = null
	current_scene.back_to_launcher()
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == LAUNCHER_SCENE_PATH)
	root.size = Vector2i(1600, 900)
	print("PASS: launcher opens 10,000 and 10,000 returns to Gamer Pub")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	quit()
