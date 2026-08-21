extends SceneTree


func _init() -> void:
	_test_special_six_die_scores()
	_test_matching_sets_double()
	_test_singles_and_mixed_scores()
	_test_best_selection()
	_test_reroll_lock_eligibility()
	_test_persistent_hand_scoring()
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


func _test_reroll_lock_eligibility() -> void:
	assert(TenkRules.can_lock_for_reroll([], [1]))
	assert(TenkRules.can_lock_for_reroll([], [1, 2, 3]))
	assert(TenkRules.can_lock_for_reroll([], [2, 3, 4, 5, 6]))
	assert(TenkRules.can_lock_for_reroll([], [4, 4, 4]))
	assert(TenkRules.can_lock_for_reroll([], [4, 4, 4, 4, 4]))
	assert(TenkRules.can_lock_for_reroll([], [2, 2, 3, 3]))
	assert(TenkRules.can_lock_for_reroll([4, 4, 4, 4], [5]))
	assert(TenkRules.can_lock_for_reroll([1, 2, 3, 4, 6], [5]))
	assert(not TenkRules.can_lock_for_reroll([], [4, 4]))
	assert(not TenkRules.can_lock_for_reroll([], [2, 3, 4, 6]))


func _test_persistent_hand_scoring() -> void:
	var result := TenkRules.score_persistent_hand([[1, 5], [1, 1]])
	assert(result.score == 350)
	assert(result.scoring_count == 4)
	result = TenkRules.score_persistent_hand([[1, 1], [1]])
	assert(result.score == 1000)
	assert(result.scoring_count == 3)
	result = TenkRules.score_persistent_hand([[1, 1], [1, 1, 5]])
	assert(result.score == 1150)
	result = TenkRules.score_persistent_hand([[1, 1], [5], [1, 1]])
	assert(result.score == 450)
	assert(result.scoring_count == 5)
	result = TenkRules.score_persistent_hand([[1], [1, 1]])
	assert(result.score == 300)
	result = TenkRules.score_persistent_hand([[4, 4], [4]])
	assert(result.score == 400)
	result = TenkRules.score_persistent_hand([[4, 4, 4], [4]])
	assert(result.score == 400)
	result = TenkRules.score_persistent_hand([[1, 2, 3, 4, 6], [5]])
	assert(result.score == 1500)
	assert(result.all_scoring)
	result = TenkRules.score_persistent_hand([[4, 4, 4, 4], [5], [1]])
	assert(result.score == 950)
	assert(result.all_scoring)


func _assert_score(dice: Array[int], expected: int) -> void:
	var result := TenkRules.score_selection(dice)
	assert(result.valid, "Expected a valid scoring selection: %s" % str(dice))
	assert(result.score == expected, "Expected %d for %s, got %d" % [expected, str(dice), result.score])
