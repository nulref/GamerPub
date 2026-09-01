extends Node
## Browser/Discord bridge for the server-authoritative Cribbage room.

signal context_changed(context: Dictionary)
signal room_status_changed(status: String)
signal room_state_changed(room: Dictionary)
signal game_state_changed(game_state: Dictionary)
signal room_error(message: String)

var context: Dictionary = {}
var room_state: Dictionary = {}
var game_state: Dictionary = {}
var room_status := "disconnected"
var last_error := ""
var multiplayer_requested := false

var _window: JavaScriptObject
var _message_callback: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_window = JavaScriptBridge.get_interface("window")
	_message_callback = JavaScriptBridge.create_callback(_on_window_message)
	_window.addEventListener("message", _message_callback)
	call_deferred("_post", "bridge-ready", {})


func begin_multiplayer(name: String) -> void:
	multiplayer_requested = true
	send_room_command("connect", {"name": name})


func end_multiplayer() -> void:
	if multiplayer_requested:
		send_room_command("leave")
	multiplayer_requested = false
	room_state.clear()
	game_state.clear()
	room_status = "disconnected"


func current_user_id() -> String:
	var user: Dictionary = context.get("currentUser", {})
	return String(user.get("userId", ""))


func suggested_name() -> String:
	var user: Dictionary = context.get("currentUser", {})
	return String(user.get("name", "Player"))


func send_room_command(command: String, payload: Dictionary = {}) -> void:
	if not OS.has_feature("web"):
		last_error = "Multiplayer is available in browser and Discord builds."
		room_error.emit(last_error)
		return
	_post("room-command", {"command": command, "payload": payload})


func request_landscape(enabled: bool) -> void:
	if OS.has_feature("web"):
		_post("orientation", {"landscape": enabled})


func _post(message_type: String, payload: Dictionary) -> void:
	if not OS.has_feature("web") or _window == null:
		return
	var message := {
		"source": "gamer-pub-cribbage-godot",
		"type": message_type,
		"payload": payload,
	}
	JavaScriptBridge.eval(
		"window.postMessage(%s, window.location.origin);" % JSON.stringify(message)
	)


func _on_window_message(arguments: Array) -> void:
	if arguments.is_empty() or _window == null:
		return
	var event: JavaScriptObject = arguments[0]
	if String(event.origin) != String(_window.location.origin):
		return
	var message: JavaScriptObject = event.data
	if message == null or String(message.source) != "gamer-pub-cribbage-web":
		return
	var payload_value: Variant = JSON.parse_string(String(message.payloadJson))
	if payload_value == null:
		payload_value = {}
	match String(message.type):
		"cribbage-context":
			context = payload_value
			context_changed.emit(context)
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
			last_error = String(payload_value.get("message", "Cribbage room error"))
			room_error.emit(last_error)
