class_name JokerGameRules
extends RefCounted
## Pure rules: no nodes, timers, UI, or audio. This is the easiest layer to test.

const GAME_WORD := "JOKER"

enum Combo {
	NONE,
	FOUR_OF_A_KIND,
	THREE_WITH_JOKER,
	FOUR_WITH_JOKER,
}


static func evaluate_hand(cards: Array[JokerCardDefinition]) -> Combo:
	var joker_count := 0
	var rank_counts: Dictionary = {}

	for card in cards:
		if card.is_joker:
			joker_count += 1
		else:
			rank_counts[card.id] = rank_counts.get(card.id, 0) + 1

	var largest_group := 0
	for count: int in rank_counts.values():
		largest_group = maxi(largest_group, count)

	# The active player temporarily holds five cards. A complete four-card set
	# inside that hand is immediately slappable; the unrelated card need not be
	# passed first.
	if joker_count >= 1 and largest_group >= 4:
		return Combo.FOUR_WITH_JOKER
	if joker_count >= 1 and largest_group >= 3:
		return Combo.THREE_WITH_JOKER
	if largest_group >= 4:
		return Combo.FOUR_OF_A_KIND

	return Combo.NONE


static func combo_title(combo: Combo) -> String:
	match combo:
		Combo.FOUR_OF_A_KIND:
			return "Four of a kind"
		Combo.THREE_WITH_JOKER:
			return "Three plus the Joker"
		Combo.FOUR_WITH_JOKER:
			return "Four of a kind plus the Joker"
		_:
			return "No set"


static func penalty_description(combo: Combo) -> String:
	match combo:
		Combo.FOUR_OF_A_KIND:
			return "The last player to slap takes a letter."
		Combo.THREE_WITH_JOKER:
			return "The last two players to slap take a letter."
		Combo.FOUR_WITH_JOKER:
			return "Every player except the winner takes a letter."
		_:
			return ""


static func penalized_players(
	combo: Combo,
	winner: int,
	slap_order: Array[int],
	player_count: int
) -> Array[int]:
	var penalized: Array[int] = []
	match combo:
		Combo.FOUR_OF_A_KIND:
			penalized.append(slap_order[-1])
		Combo.THREE_WITH_JOKER:
			penalized.append(slap_order[-2])
			penalized.append(slap_order[-1])
		Combo.FOUR_WITH_JOKER:
			for player_index in player_count:
				if player_index != winner:
					penalized.append(player_index)
	return penalized
