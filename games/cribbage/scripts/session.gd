extends Node
## Carries the selected pre-game configuration between Cribbage scenes.

var multiplayer_requested := false
var mode := "standard"
var player_count := 2
var player_name := "You"


func configure(next_mode: String, next_player_count: int, multiplayer: bool) -> void:
	mode = next_mode
	player_count = next_player_count
	multiplayer_requested = multiplayer


func reset() -> void:
	multiplayer_requested = false
	mode = "standard"
	player_count = 2
