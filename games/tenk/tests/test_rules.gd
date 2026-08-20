extends SceneTree


func _init() -> void:
	_test_special_six_die_scores()
	_test_matching_sets_double()
	_test_singles_and_mixed_scores()
	_test_best_selection()
	_test_go_for_it()
	_test_go_for_preserves_completed_sets()
	print("PASS: 10,000 scoring rules")
	quit()


func _test_special_six_die_scores() -> void:
	_assert_score([1, 2, 3, 4, 5, 6], 1500)
	_assert_score([1, 1, 2, 2, 3, 3], 1000)
	_assert_score([4, 4, 4, 4, 2, 2], 1000)
	_assert_score([2, 2, 2, 6, 6, 6], 1000)


func _test_matching_sets_double() -> void:
	_assert_score([1, 1, 1], 1000)
	_assert_score([1, 1, 1, 1], 2000)
	_assert_score([1, 1, 1, 1, 1], 4000)
	_assert_score([1, 1, 1, 1, 1, 1], 8000)
	_assert_score([4, 4, 4], 400)
	_assert_score([4, 4, 4, 4], 800)
	_assert_score([4, 4, 4, 4, 4], 1600)
	_assert_score([4, 4, 4, 4, 4, 4], 3200)


func _test_singles_and_mixed_scores() -> void:
	_assert_score([1], 100)
	_assert_score([1, 1], 200)
	_assert_score([5], 50)
	_assert_score([5, 5], 100)
	_assert_score([4, 4, 4, 1, 5], 550)
	assert(not TenkRules.score_selection([2]).valid)
	assert(not TenkRules.score_selection([1, 2]).valid)


func _test_best_selection() -> void:
	var best := TenkRules.best_scoring_selection([2, 2, 3, 4, 5, 6])
	assert(best.score == 50)
	assert(best.scoring_count == 1)
	assert(best.indices == PackedInt32Array([4]))
	best = TenkRules.best_scoring_selection([1, 1, 1, 5, 2, 6])
	assert(best.score == 1050)
	assert(best.scoring_count == 4)


func _test_go_for_it() -> void:
	var result := TenkRules.resolve_go_for(1, [1, 1, 5, 6])
	assert(result.success)
	assert(result.score == 1150)
	assert(not result.and_rolling)

	result = TenkRules.resolve_go_for(4, [4, 5, 5, 1])
	assert(result.success)
	assert(result.score == 600)
	assert(result.and_rolling)

	result = TenkRules.resolve_go_for(4, [4, 1, 2, 6])
	assert(result.success)
	assert(result.score == 500)
	assert(not result.and_rolling)

	result = TenkRules.resolve_go_for(4, [4, 3, 3, 3])
	assert(result.success)
	assert(result.score == 700)
	assert(result.and_rolling)

	result = TenkRules.resolve_go_for(1, [2, 2, 3, 3])
	assert(result.success)
	assert(result.score == 1000)
	assert(result.and_rolling)

	result = TenkRules.resolve_go_for(2, [1, 5, 3, 4])
	assert(not result.success)
	assert(result.score == 0)


func _test_go_for_preserves_completed_sets() -> void:
	var plans := TenkRules.go_for_plans([6, 5, 4, 4, 5, 5])
	assert(plans.size() == 1)
	var plan: Dictionary = plans[0]
	assert(plan.pair_face == 4)
	assert(plan.locked_dice == [5, 4, 4, 5, 5])
	assert(plan.reroll_count == 1)
	assert(plan.completion_faces == [4, 5])
	assert(plan.preserves_completed_set)

	var result := TenkRules.resolve_go_for_plan(plan, [4])
	assert(result.success)
	assert(result.score == 1000)
	assert(result.scoring_count == 6)
	assert(result.and_rolling)
	result = TenkRules.resolve_go_for_plan(plan, [5])
	assert(result.success)
	assert(result.score == 1000)
	assert(result.and_rolling)
	result = TenkRules.resolve_go_for_plan(plan, [6])
	assert(not result.success)

	plans = TenkRules.go_for_plans([2, 4, 4, 2, 4, 1])
	assert(plans.size() == 1)
	plan = plans[0]
	assert(plan.pair_face == 2)
	assert(plan.locked_dice == [2, 4, 4, 2, 4])
	assert(plan.reroll_count == 1)
	assert(plan.completion_faces == [2, 4])
	for completion in [2, 4]:
		result = TenkRules.resolve_go_for_plan(plan, [completion])
		assert(result.success)
		assert(result.score == 1000)
		assert(result.and_rolling)

	var ordinary_plan: Dictionary = TenkRules.go_for_plans([4, 4, 1, 2, 3, 6])[0]
	assert(ordinary_plan.reroll_count == 4)
	assert(ordinary_plan.locked_dice == [4, 4])
	result = TenkRules.resolve_go_for_plan(ordinary_plan, [4, 3, 3, 3])
	assert(result.score == 700)
	assert(result.and_rolling)
	assert(TenkRules.go_for_plans([4, 4, 4, 4, 2, 2]).is_empty())


func _assert_score(dice: Array[int], expected: int) -> void:
	var result := TenkRules.score_selection(dice)
	assert(result.valid, "Expected a valid scoring selection: %s" % str(dice))
	assert(result.score == expected, "Expected %d for %s, got %d" % [expected, str(dice), result.score])
