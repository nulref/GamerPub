import { describe, expect, it } from "vitest";
import {
  bestScoringSelection,
  canLockForReroll,
  scorePersistentHand,
  scoreSelection,
} from "../src/tenk-rules";

describe("Tenk scoring rules", () => {
  it("scores specials, matching sets, and singles", () => {
    expect(scoreSelection([1, 2, 3, 4, 5, 6]).score).toBe(1500);
    expect(scoreSelection([4, 4, 4, 4, 2, 2]).score).toBe(1000);
    expect(scoreSelection([1, 1, 1, 1]).score).toBe(2000);
    expect(scoreSelection([4, 4, 4, 1, 5]).score).toBe(550);
    expect(scoreSelection([2]).valid).toBe(false);
  });

  it("keeps matching sets scoped to their roll except for a carried pair", () => {
    expect(scorePersistentHand([[1, 5], [1, 1]]).score).toBe(350);
    expect(scorePersistentHand([[1, 1], [1]]).score).toBe(1000);
    expect(scorePersistentHand([[1, 1]], [1], false).score).toBe(300);
    expect(scorePersistentHand([[1, 1], [5], [1, 1]]).score).toBe(450);
    expect(scorePersistentHand([[1], [1, 1]]).score).toBe(300);
    expect(scorePersistentHand([[4, 4, 4, 4], [5], [1]])).toMatchObject({
      score: 950,
      allScoring: true,
    });
    expect(scorePersistentHand([[1], [1], [1]], [1, 5, 5])).toMatchObject({
      score: 500,
      allScoring: true,
    });
    expect(scorePersistentHand([[2, 2, 3, 3]], [4, 4])).toMatchObject({
      score: 1000,
      allScoring: true,
    });
    expect(scorePersistentHand([[2, 2], [2]], [6, 6, 6])).toMatchObject({
      score: 1000,
      allScoring: true,
    });
  });

  it("recognizes scoring and qualifying partial rerolls", () => {
    expect(canLockForReroll([], [1])).toBe(true);
    expect(canLockForReroll([], [2, 3, 4, 5, 6])).toBe(true);
    expect(canLockForReroll([], [2, 2, 3, 3])).toBe(true);
    expect(canLockForReroll([6, 6], [6])).toBe(true);
    expect(canLockForReroll([6, 6, 6], [6])).toBe(false);
    expect(canLockForReroll([], [4, 4])).toBe(true);
    expect(bestScoringSelection([2, 2, 3, 4, 5, 6])).toMatchObject({ score: 50, indices: [4] });
  });
});
