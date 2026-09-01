export interface TenkScore {
  valid: boolean;
  score: number;
  scoringCount: number;
  allScoring: boolean;
  label: string;
}

export interface TenkBestScore extends TenkScore {
  indices: number[];
}

function countsFor(dice: readonly number[]): number[] {
  const counts = Array.from({ length: 7 }, () => 0);
  for (const die of dice) if (Number.isInteger(die) && die >= 1 && die <= 6) counts[die] += 1;
  return counts;
}

function isStraight(counts: readonly number[]): boolean {
  return [1, 2, 3, 4, 5, 6].every((face) => counts[face] === 1);
}

function isThreePairs(counts: readonly number[]): boolean {
  const groups = counts.slice(1).filter((count) => count > 0).sort((left, right) => left - right);
  return JSON.stringify(groups) === JSON.stringify([2, 2, 2]) ||
    JSON.stringify(groups) === JSON.stringify([2, 4]) ||
    JSON.stringify(groups) === JSON.stringify([3, 3]);
}

function isPersistentThreePairs(
  batchCounts: readonly (readonly number[])[],
  fullCounts: readonly number[],
): boolean {
  if (!isThreePairs(fullCounts)) return false;
  for (let face = 1; face <= 6; face += 1) {
    const requiredCount = fullCounts[face];
    if (requiredCount === 0) continue;
    const groupWasRolledTogether = batchCounts.some((counts, batchIndex) =>
      counts[face] === requiredCount ||
      (requiredCount === 3 && counts[face] === 2 && batchCounts[batchIndex + 1]?.[face] === 1));
    if (!groupWasRolledTogether) return false;
  }
  return true;
}

function result(score: number, scoringCount: number, label: string): TenkScore {
  return { valid: score > 0, score, scoringCount, allScoring: scoringCount === 6, label };
}

function scoreFaceCount(face: number, count: number): { score: number; scoringCount: number } {
  if (count <= 0) return { score: 0, scoringCount: 0 };
  if (count >= 3) {
    const base = face === 1 ? 1000 : face * 100;
    return { score: base * (2 ** (count - 3)), scoringCount: count };
  }
  if (face === 1) return { score: count * 100, scoringCount: count };
  if (face === 5) return { score: count * 50, scoringCount: count };
  return { score: 0, scoringCount: 0 };
}

export function scoreSelection(dice: readonly number[]): TenkScore {
  if (dice.length === 0 || dice.length > 6) return result(0, 0, "Not a scoring selection");
  const counts = countsFor(dice);
  if (dice.length === 6) {
    if (isStraight(counts)) return result(1500, 6, "Straight — and rolling");
    if (isThreePairs(counts)) return result(1000, 6, "Three pairs — and rolling");
  }

  let score = 0;
  let scoringCount = 0;
  const parts: string[] = [];
  for (let face = 1; face <= 6; face += 1) {
    const count = counts[face];
    if (count >= 3) {
      const faceScore = scoreFaceCount(face, count);
      score += faceScore.score;
      scoringCount += count;
      parts.push(`${count} × ${face}`);
    } else if (face === 1 || face === 5) {
      const singleValue = face === 1 ? 100 : 50;
      score += count * singleValue;
      scoringCount += count;
      if (count > 0) parts.push(`${count} × ${face}`);
    }
  }
  if (score <= 0 || scoringCount !== dice.length) return result(0, 0, "Not a scoring selection");
  return result(score, scoringCount, parts.join(", "));
}

export function bestScoringSelection(dice: readonly number[]): TenkBestScore {
  let best: TenkBestScore = {
    ...result(0, 0, "No scoring dice"),
    indices: [],
  };
  for (let mask = 1; mask < (1 << dice.length); mask += 1) {
    const selected: number[] = [];
    const indices: number[] = [];
    for (let index = 0; index < dice.length; index += 1) {
      if ((mask & (1 << index)) !== 0) {
        selected.push(dice[index]);
        indices.push(index);
      }
    }
    const scored = scoreSelection(selected);
    if (!scored.valid) continue;
    if (scored.score > best.score ||
        (scored.score === best.score && selected.length > best.scoringCount)) {
      best = { ...scored, allScoring: selected.length === dice.length, indices };
    }
  }
  return best;
}

