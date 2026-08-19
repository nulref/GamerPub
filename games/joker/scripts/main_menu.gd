extends Control

const LAUNCHER_SCENE_PATH := "res://launcher/main_menu.tscn"

@onready var single_player_button: Button = %SinglePlayerButton
@onready var multi_player_button: Button = %MultiPlayerButton
@onready var settings_button: Button = %SettingsButton
@onready var rules_button: Button = %RulesButton
@onready var quit_button: Button = %QuitButton
@onready var settings_overlay: Control = %SettingsOverlay
@onready var rules_overlay: JokerRulesOverlay = %RulesOverlay
@onready var sound_toggle: CheckButton = %SoundToggle
@onready var music_toggle: CheckButton = %MusicToggle
@onready var bot_speed_slider: HSlider = %BotSpeedSlider
@onready var bot_speed_value: Label = %BotSpeedValue
@onready var menu_music: AudioStreamPlayer = $MenuMusic

var _settings := JokerSettingsStore.new()
var _bridge: Node

func _ready() -> void:
	_bridge = get_node("/root/JokerDiscordBridge")
	_bridge.connect("shell_command_requested", _on_shell_command_requested)
	_apply_mobile_layout()
	_connect_signals()
	_load_settings()


func _apply_mobile_layout() -> void:
	if not JokerMobileUI.is_active():
		return
	for control: Control in [
		single_player_button,
		multi_player_button,
		settings_button,
		rules_button,
		quit_button,
		sound_toggle,
		music_toggle,
		%CloseSettingsButton,
	]:
		JokerMobileUI.enlarge_control(control)
	JokerMobileUI.enlarge_control(bot_speed_slider, 72.0, 0)

func _connect_signals() -> void:
	%SinglePlayerButton.pressed.connect(_on_single_pressed)
	%MultiPlayerButton.pressed.connect(_on_multi_pressed)
	%SettingsButton.pressed.connect(_open_settings)
	%RulesButton.pressed.connect(_open_rules)
	%CloseSettingsButton.pressed.connect(_close_settings)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%SoundToggle.toggled.connect(_on_sound_toggled)
	%MusicToggle.toggled.connect(_on_music_toggled)
	%BotSpeedSlider.value_changed.connect(_on_bot_speed_changed)

func _on_single_pressed() -> void:
	get_node("/root/JokerDiscordBridge").set("multiplayer_requested", false)
	get_tree().change_scene_to_file("res://games/joker/scenes/game.tscn")

func _on_multi_pressed() -> void:
	get_node("/root/JokerDiscordBridge").call("begin_multiplayer")
	get_tree().change_scene_to_file("res://games/joker/scenes/game.tscn")

func _load_settings() -> void:
	_settings.load_from_disk()
	sound_toggle.set_pressed_no_signal(_settings.sound_enabled)
	music_toggle.set_pressed_no_signal(_settings.music_enabled)
	bot_speed_slider.set_value_no_signal(_settings.bot_speed_scale)
	_update_speed_label(_settings.bot_speed_scale)
	_set_music_enabled(_settings.music_enabled)

func _on_sound_toggled(enabled: bool) -> void:
	_settings.sound_enabled = enabled

func _on_music_toggled(enabled: bool) -> void:
	_settings.music_enabled = enabled
	_set_music_enabled(enabled)

func _on_bot_speed_changed(value: float) -> void:
	_settings.bot_speed_scale = value
	_update_speed_label(value)

func _open_settings() -> void:
	rules_overlay.close()
	settings_overlay.show()


func _open_rules() -> void:
	settings_overlay.hide()
	rules_overlay.open()


func _on_shell_command_requested(command: String) -> void:
	if command == "open_settings":
		_open_settings()

func _close_settings() -> void:
	_settings.save_to_disk()
	settings_overlay.hide()

func _update_speed_label(value: float) -> void:
	if value < 0.85:
		bot_speed_value.text = "RELAXED"
	elif value > 1.25:
		bot_speed_value.text = "FAST"
	else:
		bot_speed_value.text = "NORMAL"

func _set_music_enabled(enabled: bool) -> void:
	if enabled:
		if not menu_music.playing:
			menu_music.play()
	else:
		menu_music.stop()

func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file(LAUNCHER_SCENE_PATH)
