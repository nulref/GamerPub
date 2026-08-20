class_name TenkRules
extends RefCounted
## Pure scoring helpers for Gamer Pub's version of 10,000.
##
## A scoring selection must be made from a single roll. The one exception is
## `resolve_go_for_plan`, which models the once-per-turn house-rule attempt.


static func score_selection(dice: Array[int]) -> Dictionary:
	var result := {
		"valid": false,
		"score": 0,
		"scoring_count": 0,
		"all_scoring": false,
		"label": "Not a scoring selection",
	}
	if dice.is_empty() or dice.size() > 6:
		return result

	var counts := _counts_for(dice)
	if dice.size() == 6:
		if _is_straight(counts):
			return _valid_result(1500, 6, "Straight — and rolling")
		if _is_three_pairs(counts):
			return _valid_result(1000, 6, "Three pairs — and rolling")

	var score := 0
	var scoring_count := 0
	var parts: Array[String] = []
	for face in range(1, 7):
		var count: int = counts[face]
		if count >= 3:
			var base := 1000 if face == 1 else face * 100
			var group_score: int = base * int(pow(2, count - 3))
			score += group_score
			scoring_count += count
			parts.append("%d × %d" % [count, face])
		elif face == 1 or face == 5:
			var single_value := 100 if face == 1 else 50
			score += count * single_value
			scoring_count += count
			if count > 0:
				parts.append("%d × %d" % [count, face])

	if score <= 0 or scoring_count != dice.size():
		return result

	result.valid = true
	result.score = score
	result.scoring_count = scoring_count
	result.all_scoring = true
	result.label = ", ".join(parts)
	return result


static func best_scoring_selection(dice: Array[int]) -> Dictionary:
	var best := {
		"valid": false,
		"score": 0,
		"scoring_count": 0,
		"all_scoring": false,
		"label": "No scoring dice",
		"indices": PackedInt32Array(),
	}
	var combination_count := 1 << dice.size()
	for mask in range(1, combination_count):
		var selected: Array[int] = []
		var indices := PackedInt32Array()
		for index in range(dice.size()):
			if mask & (1 << index):
				selected.append(dice[index])
				indices.append(index)
		var scored := score_selection(selected)
		if not scored.valid:
			continue
		if scored.score > best.score or (scored.score == best.score and selected.size() > best.scoring_count):
			best = scored.duplicate()
			best.indices = indices
			best.all_scoring = selected.size() == dice.size()
	return best


static func go_for_options(dice: Array[int]) -> Array[int]:
	var options: Array[int] = []
	for plan in go_for_plans(dice):
		options.append(plan.pair_face)
	return options


static func go_for_plans(dice: Array[int]) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	if dice.size() != 6 or score_selection(dice).valid:
		return plans

	var counts := _counts_for(dice)
	for pair_face in range(1, 7):
		if counts[pair_face] != 2:
			continue

		var completed_face := 0
		for face in range(1, 7):
			if face != pair_face and counts[face] == 3:
				completed_face = face
				break

		var locked_dice: Array[int] = [pair_face, pair_face]
		var completion_faces: Array[int] = [pair_face]
		var reroll_count := 4
		var preserves_completed_set := false
		if completed_face > 0:
			locked_dice.clear()
			for die in dice:
				if die == pair_face or die == completed_face:
					locked_dice.append(die)
			completion_faces.append(completed_face)
			completion_faces.sort()
			reroll_count = 1
			preserves_completed_set = true

		plans.append({
			"pair_face": pair_face,
			"locked_dice": locked_dice,
			"reroll_count": reroll_count,
			"target_score": go_for_target_score(pair_face),
			"completion_faces": completion_faces,
			"preserves_completed_set": preserves_completed_set,
		})
	return plans


static func go_for_target_score(face: int) -> int:
	return 1000 if face == 1 else face * 100


static func resolve_go_for_plan(plan: Dictionary, rolled_dice: Array[int]) -> Dictionary:
	var failed := _failed_go_for_result()
	var pair_face := int(plan.get("pair_face", 0))
	var reroll_count := int(plan.get("reroll_count", 0))
	if pair_face < 1 or pair_face > 6 or rolled_dice.size() != reroll_count:
		return failed

	if bool(plan.get("preserves_completed_set", false)):
		if reroll_count != 1:
			return failed
		var completion_faces: Array[int] = []
		for value in plan.get("completion_faces", []):
			completion_faces.append(int(value))
		if not completion_faces.has(rolled_dice[0]):
			return failed
		return {
			"success": true,
			"score": 1000,
			"scoring_count": 6,
			"and_rolling": true,
			"label": "Three-pair special — and rolling",
		}

	return resolve_go_for(pair_face, rolled_dice)


static func resolve_go_for(pair_face: int, rolled_dice: Array[int]) -> Dictionary:
	var failed := _failed_go_for_result()
	if pair_face < 1 or pair_face > 6 or rolled_dice.size() != 4:
		return failed

	# The carried pair plus two fresh pairs makes the special three-pair score.
	# A fresh triple does not combine with the carried pair as "two triplets";
	# ordinary combinations must otherwise occur entirely in one roll.
	var rolled_counts := _counts_for(rolled_dice)
	var rolled_groups: Array[int] = []
	for face in range(1, 7):
		if rolled_counts[face] > 0:
			rolled_groups.append(rolled_counts[face])
	rolled_groups.sort()
	if rolled_groups == [2, 2] or rolled_groups == [4]:
		return {
			"success": true,
			"score": 1000,
			"scoring_count": 6,
			"and_rolling": true,
			"label": "Three pairs — and rolling",
		}

	var matching_index := rolled_dice.find(pair_face)
	if matching_index < 0:
		return failed

	var remaining := rolled_dice.duplicate()
	remaining.remove_at(matching_index)
	var extra := best_scoring_selection(remaining)
	var target_score := go_for_target_score(pair_face)
	var extra_score: int = extra.score
	var extra_count: int = extra.scoring_count
	var scoring_count := 3 + extra_count
	var total_score := target_score + extra_score
	var target_label := "Three %ds" % pair_face
	if extra_score > 0:
		target_label += " + %s" % extra.label
	if scoring_count == 6:
		target_label += " — and rolling"

	return {
		"success": true,
		"score": total_score,
		"scoring_count": scoring_count,
		"and_rolling": scoring_count == 6,
		"label": target_label,
	}


static func _failed_go_for_result() -> Dictionary:
	return {
		"success": false,
		"score": 0,
		"scoring_count": 0,
		"and_rolling": false,
		"label": "Missed the target",
	}


static func _counts_for(dice: Array[int]) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	for die in dice:
		if die >= 1 and die <= 6:
			counts[die] += 1
	return counts


static func _is_straight(counts: Array[int]) -> bool:
	for face in range(1, 7):
		if counts[face] != 1:
			return false
	return true


static func _is_three_pairs(counts: Array[int]) -> bool:
	var groups: Array[int] = []
	for face in range(1, 7):
		if counts[face] > 0:
			groups.append(counts[face])
	groups.sort()
	return groups == [2, 2, 2] or groups == [2, 4] or groups == [3, 3]


static func _valid_result(score: int, count: int, label: String) -> Dictionary:
	return {
		"valid": true,
		"score": score,
		"scoring_count": count,
		"all_scoring": true,
		"label": label,
	}
