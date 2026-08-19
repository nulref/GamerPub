extends Node
## Persistent bridge between the Godot iframe and the Discord Activity wrapper.

signal context_changed(context: Dictionary)
signal room_status_changed(status: String)
signal room_state_changed(room: Dictionary)
signal game_state_changed(game_state: Dictionary)
signal room_error(message: String)
signal shell_command_requested(command: String)

var multiplayer_requested := false
var activity_context: Dictionary = {}
var room_state: Dictionary = {}
var game_state: Dictionary = {}
var room_status := "disconnected"
var last_error := ""

var _window: JavaScriptObject
var _message_callback: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_window = JavaScriptBridge.get_interface("window")
	_message_callback = JavaScriptBridge.create_callback(_on_window_message)
	_window.addEventListener("message", _message_callback)
	call_deferred("_post", "bridge-ready", {})


func begin_multiplayer() -> void:
	multiplayer_requested = true


func end_multiplayer() -> void:
	if multiplayer_requested:
		send_room_command("leave")
	multiplayer_requested = false
	room_state.clear()
	game_state.clear()
	room_status = "disconnected"


func suggested_name() -> String:
	var user: Dictionary = activity_context.get("currentUser", {})
	var candidate := String(user.get("displayName", ""))
	if candidate.is_empty():
		candidate = String(user.get("global_name", ""))
	if candidate.is_empty():
		candidate = String(user.get("username", "Player"))
	return candidate


func current_user_id() -> String:
	var user: Dictionary = activity_context.get("currentUser", {})
	return String(user.get("id", ""))


func is_discord_activity() -> bool:
	return bool(activity_context.get("connected", false)) and not current_user_id().is_empty()


func send_room_command(command: String, values: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		last_error = "Multiplayer is available inside the Discord Activity."
		room_error.emit(last_error)
		return
	var payload := values.duplicate()
	payload["command"] = command
	_post("room-command", payload)


func _post(message_type: String, payload: Dictionary) -> void:
	if not OS.has_feature("web") or _window == null:
		return
	var message := {
		"source": "joker-godot",
		"type": message_type,
		"payload": payload,
	}
	JavaScriptBridge.eval(
		"window.parent.postMessage(%s, window.location.origin);" % JSON.stringify(message)
	)


func _on_window_message(arguments: Array) -> void:
	if arguments.is_empty():
		return
	var event: JavaScriptObject = arguments[0]
	if String(event.origin) != String(_window.location.origin):
		return
	var message: JavaScriptObject = event.data
	if message == null or String(message.source) != "joker-discord-activity":
		return
	var payload_value: Variant = JSON.parse_string(String(message.payloadJson))
	if payload_value == null:
		payload_value = {}

	match String(message.type):
		"discord-context":
			activity_context = payload_value
			context_changed.emit(activity_context)
		"room-status":
			room_status = String(payload_value.get("status", "disconnected"))
			room_status_changed.emit(room_status)
		"room-state":
			room_state = payload_value
			room_state_changed.emit(room_state)
		"game-state":
			game_state = payload_value
			game_state_changed.emit(game_state)
		"room-error":
			last_error = String(payload_value.get("message", "Multiplayer error"))
			room_error.emit(last_error)
		"shell-command":
			shell_command_requested.emit(String(payload_value.get("command", "")))
