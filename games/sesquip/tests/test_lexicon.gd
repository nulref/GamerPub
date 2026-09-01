extends SceneTree
## Verifies prefix traversal, terminal-word detection, and normalization.

const LEXICON := preload("res://games/sesquip/scripts/sesquip_lexicon.gd")


func _init() -> void:
	var lexicon = LEXICON.new(PackedStringArray([
		"CAR",
		"CARD",
		"CART",
		"CARTON",
		"DOG",
	]))

	assert(lexicon.word_count == 5)
	assert(lexicon.is_prefix("ca"))
	assert(lexicon.is_word("car"))
	assert(not lexicon.is_terminal_word("CAR"))
	assert(lexicon.legal_letters("CAR") == PackedStringArray(["D", "T"]))
	assert(lexicon.completion_count("CAR") == 4)
	assert(lexicon.is_terminal_word("CARD"))
	assert(not lexicon.has_continuations("CARTON"))
	assert(not lexicon.is_prefix("CAT"))
	assert(not lexicon.add_word("A"))
	assert(not lexicon.add_word("CAN'T"))
	assert(LEXICON.normalize("  carton ") == "CARTON")
	print("PASS: Sesquip lexicon traverses prefixes and terminal words")
	quit()
