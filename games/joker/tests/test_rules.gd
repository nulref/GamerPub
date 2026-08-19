extends SceneTree
## Run with: godot --headless --path . --script tests/test_rules.gd

const ACE: JokerCardDefinition = preload("res://games/joker/resources/ranks/spade_ace.tres")
const TWO: JokerCardDefinition = preload("res://games/joker/resources/ranks/spade_two.tres")
const JOKER: JokerCardDefinition = preload("res://games/joker/resources/ranks/joker.tres")


func _init() -> void:
	assert(JokerGameRules.evaluate_hand(_cards([ACE, ACE, ACE, ACE])) == JokerGameRules.Combo.FOUR_OF_A_KIND)
	assert(JokerGameRules.evaluate_hand(_cards([TWO, TWO, TWO, JOKER])) == JokerGameRules.Combo.THREE_WITH_JOKER)
	assert(JokerGameRules.evaluate_hand(_cards([ACE, ACE, ACE, ACE, JOKER])) == JokerGameRules.Combo.FOUR_WITH_JOKER)

	# A completed set is immediately valid inside the active player's five-card hand.
	assert(JokerGameRules.evaluate_hand(_cards([ACE, ACE, ACE, ACE, TWO])) == JokerGameRules.Combo.FOUR_OF_A_KIND)
	assert(JokerGameRules.evaluate_hand(_cards([TWO, TWO, TWO, JOKER, ACE])) == JokerGameRules.Combo.THREE_WITH_JOKER)
	assert(JokerGameRules.evaluate_hand(_cards([ACE, ACE, TWO, JOKER])) == JokerGameRules.Combo.NONE)

	var slap_order: Array[int] = [2, 0, 3, 1]
	assert(JokerGameRules.penalized_players(JokerGameRules.Combo.FOUR_OF_A_KIND, 2, slap_order, 4) == [1])
	assert(JokerGameRules.penalized_players(JokerGameRules.Combo.THREE_WITH_JOKER, 2, slap_order, 4) == [3, 1])
	assert(JokerGameRules.penalized_players(JokerGameRules.Combo.FOUR_WITH_JOKER, 2, slap_order, 4) == [0, 1, 3])

	print("PASS: all Joker rule checks succeeded")
	quit()


func _cards(values: Array) -> Array[JokerCardDefinition]:
	var result: Array[JokerCardDefinition] = []
	for value: JokerCardDefinition in values:
		result.append(value)
	return result
