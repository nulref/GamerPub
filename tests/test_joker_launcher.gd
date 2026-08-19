extends SceneTree
## Verifies the collection launches Joker and Joker returns to the launcher.

const LAUNCHER_SCENE_PATH := "res://launcher/main_menu.tscn"
const JOKER_SCENE_PATH := "res://games/joker/scenes/main_menu.tscn"


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
	assert(cards.get_child(0).game_id == &"joker")
	launcher._on_game_selected(&"joker")
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == JOKER_SCENE_PATH)
	cards = null
	launcher = null
	launcher_scene = null
	var menu_music: AudioStreamPlayer = current_scene.get_node("MenuMusic")
	menu_music.stop()
	menu_music.stream = null
	current_scene.get_node("%QuitButton").pressed.emit()
	await process_frame
	await process_frame

	assert(current_scene != null)
	assert(current_scene.scene_file_path == LAUNCHER_SCENE_PATH)
	print("PASS: launcher opens Joker and Joker returns to Gamer Pub")
	menu_music = null
	current_scene.queue_free()
	current_scene = null
	await process_frame
	quit()
