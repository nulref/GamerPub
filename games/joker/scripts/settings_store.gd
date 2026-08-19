class_name JokerSettingsStore
extends RefCounted
## ConfigFile is a good fit for small, human-readable preferences.

const SETTINGS_PATH := "user://joker_settings.cfg"

var sound_enabled: bool = true
var music_enabled: bool = true
var bot_speed_scale: float = 1.0


func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	sound_enabled = bool(config.get_value("audio", "sound_enabled", true))
	music_enabled = bool(config.get_value("audio", "music_enabled", true))
	bot_speed_scale = clampf(
		float(config.get_value("gameplay", "bot_speed_scale", 1.0)),
		0.65,
		1.60
	)


func save_to_disk() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "sound_enabled", sound_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("gameplay", "bot_speed_scale", bot_speed_scale)
	return config.save(SETTINGS_PATH)
