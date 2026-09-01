class_name TenkDiceAudio
extends AudioStreamPlayer
## Plays the licensed dice-roll effect used by Tenk.

const ROLL_SOUND: AudioStream = preload("res://games/tenk/assets/audio/dice-roll.wav")

var sound_enabled := true
var play_count := 0
var _roll_stream: AudioStream = ROLL_SOUND


func _ready() -> void:
	stream = _roll_stream


func play_roll(_dice_count: int) -> void:
	if not sound_enabled:
		return
	if _roll_stream == null:
		_roll_stream = ROLL_SOUND
	stream = _roll_stream
	pitch_scale = 1.0
	volume_db = 0.0
	play_count += 1
	play()
