import { describe, expect, it } from "vitest";
import { TenkGame } from "../src/tenk-game";
import type { TenkRoomPlayer } from "../src/tenk-room-state";

const players: TenkRoomPlayer[] = [
  { id: "one", name: "One", ready: true, connected: true, joinedAt: 1, seat: 0 },
  { id: "two", name: "Two", ready: true, connected: true, joinedAt: 2, seat: 1 },
];

function straightRandom() {
  let index = 0;
  return () => ((index++ % 6) + 0.01) / 6;
}

function diceSequenceRandom(dice: readonly number[]) {
  let index = 0;
  return () => (dice[index++ % dice.length] - 0.5) / 6;
}

function gameAtScore(score: number, random: () => number): TenkGame {
  const snapshot = new TenkGame(players, straightRandom()).snapshot();
  snapshot.players[0].score = score;
  snapshot.players[0].onBoard = true;
  return new TenkGame(players, random, snapshot);
}

describe("authoritative Tenk game", () => {
  it("rolls, scores a straight, banks, and advances the turn", () => {
    const entries: string[] = [];
    const game = new TenkGame(players, straightRandom(), undefined, (entry) => entries.push(entry));
    game.roll("one");
    expect(game.snapshot()).toMatchObject({
      currentRoll: [1, 2, 3, 4, 5, 6],
      selectedIndices: [],
      displayTurnScore: 0,
    });
    game.setSelection("one", [0, 1, 2, 3, 4, 5]);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [0, 1, 2, 3, 4, 5],
      displayTurnScore: 1500,
    });
    game.reroll("one", [0, 1, 2, 3, 4, 5]);
    expect(game.snapshot()).toMatchObject({ turnScore: 1500, hotHandReady: true });
    game.keep("one", []);
    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      turnScore: 0,
      currentRoll: [],
      status: "One banked 1500 points. Two, roll all six dice.",
    });
    expect(game.snapshot().players[0]).toMatchObject({ score: 1500, onBoard: true });
    expect(entries).toEqual(expect.arrayContaining([
      expect.stringMatching(/roll=1 .* event=ROLL .* dice=\[1, 2, 3, 4, 5, 6\] .* roll_points=1500/),
      expect.stringMatching(/roll=1 .* event=ACTION .* action=REROLL .* points=1500/),
      expect.stringMatching(/roll=1 .* event=ACTION .* action=KEEP .* points=0 .* turn_points=1500/),
      expect.stringMatching(/roll=1 .* event=OUTCOME .* outcome=BANKED .* points=1500/),
      expect.stringMatching(/roll=1 .* event=ACTION .* action=AUTO_NEXT_PLAYER/),
    ]));
    expect(game.snapshot().activity.some((entry) => entry.includes("event=ROLL"))).toBe(true);
  });

  it("logs zero-point rolls, player actions, and bust outcomes", () => {
    const entries: string[] = [];
    const random = diceSequenceRandom([2, 2, 3, 3, 4, 6, 4, 6]);
    const game = new TenkGame(players, random, undefined, (entry) => entries.push(entry));

    game.roll("one");
    game.reroll("one", [0, 1, 2, 3]);

    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      turnScore: 0,
      status: expect.stringContaining("Two, roll all six dice."),
    });
    expect(entries).toEqual(expect.arrayContaining([
      expect.stringMatching(/roll=1 .* event=ROLL .* roll_points=0 .* available_hand_points=0/),
      expect.stringMatching(/roll=1 .* event=ACTION .* action=REROLL .* points=0/),
      expect.stringMatching(/roll=2 .* event=ROLL .* dice=\[4, 6\] .* roll_points=0/),
      expect.stringMatching(/roll=2 .* event=OUTCOME .* outcome=BUST .* points=0/),
    ]));
  });

  it("rejects actions from a player whose turn is not active", () => {
    const game = new TenkGame(players, straightRandom());
    expect(() => game.roll("two")).toThrowError("Wait for your turn");
  });

  it("shares manual dice selections without preselecting a suggested score", () => {
    const game = new TenkGame(players, straightRandom());
    game.roll("one");

    expect(game.snapshot()).toMatchObject({
      selectedIndices: [],
      displayTurnScore: 0,
      selection: "Select dice to lock before rerolling.",
    });

    game.setSelection("one", [0, 4]);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [0, 4],
      displayTurnScore: 150,
      selection: "2 selected • current hand score 150",
    });
    expect(() => game.keep("one", [0, 4])).toThrowError("Reach 1,000 this turn before banking");

    game.setSelection("one", [1]);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [1],
      displayTurnScore: 0,
      selection: "That selection is not a scoring or qualifying partial combination.",
    });
    expect(() => game.reroll("one", [1])).toThrowError("Select scoring dice");

    game.setSelection("one", []);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [],
      displayTurnScore: 0,
    });
    expect(() => game.setSelection("two", [0])).toThrowError("Wait for your turn");
  });

  it("requires exactly 10,000 and busts a turn that overshoots", () => {
    const overshootSnapshot = new TenkGame(players, straightRandom()).snapshot();
    overshootSnapshot.players[0].score = 9500;
    overshootSnapshot.players[0].onBoard = true;
    overshootSnapshot.turnScore = 550;
    overshootSnapshot.hotHandReady = true;
    const overshootGame = new TenkGame(players, straightRandom(), overshootSnapshot);

    overshootGame.keep("one", []);

    const overshootResult = overshootGame.snapshot();
    expect(overshootResult).toMatchObject({
      turnScore: 0,
      awaitingNextPlayer: false,
      currentPlayer: 1,
      gameOver: false,
      status: expect.stringContaining("over exactly 10,000"),
    });
    expect(overshootResult.players[0]).toMatchObject({ score: 9500, onBoard: true });
    expect(overshootResult.activity).toContainEqual(
      expect.stringMatching(/outcome=BUST .* points=0 .* points_lost=550/),
    );

    const exactSnapshot = new TenkGame(players, straightRandom()).snapshot();
    exactSnapshot.players[0].score = 9500;
    exactSnapshot.players[0].onBoard = true;
    exactSnapshot.turnScore = 500;
    exactSnapshot.hotHandReady = true;
    const exactGame = new TenkGame(players, straightRandom(), exactSnapshot);

    exactGame.keep("one", []);

    const exactResult = exactGame.snapshot();
    expect(exactResult).toMatchObject({
      gameOver: true,
      winnerId: "one",
    });
    expect(exactResult.players[0].score).toBe(10_000);
  });

  it("treats two locked 1s as a committed 1,000-point try through 9,000", () => {
    const dice = [1, 4, 5, 2, 4, 1, 5, 2, 4, 4];
    const game = gameAtScore(9000, diceSequenceRandom(dice));

    game.roll("one");
    game.reroll("one", [0, 5]);

    expect(game.snapshot()).toMatchObject({
      turnScore: 0,
      awaitingNextPlayer: false,
      currentPlayer: 1,
      status: "The attempt at three 1s missed the required third 1 — bust! Two, roll all six dice.",
    });
    expect(game.snapshot().players[0].score).toBe(9000);

    const overNineThousand = gameAtScore(9050, diceSequenceRandom(dice));
    overNineThousand.roll("one");
    overNineThousand.reroll("one", [0, 5]);
    expect(overNineThousand.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      selectedIndices: [],
      displayTurnScore: 200,
    });
    overNineThousand.setSelection("one", [1]);
    expect(overNineThousand.snapshot()).toMatchObject({
      selectedIndices: [1],
      displayTurnScore: 250,
    });
  });

  it("immediately busts an opening 1,000 above 9,000", () => {
    const openingThousand = [1, 1, 1, 2, 3, 4];
    const overshoot = gameAtScore(9050, diceSequenceRandom(openingThousand));
    overshoot.roll("one");
    expect(overshoot.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      status: "The opening roll scored 1,000, which would exceed exactly 10,000 — bust! Two, roll all six dice.",
    });
    expect(overshoot.snapshot().players[0].score).toBe(9050);

    const exact = gameAtScore(9000, diceSequenceRandom(openingThousand));
    exact.roll("one");
    expect(exact.snapshot().awaitingNextPlayer).toBe(false);
  });

  it("immediately busts an opening straight that would overshoot 10,000", () => {
    const game = gameAtScore(9600, straightRandom());

    game.roll("one");

    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      selectedIndices: [],
      turnScore: 0,
      status: "The opening roll scored 1,500, which would exceed exactly 10,000 — bust! Two, roll all six dice.",
    });
    expect(game.snapshot().players[0].score).toBe(9600);
    expect(game.snapshot().activity).toContainEqual(
      expect.stringMatching(/event=OUTCOME .* outcome=BUST .* points_lost=1500/),
    );
  });

  it("keeps carried 1s as singles above 9,000", () => {
    const dice = [1, 1, 5, 2, 4, 4, 6, 1, 6, 4];
    const game = gameAtScore(9600, diceSequenceRandom(dice));

    game.roll("one");
    game.reroll("one", [0, 1]);
    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      selectedIndices: [],
      displayTurnScore: 200,
    });
    game.setSelection("one", [3]);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [3],
      displayTurnScore: 300,
    });

    game.keep("one", [3]);
    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      turnScore: 0,
      status: "One banked 300 points. Two, roll all six dice.",
    });
    expect(game.snapshot().players[0].score).toBe(9900);
  });

  it("allows one non-scoring pair attempt to advance toward three of a kind", () => {
    const dice = [1, 5, 4, 6, 6, 5, 6, 2, 3, 4];
    const game = gameAtScore(5450, diceSequenceRandom(dice));

    game.roll("one");
    expect(() => game.reroll("one", [3, 4])).not.toThrow();
    expect(game.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      goForUsed: true,
      selectedIndices: [],
      displayTurnScore: 0,
    });
    game.setSelection("one", [0]);
    expect(game.snapshot()).toMatchObject({
      selectedIndices: [0],
      displayTurnScore: 600,
    });
    expect(game.snapshot().activity).toContainEqual(
      expect.stringMatching(/event=ACTION .* action=REROLL .* selected=\[6, 6\]/),
    );

    const missedPairDice = [1, 5, 4, 6, 6, 5, 2, 2, 3, 4];
    const missedPair = gameAtScore(5450, diceSequenceRandom(missedPairDice));
    missedPair.roll("one");
    missedPair.reroll("one", [3, 4]);
    expect(missedPair.snapshot()).toMatchObject({
      awaitingNextPlayer: false,
      currentPlayer: 1,
      turnScore: 0,
      status: "The rerolled dice did not score or advance a combination — bust! Two, roll all six dice.",
    });
  });

  it("accepts a newly rolled scoring triple with two matching dice already locked", () => {
    const dice = [5, 5, 2, 3, 4, 6, 5, 4, 5, 5, 1];
    const game = gameAtScore(1150, diceSequenceRandom(dice));

    game.roll("one");
    game.reroll("one", [0, 1]);
    expect(game.snapshot().selectedIndices).toEqual([]);
    game.setSelection("one", [2, 4, 5]);
    expect(game.snapshot().selectedIndices).toEqual([2, 4, 5]);
    expect(() => game.reroll("one", [2, 4, 5])).not.toThrow();
    expect(game.snapshot().activity).toContainEqual(
      expect.stringMatching(/event=ACTION .* action=REROLL .* selected=\[5, 5, 5\]/),
    );
  });

  it("busts when a new roll only matches an already-scored triple", () => {
    const dice = [2, 3, 6, 6, 6, 4, 4, 6, 3];
    const game = new TenkGame(players, diceSequenceRandom(dice));

    game.roll("one");
    game.reroll("one", [2, 3, 4]);

    expect(game.snapshot()).toMatchObject({
      turnScore: 0,
      awaitingNextPlayer: false,
      currentPlayer: 1,
      status: "The rerolled dice did not score or advance a combination — bust! Two, roll all six dice.",
    });
    expect(game.snapshot().activity).toContainEqual(
      expect.stringMatching(/event=ROLL .* dice=\[4, 6, 3\] .* available_hand_points=0/),
    );
    expect(game.snapshot().activity).toContainEqual(
      expect.stringMatching(/outcome=BUST .* points_lost=600/),
    );
  });
});
