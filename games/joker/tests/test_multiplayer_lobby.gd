extends SceneTree
## Verifies that multiplayer pauses the local controller behind the lobby overlay.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bridge := root.get_node("JokerDiscordBridge")
	assert(not bridge.is_discord_activity())
	bridge.activity_context = {
		"connected": true,
		"currentUser": {"id": "play-tester"},
	}
	assert(bridge.is_discord_activity())
	bridge.activity_context.clear()
	bridge.begin_multiplayer()
	var packed_scene: PackedScene = load("res://games/joker/scenes/game.tscn")
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame

	var overlay: JokerWaitingOverlay = scene.get_node("WaitingOverlay")
	var controller: JokerGameController = scene.get_node("GameController")
	assert(overlay.visible)
	assert(controller.phase == JokerGameController.Phase.SETUP)
	assert(controller.round_number == 0)

	bridge.multiplayer_requested = false
	scene.queue_free()
	print("PASS: multiplayer opens a waiting overlay without starting a local match")
	quit()
