export const CRIBBAGE_WINNING_SCORE = 121;
export const CRIBBAGE_MODES = ["standard", "partnership", "variant"] as const;
export type CribbageMode = typeof CRIBBAGE_MODES[number];

export interface CribbageCard {
  id: string;
  suit: "clubs" | "diamonds" | "hearts" | "spades";
  rank: number;
}

export interface CribbageHandScore {
  total: number;
  fifteens: number;
  pairs: number;
  runs: number;
  flush: number;
  nobs: number;
  detail: string;
}

export function validCribbagePlayerCounts(mode: CribbageMode): readonly number[] {
  if (mode === "standard") return [2, 3, 4];
  if (mode === "partnership") return [2, 4];
  return [5, 6];
}

export function validCribbageConfig(mode: unknown, playerCount: unknown): mode is CribbageMode {
  return typeof mode === "string" && (CRIBBAGE_MODES as readonly string[]).includes(mode) &&
    Number.isInteger(playerCount) && validCribbagePlayerCounts(mode as CribbageMode).includes(playerCount as number);
}

export function cribbageTeam(mode: CribbageMode, playerCount: number, player: number): number {
  if (mode === "partnership" && playerCount === 4) return player % 2;
  if (mode === "variant" && playerCount === 6) return player % 3;
  return player;
}

export function cribbageDealerPartner(mode: CribbageMode, playerCount: number, dealer: number): number {
  if (mode === "partnership" && playerCount === 4) return (dealer + 2) % 4;
  if (mode === "variant" && playerCount === 6) return (dealer + 3) % 6;
  return -1;
}

export function cribbageDealPlan(mode: CribbageMode, playerCount: number, dealer: number) {
  const dealt = Array<number>(playerCount).fill(playerCount === 2 ? 6 : 5);
  const discards = Array<number>(playerCount).fill(playerCount === 2 ? 2 : 1);
  if (playerCount === 5) {
    dealt[dealer] = 4;
    discards[dealer] = 0;
  } else if (playerCount === 6) {
    dealt[dealer] = 4;
    discards[dealer] = 0;
    const partner = cribbageDealerPartner(mode, playerCount, dealer);
    dealt[partner] = 4;
    discards[partner] = 0;
  }
  return { dealt, discards, cribExtra: playerCount === 3 ? 1 : 0 };
}

export function cribbageDeck(): CribbageCard[] {
  const suits: CribbageCard["suit"][] = ["clubs", "diamonds", "hearts", "spades"];
  return suits.flatMap((suit) => Array.from({ length: 13 }, (_, index) => ({
    id: `${suit}_${index + 1}`,
    suit,
    rank: index + 1,
  })));
}

export function cribbageCardValue(card: CribbageCard): number {
  return Math.min(card.rank, 10);
}

function bitCount(value: number): number {
  let result = 0;
  for (let remaining = value; remaining > 0; remaining >>= 1) result += remaining & 1;
  return result;
}

export function scoreCribbageHand(
  hand: CribbageCard[],
  starter: CribbageCard,
  crib = false,
): CribbageHandScore {
  const cards = [...hand, starter];
  let fifteens = 0;
  for (let mask = 1; mask < (1 << cards.length); mask += 1) {
    const total = cards.reduce((sum, card, index) =>
      sum + ((mask & (1 << index)) ? cribbageCardValue(card) : 0), 0);
    if (total === 15) fifteens += 2;
  }
  let pairs = 0;
  for (let left = 0; left < cards.length; left += 1) {
    for (let right = left + 1; right < cards.length; right += 1) {
      if (cards[left].rank === cards[right].rank) pairs += 2;
    }
  }
  let runs = 0;
  for (let runSize = cards.length; runSize >= 3; runSize -= 1) {
    let count = 0;
    for (let mask = 1; mask < (1 << cards.length); mask += 1) {
      if (bitCount(mask) !== runSize) continue;
      const ranks = cards.filter((_, index) => mask & (1 << index)).map((card) => card.rank)
        .sort((left, right) => left - right);
      if (new Set(ranks).size === runSize && ranks.at(-1)! - ranks[0] === runSize - 1) count += 1;
    }
    if (count) {
      runs = count * runSize;
      break;
    }
  }
  const handFlush = hand.length === 4 && hand.every((card) => card.suit === hand[0].suit);
  const flush = handFlush && starter.suit === hand[0].suit ? 5 : handFlush && !crib ? 4 : 0;
  const nobs = hand.some((card) => card.rank === 11 && card.suit === starter.suit) ? 1 : 0;
  const parts = [
    fifteens ? `fifteens ${fifteens}` : "",
    pairs ? `pairs ${pairs}` : "",
    runs ? `runs ${runs}` : "",
    flush ? `flush ${flush}` : "",
    nobs ? "nobs 1" : "",
  ].filter(Boolean);
  return {
    total: fifteens + pairs + runs + flush + nobs,
    fifteens,
    pairs,
    runs,
    flush,
    nobs,
    detail: parts.join(", ") || "no points",
  };
}

export function scoreCribbagePeg(sequence: CribbageCard[], total: number): number {
  let score = total === 15 || total === 31 ? 2 : 0;
  if (sequence.length >= 2) {
    let matching = 1;
    const lastRank = sequence.at(-1)!.rank;
    for (let index = sequence.length - 2; index >= 0 && sequence[index].rank === lastRank; index -= 1) {
      matching += 1;
    }
    score += matching === 2 ? 2 : matching === 3 ? 6 : matching >= 4 ? 12 : 0;
  }
  for (let size = Math.min(sequence.length, 7); size >= 3; size -= 1) {
    const ranks = sequence.slice(-size).map((card) => card.rank).sort((left, right) => left - right);
    if (new Set(ranks).size === size && ranks.at(-1)! - ranks[0] === size - 1) {
      score += size;
      break;
    }
  }
  return score;
}
