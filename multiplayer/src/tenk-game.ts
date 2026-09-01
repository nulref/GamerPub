import { RoomCommandError } from "./room-state";
import type { TenkRoomPlayer } from "./tenk-room-state";
import {
  bestScoringSelection,
  canLockForReroll,
  scorePersistentHand,
  scoreSelection,
} from "./tenk-rules";

const WINNING_SCORE = 10_000;
const OPENING_SCORE = 1_000;

export interface TenkGamePlayer {
  id: string;
  name: string;
  score: number;
  onBoard: boolean;
  connected: boolean;
}

export interface TenkGameSnapshot {
  players: TenkGamePlayer[];
  currentPlayer: number;
  turnScore: number;
  displayTurnScore: number;
  diceToRoll: number;
  currentRoll: number[];
  lockedIndices: number[];
  lockedBatches: number[][];
  selectedIndices: number[];
  goForUsed: boolean;
  rescueMode: boolean;
  hotHandReady: boolean;
  awaitingNextPlayer: boolean;
  gameOver: boolean;
  winnerId: string | null;
  status: string;
  rollDetail: string;
  selection: string;
  activity: string[];
  rollNumber: number;
  revision: number;
}

export type TenkGameLogSink = (entry: string) => void;

function formatNumber(value: number): string {
  return value.toLocaleString("en-US");
}

export class TenkGame {
  private players: TenkGamePlayer[];
  private currentPlayer = 0;
  private turnScore = 0;
  private diceToRoll = 6;
  private currentRoll: number[] = [];
  private lockedIndices: number[] = [];
  private lockedBatches: number[][] = [];
  private selectedIndices: number[] = [];
  private goForUsed = false;
  private rescueMode = false;
  private hotHandReady = false;
  private awaitingNextPlayer = false;
  private gameOver = false;
  private winnerId: string | null = null;
  private status = "";
  private rollDetail = "Six dice are ready.";
  private selection = "Roll to begin.";
  private activity: string[] = [];
  private rollNumber = 0;
  private revision = 0;

  constructor(
    roomPlayers: readonly TenkRoomPlayer[],
    private readonly random: () => number = Math.random,
    snapshot?: TenkGameSnapshot | null,
    private readonly logSink: TenkGameLogSink = () => undefined,
  ) {
    if (snapshot) {
      this.players = snapshot.players.map((player) => ({ ...player }));
      this.currentPlayer = snapshot.currentPlayer;
      this.turnScore = snapshot.turnScore;
      this.diceToRoll = snapshot.diceToRoll;
      this.currentRoll = [...snapshot.currentRoll];
      this.lockedIndices = [...snapshot.lockedIndices];
      this.lockedBatches = snapshot.lockedBatches.map((batch) => [...batch]);
      this.selectedIndices = [...(snapshot.selectedIndices ?? [])];
      this.goForUsed = snapshot.goForUsed;
      this.rescueMode = snapshot.rescueMode;
      this.hotHandReady = snapshot.hotHandReady;
      this.awaitingNextPlayer = snapshot.awaitingNextPlayer;
      this.gameOver = snapshot.gameOver;
      this.winnerId = snapshot.winnerId;
      this.status = snapshot.status;
      this.rollDetail = snapshot.rollDetail;
      this.selection = snapshot.selection;
      this.activity = [...snapshot.activity];
      this.rollNumber = snapshot.rollNumber ?? 0;
      this.revision = snapshot.revision;
    } else {
      this.players = roomPlayers.map((player) => ({
        id: player.id,
        name: player.name,
        score: 0,
        onBoard: false,
        connected: player.connected,
      }));
      this.activity.push("New game: first to 10,000 wins.");
      this.audit("GAME_START", {
        players: `[${this.players.map((player) => player.name.replace(/[\r\n|]+/g, " ")).join(", ")}]`,
      });
      this.beginTurn();
    }
  }

  roll(userId: string): void {
    this.requireTurn(userId);
    if (this.awaitingNextPlayer) throw new RoomCommandError("next_player_required", "Advance to the next player.");
    if (!this.currentRoll.length || this.hotHandReady) {
      this.auditAction(this.hotHandReady ? "ROLL_HOT_DICE" : "ROLL", [], 0, 0, this.turnScore);
      this.hotHandReady = false;
      this.lockedIndices = [];
      this.lockedBatches = [];
      this.selectedIndices = [];
      this.currentRoll = this.randomDice(6);
      this.diceToRoll = 6;
      this.presentHand(this.turnScore === 0 && !this.goForUsed);
      this.touch();
      return;
    }
    throw new RoomCommandError("selection_required", "Select dice before rerolling.");
  }

