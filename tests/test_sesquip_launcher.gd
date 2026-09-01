extends SceneTree
## Verifies the collection launches Sesquip and the game returns to the launcher.

const LAUNCHER_SCENE_PATH := "res://launcher/main_menu.tscn"
const SESQUIP_SCENE_PATH := "res://games/sesquip/scenes/game.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var launcher_scene: PackedScene = load(LAUNCHER_SCENE_PATH)
	var launcher: Control = launcher_scene.instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame

	var cards: HBoxContainer = launcher.get_node("%Cards")
	assert(cards.get_child_count() == 10)
	assert(cards.get_child(2).game_id == &"sesquip")
	launcher._on_game_selected(&"sesquip")
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == SESQUIP_SCENE_PATH)
	cards = null
	launcher = null
	launcher_scene = null
	current_scene.back_to_launcher()
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == LAUNCHER_SCENE_PATH)
	print("PASS: launcher opens Sesquip and Sesquip returns to Gamer Pub")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	quit()
