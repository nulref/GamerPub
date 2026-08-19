class_name JokerPlayerState
extends Resource
## Round state lives in Resources so it is easy to inspect and test.

@export var display_name: String = "Player"
var hand: Array[JokerCardDefinition] = []
var letters: String = ""


func _init(player_name: String = "Player") -> void:
	display_name = player_name


func reset_for_game() -> void:
	hand.clear()
	letters = ""


func add_letter() -> String:
	if letters.length() < JokerGameRules.GAME_WORD.length():
		letters += JokerGameRules.GAME_WORD[letters.length()]
	return letters


func is_out() -> bool:
	return letters == JokerGameRules.GAME_WORD


func score_label() -> String:
	return letters if not letters.is_empty() else "—"