  setSelection(userId: string, rawIndices: unknown): void {
    this.requireTurn(userId);
    if (this.awaitingNextPlayer || !this.currentRoll.length || this.hotHandReady) {
      throw new RoomCommandError("selection_unavailable", "Dice cannot be selected now.");
    }
    this.selectedIndices = this.selectedActiveIndices(rawIndices, true);
    this.updateSelectionSummary();
    this.touch();
  }

  reroll(userId: string, rawIndices: unknown): void {
    this.requireTurn(userId);
    if (this.awaitingNextPlayer || !this.currentRoll.length || this.hotHandReady) {
      throw new RoomCommandError("roll_unavailable", "The dice cannot be rerolled now.");
    }
    const selected = this.selectedActiveIndices(rawIndices, false);
    const selectedValues = this.valuesForIndices(selected);
    if (!this.canUseSelection(selectedValues)) {
      throw new RoomCommandError("invalid_selection", "Select scoring dice or a qualifying partial combination.");
    }
    if (selected.length === this.activeIndices().length) {
      const completed = this.scoreHand(selectedValues);
      if (!completed.valid || !completed.allScoring) {
        throw new RoomCommandError("invalid_selection", "All selected dice must complete a scoring hand.");
      }
    }

    const forcedThousandTry = this.isForcedThousandTry(selectedValues);
    const previousHandScore = this.scoreHand().score;
    const selectedHandScore = this.scoreHand(selectedValues).score;
    const selectedRollScore = bestScoringSelection(selectedValues).score;
    const consumesGoFor = selectedRollScore <= 0 && selectedHandScore <= previousHandScore;
    this.auditAction(
      "REROLL",
      selectedValues,
      Math.max(0, selectedHandScore - previousHandScore),
      selectedHandScore,
      this.turnScore + selectedHandScore,
    );

    this.lockedBatches.push([...selectedValues]);
    this.lockedIndices = [...new Set([...this.lockedIndices, ...selected])].sort((a, b) => a - b);
    this.selectedIndices = [];
    if (this.lockedIndices.length === 6) {
      const fullScore = this.scoreHand();
      if (!fullScore.valid || !fullScore.allScoring) {
        this.finishBust("The completed hand does not score — bust!");
      } else {
        this.turnScore += fullScore.score;
        this.diceToRoll = 6;
        this.hotHandReady = true;
        this.rescueMode = false;
        this.status = `${fullScore.label} — AND ROLLING!`;
        this.rollDetail = `All six dice scored for ${formatNumber(fullScore.score)}.`;
        this.selection = "Reroll all six dice, or keep it.";
        this.addActivity(`${this.current().name} completed the hand for ${fullScore.score} — and rolling.`);
      }
      this.touch();
      return;
    }

    if (this.rescueMode || consumesGoFor) {
      this.goForUsed = true;
      this.rescueMode = false;
    }
    const rerolledIndices = this.activeIndices();
    const rolledValues: number[] = [];
    for (const index of rerolledIndices) {
      this.currentRoll[index] = this.randomDie();
      rolledValues.push(this.currentRoll[index]);
    }
    this.diceToRoll = rerolledIndices.length;
    const missedThousandTry = forcedThousandTry && !rolledValues.includes(1);
    const candidate = missedThousandTry ? [] : this.bestLockCandidate();
    this.auditRoll(rolledValues, candidate);
    if (missedThousandTry) {
      this.rollDetail = `Rerolled [${rolledValues.join(", ")}]`;
      this.finishBust("The attempt at three 1s missed the required third 1 — bust!");
    } else if (!candidate.length) {
      this.rollDetail = `Rerolled [${rolledValues.join(", ")}]`;
      this.finishBust("The rerolled dice did not score or advance a combination — bust!");
    } else {
      this.status = "Select scoring dice or a qualifying partial combination, then reroll.";
      this.rollDetail = `Rerolled [${rolledValues.join(", ")}] • ${rerolledIndices.length} dice remain active`;
      this.selection = "Select dice to lock before rerolling.";
    }
    this.touch();
  }

