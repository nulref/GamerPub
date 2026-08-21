class_name TenkRules
extends RefCounted
## Pure scoring helpers for Gamer Pub's version of 10,000.
##
## Locked and newly rolled dice form one persistent six-die hand.


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


static func can_lock_for_reroll(locked_dice: Array[int], selected_dice: Array[int]) -> bool:
	if selected_dice.is_empty() or locked_dice.size() + selected_dice.size() > 6:
		return false

	var selected_score := best_scoring_selection(selected_dice)
	if selected_score.score > 0:
		return true

	var combined := locked_dice.duplicate()
	combined.append_array(selected_dice)
	if combined.size() == 6 and score_selection(combined).valid:
		return true

	var counts := _counts_for(combined)
	var selected_counts := _counts_for(selected_dice)
	var distinct_faces := 0
	for face in range(1, 7):
		if counts[face] > 0:
			distinct_faces += 1
	if distinct_faces >= 5:
		for face in range(1, 7):
			if selected_counts[face] > 0 and counts[face] == 1:
				return true

	var pair_faces := 0
	for face in range(1, 7):
		if counts[face] >= 2:
			pair_faces += 1
		if selected_counts[face] > 0 and counts[face] >= 3 and counts[face] <= 5:
			return true
	if pair_faces >= 2:
		for face in range(1, 7):
			if selected_counts[face] > 0 and counts[face] >= 2:
				return true

	return false


static func score_persistent_hand(locked_batches: Array, selected_batch: Array[int] = []) -> Dictionary:
	var batches: Array = locked_batches.duplicate(true)
	if not selected_batch.is_empty():
		batches.append(selected_batch.duplicate())

	var all_dice: Array[int] = []
	var batch_counts: Array = []
	for raw_batch in batches:
		var batch: Array[int] = []
		for value in raw_batch:
			batch.append(int(value))
		all_dice.append_array(batch)
		batch_counts.append(_counts_for(batch))

	if all_dice.size() == 6:
		var full_counts := _counts_for(all_dice)
		if _is_straight(full_counts):
			return _persistent_result(1500, 6, "Straight — and rolling")
		if _is_three_pairs(full_counts):
			return _persistent_result(1000, 6, "Three pairs — and rolling")

	var total_score := 0
	var total_count := 0
	for face in range(1, 7):
		var best_face_score := 0
		var best_face_count := 0
		for counts in batch_counts:
			var batch_result := _score_face_count(face, int(counts[face]))
			best_face_score += batch_result.score
			best_face_count += batch_result.scoring_count

		for pair_batch in range(batch_counts.size()):
			if int(batch_counts[pair_batch][face]) != 2:
				continue
			for matching_batch in range(pair_batch + 1, batch_counts.size()):
				if int(batch_counts[matching_batch][face]) < 1:
					continue
				var cross_score := 1000 if face == 1 else face * 100
				var cross_count := 3
				for batch_index in range(batch_counts.size()):
					var remaining := int(batch_counts[batch_index][face])
					if batch_index == pair_batch:
						remaining -= 2
					elif batch_index == matching_batch:
						remaining -= 1
					var remaining_result := _score_face_count(face, remaining)
					cross_score += remaining_result.score
					cross_count += remaining_result.scoring_count
				if cross_score > best_face_score or (cross_score == best_face_score and cross_count > best_face_count):
					best_face_score = cross_score
					best_face_count = cross_count

		total_score += best_face_score
		total_count += best_face_count

	return _persistent_result(total_score, total_count, "Scoring hand" if total_score > 0 else "No score")


static func _score_face_count(face: int, count: int) -> Dictionary:
	if count <= 0:
		return {"score": 0, "scoring_count": 0}
	if count >= 3:
		var base := 1000 if face == 1 else face * 100
		return {
			"score": base * int(pow(2, count - 3)),
			"scoring_count": count,
		}
	if face == 1:
		return {"score": count * 100, "scoring_count": count}
	if face == 5:
		return {"score": count * 50, "scoring_count": count}
	return {"score": 0, "scoring_count": 0}


static func _persistent_result(score: int, scoring_count: int, label: String) -> Dictionary:
	return {
		"valid": score > 0,
		"score": score,
		"scoring_count": scoring_count,
		"all_scoring": scoring_count == 6,
		"label": label,
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
