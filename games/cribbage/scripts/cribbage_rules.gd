class_name CribbageRules
extends RefCounted
## Pure Cribbage rules shared by the local match, bots, and tests.

const WINNING_SCORE := 121
const SUITS := ["clubs", "diamonds", "hearts", "spades"]


static func valid_player_counts(mode: String) -> Array[int]:
	match mode:
		"standard":
			return [2, 3, 4]
		"partnership":
			return [2, 4]
		"variant":
			return [5, 6]
	return []


static func is_valid_config(mode: String, player_count: int) -> bool:
	return valid_player_counts(mode).has(player_count)


static func mode_title(mode: String) -> String:
	match mode:
		"partnership":
			return "Partnership"
		"variant":
			return "Variant"
	return "Standard"


static func team_for_player(mode: String, player_count: int, player_index: int) -> int:
	if mode == "partnership" and player_count == 4:
		return player_index % 2
	if mode == "variant" and player_count == 6:
		return player_index % 3
	return player_index


static func dealer_partner(mode: String, player_count: int, dealer: int) -> int:
	if mode == "partnership" and player_count == 4:
		return (dealer + 2) % 4
	if mode == "variant" and player_count == 6:
		return (dealer + 3) % 6
	return -1


static func deal_plan(mode: String, player_count: int, dealer: int) -> Dictionary:
	var dealt: Array[int] = []
	var discards: Array[int] = []
	dealt.resize(player_count)
	discards.resize(player_count)
	if player_count == 2:
		dealt.fill(6)
		discards.fill(2)
	elif player_count == 3:
		dealt.fill(5)
		discards.fill(1)
	elif player_count == 4:
		dealt.fill(5)
		discards.fill(1)
	elif player_count == 5:
		dealt.fill(5)
		discards.fill(1)
		dealt[dealer] = 4
		discards[dealer] = 0
	elif player_count == 6:
		dealt.fill(5)
		discards.fill(1)
		dealt[dealer] = 4
		discards[dealer] = 0
		var partner := dealer_partner(mode, player_count, dealer)
		dealt[partner] = 4
		discards[partner] = 0
	return {
		"dealt": dealt,
		"discards": discards,
		"crib_extra": 1 if player_count == 3 else 0,
	}


static func make_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	for suit in SUITS:
		for rank in range(1, 14):
			deck.append({
				"id": "%s_%d" % [suit, rank],
				"suit": suit,
				"rank": rank,
			})
	return deck


static func card_value(card: Dictionary) -> int:
	return mini(int(card.get("rank", 0)), 10)


static func card_label(card: Dictionary) -> String:
	var rank := int(card.get("rank", 0))
	var rank_text := str(rank)
	match rank:
		1: rank_text = "A"
		11: rank_text = "J"
		12: rank_text = "Q"
		13: rank_text = "K"
	var suit_text := String(card.get("suit", "?"))
	var suit_symbol: String = {"clubs": "♣", "diamonds": "♦", "hearts": "♥", "spades": "♠"}.get(suit_text, "?")
	return "%s%s" % [rank_text, suit_symbol]


static func score_hand(hand: Array, starter: Dictionary, is_crib: bool = false) -> Dictionary:
	var cards: Array = hand.duplicate(true)
	if not starter.is_empty():
		cards.append(starter)
	var fifteens := 0
	for mask in range(1, 1 << cards.size()):
		var total := 0
		for index in cards.size():
			if mask & (1 << index):
				total += card_value(cards[index])
		if total == 15:
			fifteens += 2

	var pairs := 0
	for left in cards.size():
		for right in range(left + 1, cards.size()):
			if int(cards[left].rank) == int(cards[right].rank):
				pairs += 2

	var runs := 0
	for run_size in range(cards.size(), 2, -1):
		var run_count := 0
		for mask in range(1, 1 << cards.size()):
			if _bit_count(mask) != run_size:
				continue
			var ranks: Array[int] = []
			for index in cards.size():
				if mask & (1 << index):
					ranks.append(int(cards[index].rank))
			ranks.sort()
			var unique := true
			for index in range(1, ranks.size()):
				if ranks[index] == ranks[index - 1]:
					unique = false
					break
			if unique and ranks[-1] - ranks[0] == run_size - 1:
				run_count += 1
		if run_count > 0:
			runs = run_count * run_size
			break

	var flush := 0
	if hand.size() == 4:
		var hand_flush := true
		for index in range(1, hand.size()):
			if hand[index].suit != hand[0].suit:
				hand_flush = false
				break
		if hand_flush:
			if not starter.is_empty() and starter.suit == hand[0].suit:
				flush = 5
			elif not is_crib:
				flush = 4

	var nobs := 0
	if not starter.is_empty():
		for card in hand:
			if int(card.rank) == 11 and card.suit == starter.suit:
				nobs = 1
				break

	var total_score := fifteens + pairs + runs + flush + nobs
	var detail_parts: Array[String] = []
	if fifteens: detail_parts.append("fifteens %d" % fifteens)
	if pairs: detail_parts.append("pairs %d" % pairs)
	if runs: detail_parts.append("runs %d" % runs)
	if flush: detail_parts.append("flush %d" % flush)
	if nobs: detail_parts.append("nobs 1")
	return {
		"total": total_score,
		"fifteens": fifteens,
		"pairs": pairs,
		"runs": runs,
		"flush": flush,
		"nobs": nobs,
		"detail": ", ".join(detail_parts) if not detail_parts.is_empty() else "no points",
	}


static func score_pegging(sequence: Array, total: int) -> Dictionary:
	var fifteen_or_thirty_one := 2 if total == 15 or total == 31 else 0
	var pairs := 0
	if sequence.size() >= 2:
		var last_rank := int(sequence[-1].rank)
		var matching := 1
		for index in range(sequence.size() - 2, -1, -1):
			if int(sequence[index].rank) != last_rank:
				break
			matching += 1
		match matching:
			2: pairs = 2
			3: pairs = 6
			4: pairs = 12

	var runs := 0
	for run_size in range(mini(sequence.size(), 7), 2, -1):
		var ranks: Array[int] = []
		for index in range(sequence.size() - run_size, sequence.size()):
			ranks.append(int(sequence[index].rank))
		ranks.sort()
		var unique := true
		for index in range(1, ranks.size()):
			if ranks[index] == ranks[index - 1]:
				unique = false
				break
		if unique and ranks[-1] - ranks[0] == run_size - 1:
			runs = run_size
			break
	var score := fifteen_or_thirty_one + pairs + runs
	return {"total": score, "fifteen_or_31": fifteen_or_thirty_one, "pairs": pairs, "runs": runs}


static func _bit_count(value: int) -> int:
	var count := 0
	var remaining := value
	while remaining > 0:
		count += remaining & 1
		remaining >>= 1
	return count