  keep(userId: string, rawIndices: unknown): void {
    this.requireTurn(userId);
    if (this.awaitingNextPlayer) throw new RoomCommandError("next_player_required", "Advance to the next player.");
    const selected = this.selectedActiveIndices(rawIndices, this.hotHandReady);
    const handScore = this.currentHandScore(selected);
    const previousHandScore = this.scoreHand().score;
    if (!this.hotHandReady) {
      const selectedValues = this.valuesForIndices(selected);
      if (!this.canUseSelection(selectedValues) || handScore <= previousHandScore) {
        throw new RoomCommandError("invalid_selection", "Select at least one scoring die before keeping.");
      }
    }
    if (handScore > 0 && this.canBankScore(handScore)) {
      this.auditAction(
        "KEEP",
        this.valuesForIndices(selected),
        Math.max(0, handScore - previousHandScore),
        handScore,
        this.turnScore + handScore,
      );
      this.turnScore += handScore;
      this.addActivity(`${this.current().name} kept the hand for ${handScore}.`);
      this.finishScoringTurn("Kept it");
    } else if (this.canBank()) {
      this.auditAction("KEEP", this.valuesForIndices(selected), 0, handScore, this.turnScore);
      this.finishScoringTurn("Kept it");
    } else {
      throw new RoomCommandError("bank_unavailable", "Reach 1,000 this turn before banking.");
    }
    this.touch();
  }

  nextPlayer(userId: string): void {
    this.requireTurn(userId);
    if (!this.awaitingNextPlayer) throw new RoomCommandError("turn_active", "Finish the current turn first.");
    this.auditAction("NEXT_PLAYER", [], 0, 0, 0);
    this.currentPlayer = (this.currentPlayer + 1) % this.players.length;
    this.beginTurn();
    this.touch();
  }

  updateConnection(userId: string, connected: boolean, name?: string): void {
    const player = this.players.find((candidate) => candidate.id === userId);
    if (!player) return;
    player.connected = connected;
    if (name?.trim()) player.name = name.trim().replace(/\s+/g, " ").slice(0, 32);
    this.touch();
  }

  snapshot(): TenkGameSnapshot {
    const selectedScore = this.currentHandScore(this.selectedIndices);
    return {
      players: this.players.map((player) => ({ ...player })),
      currentPlayer: this.currentPlayer,
      turnScore: this.turnScore,
      displayTurnScore: this.turnScore + selectedScore,
      diceToRoll: this.diceToRoll,
      currentRoll: [...this.currentRoll],
      lockedIndices: [...this.lockedIndices],
      lockedBatches: this.lockedBatches.map((batch) => [...batch]),
      selectedIndices: [...this.selectedIndices],
      goForUsed: this.goForUsed,
      rescueMode: this.rescueMode,
      hotHandReady: this.hotHandReady,
      awaitingNextPlayer: this.awaitingNextPlayer,
      gameOver: this.gameOver,
      winnerId: this.winnerId,
      status: this.status,
      rollDetail: this.rollDetail,
      selection: this.selection,
      activity: [...this.activity],
      rollNumber: this.rollNumber,
      revision: this.revision,
    };
  }

  private beginTurn(handoffMessage = ""): void {
    this.turnScore = 0;
    this.diceToRoll = 6;
    this.currentRoll = [];
    this.lockedIndices = [];
    this.lockedBatches = [];
    this.selectedIndices = [];
    this.goForUsed = false;
    this.rescueMode = false;
    this.hotHandReady = false;
    this.awaitingNextPlayer = false;
    const nextTurnMessage = `${this.current().name}, roll all six dice.`;
    this.status = handoffMessage.trim()
      ? `${handoffMessage.trim()} ${nextTurnMessage}`
      : nextTurnMessage;
    this.rollDetail = "Six dice are ready.";
    this.selection = "Roll to begin.";
    this.addActivity(`${this.current().name}'s turn`);
    this.audit("TURN_START", { turn_points: 0, total_score: this.current().score });
  }

