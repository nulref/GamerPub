import { describe, expect, it } from "vitest";
import { CARD_IDS, MultiplayerGame, evaluateHand, type MatchStorageSnapshot } from "../src/game-state";
import type { RoomPlayer } from "../src/room-state";

function players(): RoomPlayer[] {
  return ["Alice", "Bot 1", "Bot 2", "Bot 3"].map((name, seat) => ({
    id: seat === 0 ? "alice" : `bot-${seat}`,
    name,
    ready: true,
    connected: true,
    joinedAt: seat,
    seat,
    isBot: seat > 0,
  }));
}

describe("multiplayer game", () => {
  it("evaluates all three winning combinations", () => {
    expect(evaluateHand(["spade_ace", "heart_ace", "club_ace", "diamond_ace"])).toBe("four_of_a_kind");
    expect(evaluateHand(["spade_two", "heart_two", "club_two", "joker"])).toBe("three_with_joker");
    expect(evaluateHand(["spade_three", "heart_three", "club_three", "diamond_three", "joker"])).toBe("four_with_joker");
    expect(evaluateHand(["spade_three", "heart_three", "club_three", "diamond_three", "spade_ace"])).toBe("four_of_a_kind");
    expect(evaluateHand(["spade_two", "heart_two", "club_two", "joker", "spade_ace"])).toBe("three_with_joker");
  });

  it("deals every card and exposes only the requesting player's hand", () => {
    const game = new MultiplayerGame(players(), () => 0.5);
    const publicState = game.publicSnapshot("alice");
    expect(publicState.players.reduce((total, player) => total + player.cardCount, 0)).toBe(CARD_IDS.length);
    expect(publicState.hand).toHaveLength(publicState.players[publicState.localSeat].cardCount);
    expect(publicState.players.every((player) => !("hand" in player))).toBe(true);
  });

  it("allows an immediate slap with four of a kind inside a five-card hand", () => {
    const stored: MatchStorageSnapshot = {
      phase: "passing",
      players: players().map((player, seat) => ({
        id: player.id,
        name: player.name,
        isBot: player.isBot,
        connected: true,
        hand: seat === 0
          ? ["spade_ace", "heart_ace", "club_ace", "diamond_ace", "spade_two"]
          : [`spade_${["two", "three", "four"][seat - 1]}`],
        letters: 0,
      })),
      roundNumber: 1,
      activeSeat: 0,
      slapOrder: [],
      winningSeat: null,
      winningCombo: null,
      result: null,
      revision: 1,
      lastEvent: null,
    };
    const game = new MultiplayerGame(players(), () => 0.5, stored);
    game.slap("alice");
    const slappingState = game.publicSnapshot("alice");

    expect(slappingState.phase).toBe("slapping");
    expect(slappingState.winningCombo).toBe("four_of_a_kind");
    expect(slappingState.slapOrder).toEqual([0]);

    game.performAutomatedAction();
    game.performAutomatedAction();
    game.performAutomatedAction();
    const state = game.publicSnapshot("alice");

    expect(state.phase).toBe("round_result");
    expect(state.result?.winner).toBe(0);
    expect(state.result?.penalized).toHaveLength(1);
    expect(state.players.filter((player) => player.letters === 1)).toHaveLength(1);
  });

  it("paces bot turns one action at a time and honors the host speed", () => {
    const stored: MatchStorageSnapshot = {
      phase: "passing",
      players: players().map((player, seat) => ({
        id: player.id,
        name: player.name,
        isBot: player.isBot,
        connected: true,
        hand: [`${["spade", "heart", "club", "diamond"][seat]}_${["ace", "two", "three", "four"][seat]}`],
        letters: 0,
      })),
      roundNumber: 1,
      activeSeat: 1,
      slapOrder: [],
      winningSeat: null,
      winningCombo: null,
      result: null,
      revision: 1,
      lastEvent: null,
      botSpeedScale: 0.65,
    };
    const game = new MultiplayerGame(players(), () => 0, stored);

    expect(game.nextAutomationDelayMs()).toBe(646);
    expect(game.publicSnapshot("alice").activeSeat).toBe(1);
    expect(game.performAutomatedAction()).toBe(true);
    expect(game.publicSnapshot("alice").activeSeat).toBe(2);

    game.setBotSpeedScale(1.6);
    expect(game.nextAutomationDelayMs()).toBe(263);
  });
});
