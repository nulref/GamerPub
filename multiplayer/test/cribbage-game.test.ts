import { describe, expect, it } from "vitest";
import { CribbageGame } from "../src/cribbage-game";
import type { CribbageMode } from "../src/cribbage-rules";
import type { CribbageRoomPlayer } from "../src/cribbage-room-state";

function players(count: number): CribbageRoomPlayer[] {
  return Array.from({ length: count }, (_, index) => ({
    id: `p${index}`,
    name: `Player ${index + 1}`,
    ready: true,
    connected: true,
    joinedAt: index,
    seat: index,
  }));
}

function finishOneDeal(mode: CribbageMode, count: number) {
  const roomPlayers = players(count);
  const game = new CribbageGame(roomPlayers, mode, () => 0.37);
  for (const player of roomPlayers) {
    const view = game.publicSnapshot(player.id);
    if (!view.discarded) {
      game.discard(player.id, Array.from({ length: view.requiredDiscard }, (_, index) => index));
    }
  }
  let view = game.publicSnapshot(roomPlayers[0].id);
  expect(view.starter).not.toEqual({});
  expect(view.players.every((player) => player.cardCount === 4)).toBe(true);
  let safety = 0;
  while (view.phase === "pegging" && safety < 100) {
    const active = view.activePlayer;
    const activeView = game.publicSnapshot(roomPlayers[active].id);
    const legal = activeView.hand.findIndex((card) =>
      Math.min(card.rank, 10) + activeView.pegTotal <= 31);
    expect(legal).toBeGreaterThanOrEqual(0);
    game.playCard(roomPlayers[active].id, legal);
    view = game.publicSnapshot(roomPlayers[0].id);
    safety += 1;
  }
  expect(safety).toBeLessThan(100);
  expect(view.phase).toBe("show");
  expect(view.showItems).toHaveLength(count + 1);
  return view;
}

describe("Cribbage game", () => {
  it.each([
    ["standard", 2], ["standard", 3], ["standard", 4],
    ["partnership", 2], ["partnership", 4], ["variant", 5], ["variant", 6],
  ] as [CribbageMode, number][]) ("completes a %s %i-player deal", (mode, count) => {
    finishOneDeal(mode, count);
  });

  it("keeps six-player partner scores synchronized", () => {
    const view = finishOneDeal("variant", 6);
    expect(view.players[1].team).toBe(view.players[4].team);
    expect(view.players[1].score).toBe(view.players[4].score);
  });
});