  private presentHand(openingRoll: boolean): void {
    const best = bestScoringSelection(this.currentRoll);
    this.rescueMode = openingRoll && best.score <= 0;
    const candidate = this.bestLockCandidate();
    this.selectedIndices = [];
    this.auditRoll(this.currentRoll, candidate);
    const forcedProjectedScore = this.current().score + this.turnScore + best.score;
    if (best.score >= 1000 && forcedProjectedScore > WINNING_SCORE) {
      this.rollDetail = `Rolled: [${this.currentRoll.join(", ")}]`;
      this.finishBust(
        `The ${openingRoll ? "opening " : ""}roll scored ${formatNumber(best.score)}, ` +
          "which would exceed exactly 10,000 — bust!",
        this.turnScore + best.score,
      );
      return;
    }
    if (!candidate.length) {
      this.finishBust("No scoring dice or qualifying partial combination — bust!");
      return;
    }
    this.rollDetail = `Rolled: [${this.currentRoll.join(", ")}]`;
    this.status = this.rescueMode
      ? "No score. Use the turn's one rescue reroll with a qualifying partial combination."
      : "Select dice to lock, then reroll every unselected die.";
    this.selection = "Select dice to lock before rerolling.";
  }

  private updateSelectionSummary(): void {
    const selectedValues = this.valuesForIndices(this.selectedIndices);
    if (!selectedValues.length) {
      this.selection = "Select dice to lock before rerolling.";
      return;
    }
    if (this.canUseSelection(selectedValues)) {
      this.selection = `${selectedValues.length} selected • current hand score ${formatNumber(this.currentHandScore(this.selectedIndices))}`;
      return;
    }
    this.selection = "That selection is not a scoring or qualifying partial combination.";
  }

  private finishScoringTurn(reason: string): void {
    const player = this.current();
    const earned = this.turnScore;
    if (this.canBank()) {
      const projectedScore = player.score + earned;
      if (projectedScore > WINNING_SCORE) {
        this.finishBust(
          `${player.name} would reach ${formatNumber(projectedScore)}, which is over exactly 10,000 — bust!`,
          earned,
        );
        return;
      }
      player.score = projectedScore;
      player.onBoard = true;
      this.audit("OUTCOME", { outcome: "BANKED", points: earned, total_score: player.score });
      this.status = `${reason} — ${player.name} banked ${earned} points.`;
      this.addActivity(`${player.name} banked ${earned} (total ${player.score}).`);
      if (player.score >= WINNING_SCORE) {
        this.gameOver = true;
        this.awaitingNextPlayer = false;
        this.winnerId = player.id;
        this.addActivity(`${player.name} WINS!`);
        return;
      }
      this.advanceToNextPlayer(`${player.name} banked ${earned} points.`);
    } else {
      this.audit("OUTCOME", { outcome: "NOT_BANKED", points: earned, banked_points: 0 });
      this.status = `${reason}, but ${player.name} needed 1,000 to get on the board. No points banked.`;
      this.addActivity(`${player.name} scored ${earned} but did not reach the opening requirement.`);
      this.advanceToNextPlayer(`${player.name}'s ${earned} points were not banked.`);
    }
  }

  private finishBust(message: string, lostOverride?: number): void {
    const lost = lostOverride ?? this.turnScore + this.scoreHand().score;
    const bustedPlayerName = this.current().name;
    this.audit("OUTCOME", { outcome: "BUST", points: 0, points_lost: lost });
    this.addActivity(message);
    this.addActivity(`${bustedPlayerName} busted and lost ${lost}.`);
    this.advanceToNextPlayer(message);
  }

  private advanceToNextPlayer(handoffMessage: string): void {
    this.auditAction("AUTO_NEXT_PLAYER", [], 0, 0, 0);
    this.currentPlayer = (this.currentPlayer + 1) % this.players.length;
    this.beginTurn(handoffMessage);
  }

  private bestLockCandidate(): number[] {
    const active = this.activeIndices();
    let best: number[] = [];
    let bestPriority = -1000;
    for (let mask = 1; mask < (1 << active.length); mask += 1) {
      const candidate = active.filter((_index, offset) => (mask & (1 << offset)) !== 0);
      const values = this.valuesForIndices(candidate);
      if (!this.canUseSelection(values)) continue;
      const exact = scoreSelection(values);
      const combined = this.scoreHand(values);
      if (candidate.length === active.length && !combined.allScoring) continue;
      let priority = -candidate.length;
      if (exact.valid) priority += 10_000 + exact.score;
      if (combined.valid) priority += 100_000 + combined.score;
      if (priority > bestPriority) {
        bestPriority = priority;
        best = candidate;
      }
    }
    return best;
  }

  private isForcedThousandTry(selectedValues: readonly number[]): boolean {
    return this.current().score <= 9000 && selectedValues.filter((value) => value === 1).length === 2;
  }

