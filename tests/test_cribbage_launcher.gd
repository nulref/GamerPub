extends SceneTree

const LAUNCHER_SCENE := "res://launcher/main_menu.tscn"
const CRIBBAGE_MENU := "res://games/cribbage/scenes/main_menu.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var launcher: Control = load(LAUNCHER_SCENE).instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame
	var cards: HBoxContainer = launcher.get_node("%Cards")
	assert(cards.get_child(3).game_id == &"cribbage")
	launcher._on_game_selected(&"cribbage")
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == CRIBBAGE_MENU)
	assert(root.has_node("CribbageSession"))
	assert(root.has_node("CribbageWebBridge"))
	print("PASS: launcher opens Cribbage and its shared services are registered")
	current_scene.queue_free()
	quit()
