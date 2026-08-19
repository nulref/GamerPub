class_name JokerWaitingOverlay
extends Control
## Lobby UI shown over the paused game table.

signal cancelled

@onready var status_label: Label = %LobbyStatus
@onready var name_edit: LineEdit = %PlayerNameEdit
@onready var name_button: Button = %ApplyNameButton
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartGameButton
@onready var seat_labels: Array[Label] = [%Seat1, %Seat2, %Seat3, %Seat4]

var _room: Dictionary = {}
var _local_ready := false
var _bridge: Node
var _connect_requested := false
var bot_speed_scale := 1.0


func _ready() -> void:
	_apply_mobile_layout()
	_bridge = get_node("/root/JokerDiscordBridge")
	_bridge.connect("context_changed", _on_context_changed)
	_bridge.connect("room_status_changed", _on_room_status_changed)
	_bridge.connect("room_state_changed", _on_room_state_changed)
	_bridge.connect("room_error", _on_room_error)
	name_button.pressed.connect(_apply_name)
	name_edit.text_submitted.connect(func(_text: String) -> void: _apply_name())
	ready_button.pressed.connect(_toggle_ready)
	start_button.pressed.connect(func() -> void:
		_bridge.call("send_room_command", "start_game", {"botSpeedScale": bot_speed_scale})
	)
	%CancelLobbyButton.pressed.connect(_cancel)


func _apply_mobile_layout() -> void:
	if not JokerMobileUI.is_active():
		return
	for control: Control in [
		name_edit,
		name_button,
		ready_button,
		start_button,
		%CancelLobbyButton,
	]:
		JokerMobileUI.enlarge_control(control)
	$Center/Panel/Margin.add_theme_constant_override("margin_left", 20)
	$Center/Panel/Margin.add_theme_constant_override("margin_top", 20)
	$Center/Panel/Margin.add_theme_constant_override("margin_right", 20)
	$Center/Panel/Margin.add_theme_constant_override("margin_bottom", 20)
	$Center/Panel/Margin/Column.add_theme_constant_override("separation", 8)
	$Center/Panel/Margin/Column/Seats.custom_minimum_size.y = 128
	$Center/Panel/Margin/Column/Title.add_theme_font_size_override("font_size", 30)
	status_label.add_theme_font_size_override("font_size", 20)
	for seat_label in seat_labels:
		seat_label.add_theme_font_size_override("font_size", 20)


func begin() -> void:
	show()
	name_edit.text = String(_bridge.call("suggested_name"))
	status_label.text = "Connecting to this Discord Activity..."
	ready_button.disabled = true
	start_button.disabled = true
	_connect_requested = false
	_try_connect()


func _on_context_changed(_context: Dictionary) -> void:
	if name_edit.text.is_empty():
		name_edit.text = String(_bridge.call("suggested_name"))
	_try_connect()


func _on_room_status_changed(status: String) -> void:
	match status:
		"waiting_for_discord":
			status_label.text = "Waiting for Discord identity..."
		"connecting":
			status_label.text = "Connecting to the room..."
		"waiting_for_host":
			status_label.text = "Waiting for a player with Lifetime Access to host..."
		"reconnecting":
			status_label.text = "Connection lost - reconnecting..."
		"disconnected":
			status_label.text = "Disconnected from the room."


func _on_room_error(message: String) -> void:
	status_label.text = message


func _on_room_state_changed(room: Dictionary) -> void:
	_room = room
	_connect_requested = true
	var players: Array = room.get("players", [])
	var local_id := String(_bridge.call("current_user_id"))
	var local_player: Dictionary = {}

	for index in seat_labels.size():
		if index < players.size():
			var player: Dictionary = players[index]
			var badges: PackedStringArray = []
			if String(player.get("id", "")) == String(room.get("hostId", "")):
				badges.append("HOST")
			if bool(player.get("ready", false)):
				badges.append("READY")
			if not bool(player.get("connected", true)):
				badges.append("RECONNECTING")
			var suffix := ""
			if not badges.is_empty():
				suffix = "  [%s]" % " / ".join(badges)
			seat_labels[index].text = "%d.  %s%s" % [
				index + 1,
				String(player.get("name", "Player")),
				suffix,
			]
			if String(player.get("id", "")) == local_id:
				local_player = player
		else:
			seat_labels[index].text = "%d.  Waiting for player..." % (index + 1)

	_local_ready = bool(local_player.get("ready", false))
	ready_button.text = "NOT READY" if _local_ready else "I'M READY"
	ready_button.disabled = local_player.is_empty() or String(room.get("phase", "")) != "waiting"

	var is_host := local_id == String(room.get("hostId", ""))
	var everyone_ready := not players.is_empty()
	for player: Dictionary in players:
		if bool(player.get("connected", false)) and not bool(player.get("ready", false)):
			everyone_ready = false
	start_button.visible = is_host
	start_button.disabled = not is_host or not everyone_ready or String(room.get("phase", "")) != "waiting"
	var bot_count: int = maxi(0, 4 - players.size())
	start_button.text = "START GAME  (%d BOT%s)" % [bot_count, "" if bot_count == 1 else "S"]

	if String(room.get("phase", "")) == "playing":
		status_label.text = "Game started - loading the shared table..."
	else:
		status_label.text = "%d player%s joined. Everyone must be ready." % [
			players.size(),
			"" if players.size() == 1 else "s",
		]


func _apply_name() -> void:
	if _room.is_empty():
		_try_connect()
	else:
		_bridge.call("send_room_command", "set_name", {"name": name_edit.text})


func _toggle_ready() -> void:
	ready_button.disabled = true
	_bridge.call("send_room_command", "set_ready", {"ready": not _local_ready})


func _cancel() -> void:
	_bridge.call("end_multiplayer")
	cancelled.emit()


func _try_connect() -> void:
	if _connect_requested:
		return
	var context: Dictionary = _bridge.get("activity_context")
	var user: Dictionary = context.get("currentUser", {})
	if not bool(context.get("connected", false)) or String(user.get("id", "")).is_empty():
		status_label.text = "Waiting for Discord identity..."
		return
	_connect_requested = true
	_bridge.call("send_room_command", "connect", {"name": name_edit.text})