export function canLockForReroll(lockedDice: readonly number[], selectedDice: readonly number[]): boolean {
  if (selectedDice.length === 0 || lockedDice.length + selectedDice.length > 6) return false;
  if (bestScoringSelection(selectedDice).score > 0) return true;

  const selectedCounts = countsFor(selectedDice);
  if (selectedDice.length === 2 && selectedCounts.slice(1).some((count) => count === 2)) return true;

  const combined = [...lockedDice, ...selectedDice];
  if (combined.length === 6 && scoreSelection(combined).valid) return true;
  const counts = countsFor(combined);
  const lockedCounts = countsFor(lockedDice);
  if (counts.slice(1).filter((count) => count > 0).length >= 5) {
    for (let face = 1; face <= 6; face += 1) {
      if (selectedCounts[face] > 0 && counts[face] === 1) return true;
    }
  }

  let pairFaces = 0;
  for (let face = 1; face <= 6; face += 1) {
    if (counts[face] >= 2) {
      pairFaces += 1;
      if (lockedCounts[face] === 2 && selectedCounts[face] > 0) return true;
    }
  }
  if (pairFaces >= 2) {
    for (let face = 1; face <= 6; face += 1) {
      if (selectedCounts[face] > 0 && counts[face] >= 2) return true;
    }
  }
  return false;
}

export function scorePersistentHand(
  lockedBatches: readonly (readonly number[])[],
  selectedBatch: readonly number[] = [],
  allowCarriedOneTriple = true,
): TenkScore {
  const batches = lockedBatches.map((batch) => [...batch]);
  if (selectedBatch.length > 0) batches.push([...selectedBatch]);
  const allDice = batches.flat();
  const batchCounts = batches.map(countsFor);
  if (allDice.length === 6) {
    const fullCounts = countsFor(allDice);
    if (isStraight(fullCounts)) return result(1500, 6, "Straight — and rolling");
    if (isPersistentThreePairs(batchCounts, fullCounts)) {
      return result(1000, 6, "Three pairs — and rolling");
    }
  }

  let totalScore = 0;
  let totalCount = 0;
  for (let face = 1; face <= 6; face += 1) {
    let bestFaceScore = 0;
    let bestFaceCount = 0;
    for (const counts of batchCounts) {
      const batchResult = scoreFaceCount(face, counts[face]);
      bestFaceScore += batchResult.score;
      bestFaceCount += batchResult.scoringCount;
    }

    for (let pairBatch = 0; pairBatch < batchCounts.length; pairBatch += 1) {
      if (face === 1 && !allowCarriedOneTriple) continue;
      if (batchCounts[pairBatch][face] !== 2) continue;
      const matchingBatch = pairBatch + 1;
      if (matchingBatch >= batchCounts.length || batchCounts[matchingBatch][face] < 1) continue;
      let crossScore = face === 1 ? 1000 : face * 100;
      let crossCount = 3;
      for (let batchIndex = 0; batchIndex < batchCounts.length; batchIndex += 1) {
        let remaining = batchCounts[batchIndex][face];
        if (batchIndex === pairBatch) remaining -= 2;
        else if (batchIndex === matchingBatch) remaining -= 1;
        const remainingResult = scoreFaceCount(face, remaining);
        crossScore += remainingResult.score;
        crossCount += remainingResult.scoringCount;
      }
      if (crossScore > bestFaceScore ||
          (crossScore === bestFaceScore && crossCount > bestFaceCount)) {
        bestFaceScore = crossScore;
        bestFaceCount = crossCount;
      }
    }
    totalScore += bestFaceScore;
    totalCount += bestFaceCount;
  }
  return result(totalScore, totalCount, totalScore > 0 ? "Scoring hand" : "No score");
}
