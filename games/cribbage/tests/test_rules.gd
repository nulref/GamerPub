extends SceneTree

const RULES := preload("res://games/cribbage/scripts/cribbage_rules.gd")


func _init() -> void:
	var hand: Array = [
		_card("hearts", 5),
		_card("clubs", 5),
		_card("diamonds", 5),
		_card("spades", 11),
	]
	var score := RULES.score_hand(hand, _card("spades", 5))
	assert(score.total == 29)
	assert(score.fifteens == 16)
	assert(score.pairs == 12)
	assert(score.nobs == 1)

	var run_score := RULES.score_hand([
		_card("clubs", 3), _card("diamonds", 3), _card("hearts", 4), _card("spades", 5)
	], _card("clubs", 6))
	assert(run_score.runs == 8)
	assert(run_score.pairs == 2)

	assert(RULES.score_pegging([_card("clubs", 7), _card("hearts", 8)], 15).total == 2)
	assert(RULES.score_pegging([
		_card("clubs", 4), _card("hearts", 6), _card("spades", 5)
	], 15).total == 5)

	var five := RULES.deal_plan("variant", 5, 2)
	assert(five.dealt == [5, 5, 4, 5, 5])
	assert(five.discards == [1, 1, 0, 1, 1])
	var six := RULES.deal_plan("variant", 6, 1)
	assert(six.dealt == [5, 4, 5, 5, 4, 5])
	assert(six.discards == [1, 0, 1, 1, 0, 1])
	assert(RULES.team_for_player("variant", 6, 4) == 1)
	assert(RULES.team_for_player("partnership", 4, 2) == 0)
	print("PASS: Cribbage scoring and 5/6-player deal rules")
	quit()


func _card(suit: String, rank: int) -> Dictionary:
	return {"id": "%s_%d" % [suit, rank], "suit": suit, "rank": rank}