  private scoreHand(selectedValues: readonly number[] = []): ReturnType<typeof scorePersistentHand> {
    return scorePersistentHand(this.lockedBatches, selectedValues, this.current().score <= 9000);
  }

  private canUseSelection(selectedValues: readonly number[]): boolean {
    if (!canLockForReroll(this.lockedValues(), selectedValues)) return false;
    if (!this.goForUsed || bestScoringSelection(selectedValues).score > 0) return true;
    return this.scoreHand(selectedValues).score > this.scoreHand().score;
  }

  private selectedActiveIndices(rawIndices: unknown, allowEmpty: boolean): number[] {
    if (!Array.isArray(rawIndices)) throw new RoomCommandError("invalid_selection", "Dice selection is invalid.");
    const active = new Set(this.activeIndices());
    const selected: number[] = [];
    for (const rawIndex of rawIndices) {
      if (!Number.isInteger(rawIndex) || !active.has(rawIndex) || selected.includes(rawIndex)) {
        throw new RoomCommandError("invalid_selection", "Dice selection is invalid.");
      }
      selected.push(rawIndex);
    }
    if (!allowEmpty && !selected.length) {
      throw new RoomCommandError("invalid_selection", "Select at least one die.");
    }
    return selected.sort((left, right) => left - right);
  }

  private currentHandScore(selected: readonly number[]): number {
    if (this.hotHandReady) return 0;
    return this.scoreHand(this.valuesForIndices(selected)).score;
  }

  private canBank(): boolean {
    return this.turnScore > 0 && (this.current().onBoard || this.turnScore >= OPENING_SCORE);
  }

  private canBankScore(additionalScore: number): boolean {
    return additionalScore > 0 &&
      (this.current().onBoard || this.turnScore + additionalScore >= OPENING_SCORE);
  }

  private activeIndices(): number[] {
    return this.currentRoll.map((_die, index) => index).filter((index) => !this.lockedIndices.includes(index));
  }

  private lockedValues(): number[] {
    return this.valuesForIndices(this.lockedIndices);
  }

  private valuesForIndices(indices: readonly number[]): number[] {
    return indices.map((index) => this.currentRoll[index]);
  }

  private requireTurn(userId: string): void {
    if (this.gameOver) throw new RoomCommandError("game_over", "This Tenk game is over.");
    if (this.current().id !== userId) throw new RoomCommandError("not_your_turn", "Wait for your turn.");
    if (!this.current().connected) throw new RoomCommandError("player_disconnected", "Reconnect before acting.");
  }

  private current(): TenkGamePlayer {
    return this.players[this.currentPlayer];
  }

  private randomDie(): number {
    return Math.floor(this.random() * 6) + 1;
  }

  private randomDice(count: number): number[] {
    return Array.from({ length: count }, () => this.randomDie());
  }

  private addActivity(message: string): void {
    this.activity.push(message);
    if (this.activity.length > 500) this.activity.splice(0, this.activity.length - 500);
  }

  private auditRoll(rolledDice: readonly number[], suggested: readonly number[]): void {
    this.rollNumber += 1;
    const availableHandPoints = suggested.length
      ? this.scoreHand(this.valuesForIndices(suggested)).score
      : 0;
    this.audit("ROLL", {
      dice: `[${rolledDice.join(", ")}]`,
      locked: `[${this.lockedValues().join(", ")}]`,
      roll_points: bestScoringSelection(rolledDice).score,
      available_hand_points: availableHandPoints,
      turn_points: this.turnScore + availableHandPoints,
    });
  }

  private auditAction(
    action: string,
    selectedDice: readonly number[],
    points: number,
    handPoints: number,
    turnPoints: number,
  ): void {
    this.audit("ACTION", {
      action,
      selected: `[${selectedDice.join(", ")}]`,
      points,
      hand_points: handPoints,
      turn_points: turnPoints,
    });
  }

  private audit(event: string, fields: Record<string, string | number | boolean>): void {
    const details = Object.entries(fields).map(([key, value]) => `${key}=${value}`);
    const entry = [
      new Date().toISOString(),
      `roll=${this.rollNumber}`,
      `player=${this.current().name.replace(/[\r\n|]+/g, " ")}`,
      `event=${event}`,
      ...details,
    ].join(" | ");
    this.addActivity(entry);
    this.logSink(entry);
  }

  private touch(): void {
    this.revision += 1;
  }
}
