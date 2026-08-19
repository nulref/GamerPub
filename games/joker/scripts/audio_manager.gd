class_name JokerAudioManager
extends AudioStreamPlayer
## Tiny synthesized sounds keep this tutorial asset-free.
@export var slap_sound: AudioStream

const SAMPLE_RATE := 22050

var sound_enabled: bool = true


func play_pass() -> void:
	_play_tone(520.0, 0.055, 0.20)


func play_slap() -> void:
	if not sound_enabled:
		return

	stream = slap_sound
	play()


func play_letter() -> void:
	_play_tone(230.0, 0.18, 0.28)


func play_round_win() -> void:
	_play_tone(760.0, 0.16, 0.22)


func _play_tone(frequency: float, duration: float, amplitude: float) -> void:
	if not sound_enabled:
		return
	stream = _build_tone(frequency, duration, amplitude)
	play()


func _build_tone(frequency: float, duration: float, amplitude: float) -> AudioStreamWAV:

	var frame_count := int(SAMPLE_RATE * duration)
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 2)

	for frame in frame_count:
		var progress := float(frame) / float(frame_count)
		var envelope := sin(progress * PI)
		var sample := sin(TAU * frequency * float(frame) / SAMPLE_RATE)
		var value := int(clampf(sample * envelope * amplitude, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(frame * 2, value)

	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = SAMPLE_RATE
	wave.stereo = false
	wave.data = bytes
	return wave
