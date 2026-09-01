extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio := TenkDiceAudio.new()
	root.add_child(audio)
	await process_frame
	assert(audio._roll_stream is AudioStreamWAV)
	assert(audio._roll_stream.resource_path == "res://games/tenk/assets/audio/dice-roll.wav")
	assert(audio._roll_stream.get_length() > 1.0)
	assert(audio.stream == audio._roll_stream)

	audio.play_roll(6)
	assert(audio.play_count == 1)
	assert(audio.playing)
	assert(audio.pitch_scale == 1.0)

	print("PASS: Tenk dice-roll WAV is loaded and playable")
	audio.stop()
	audio._roll_stream = null
	audio.stream = null
	audio.queue_free()
	await process_frame
	await process_frame
	quit()
