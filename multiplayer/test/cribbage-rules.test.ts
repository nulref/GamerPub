import { describe, expect, it } from "vitest";
import {
  type CribbageCard,
  cribbageDealPlan,
  cribbageTeam,
  scoreCribbageHand,
  scoreCribbagePeg,
} from "../src/cribbage-rules";

const card = (suit: CribbageCard["suit"], rank: number): CribbageCard => ({
  id: `${suit}_${rank}`,
  suit,
  rank,
});

describe("Cribbage rules", () => {
  it("scores the canonical 29 hand", () => {
    const score = scoreCribbageHand([
      card("hearts", 5), card("clubs", 5), card("diamonds", 5), card("spades", 11),
    ], card("spades", 5));
    expect(score).toMatchObject({ total: 29, fifteens: 16, pairs: 12, nobs: 1 });
  });

  it("scores pegging combinations together", () => {
    expect(scoreCribbagePeg([card("clubs", 7), card("hearts", 8)], 15)).toBe(2);
    expect(scoreCribbagePeg([card("clubs", 4), card("hearts", 6), card("spades", 5)], 15)).toBe(5);
  });

  it("uses the requested five- and six-player deals and teams", () => {
    expect(cribbageDealPlan("variant", 5, 2)).toMatchObject({
      dealt: [5, 5, 4, 5, 5], discards: [1, 1, 0, 1, 1],
    });
    expect(cribbageDealPlan("variant", 6, 1)).toMatchObject({
      dealt: [5, 4, 5, 5, 4, 5], discards: [1, 0, 1, 1, 0, 1],
    });
    expect(cribbageTeam("variant", 6, 4)).toBe(1);
    expect(cribbageTeam("partnership", 4, 2)).toBe(0);
  });
});
