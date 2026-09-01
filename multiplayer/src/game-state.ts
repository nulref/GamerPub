import { RoomCommandError, type RoomPlayer } from "./room-state";

export const GAME_WORD = "JOKER";
export const CARD_IDS = [
  "spade_ace",
  "spade_two",
  "spade_three",
  "spade_four",
  "heart_ace",
  "heart_two",
  "heart_three",
  "heart_four",
  "club_ace",
  "club_two",
  "club_three",
  "club_four",
  "diamond_ace",
  "diamond_two",
  "diamond_three",
  "diamond_four",
  "joker",
] as const;

export type GamePhase = "passing" | "slapping" | "round_result" | "game_over";
export type Combo = "four_of_a_kind" | "three_with_joker" | "four_with_joker";

export interface MatchPlayer {
  id: string;
  name: string;
  isBot: boolean;
  connected: boolean;
  hand: string[];
  letters: number;
}

export interface RoundResult {
  winner: number;
  combo: Combo;
  slapOrder: number[];
  penalized: number[];
}

export interface MatchStorageSnapshot {
  phase: GamePhase;
  players: MatchPlayer[];
  roundNumber: number;
  activeSeat: number;
  slapOrder: number[];
  winningSeat: number | null;
  winningCombo: Combo | null;
  result: RoundResult | null;
  revision: number;
  lastEvent: Record<string, unknown> | null;
  botSpeedScale?: number;
}

export interface PublicMatchSnapshot {
  phase: GamePhase;
  players: Array<Omit<MatchPlayer, "hand"> & { cardCount: number }>;
  roundNumber: number;
  activeSeat: number;
  slapOrder: number[];
  winningSeat: number | null;
  winningCombo: Combo | null;
  result: RoundResult | null;
  revision: number;
  lastEvent: Record<string, unknown> | null;
  localSeat: number;
  hand: string[];
  botSpeedScale: number;
}

function cardRank(cardId: string): string {
  return cardId === "joker" ? cardId : cardId.slice(cardId.indexOf("_") + 1);
}

export function evaluateHand(hand: string[]): Combo | null {
  const jokerCount = hand.filter((card) => card === "joker").length;
  const counts = new Map<string, number>();
  for (const card of hand) {
    if (card === "joker") continue;
    const rank = cardRank(card);
    counts.set(rank, (counts.get(rank) ?? 0) + 1);
  }
  const largestGroup = Math.max(0, ...counts.values());
  // The player who just received a card temporarily holds five cards. A
  // completed four-card set is immediately valid inside that hand; they do
  // not need to pass the unrelated fifth card before slapping.
  if (jokerCount >= 1 && largestGroup >= 4) return "four_with_joker";
  if (jokerCount >= 1 && largestGroup >= 3) return "three_with_joker";
  if (largestGroup >= 4) return "four_of_a_kind";
  return null;
}

function normalizeBotSpeedScale(value: number): number {
  return Number.isFinite(value) ? Math.min(1.6, Math.max(0.65, value)) : 1;
}

function clonePlayer(player: MatchPlayer): MatchPlayer {
  return { ...player, hand: [...player.hand] };
}

export class MultiplayerGame {
  private phase: GamePhase = "passing";
  private players: MatchPlayer[];
  private roundNumber = 0;
  private activeSeat = 0;
  private slapOrder: number[] = [];
  private winningSeat: number | null = null;
  private winningCombo: Combo | null = null;
  private result: RoundResult | null = null;
  private revision = 0;
  private lastEvent: Record<string, unknown> | null = null;
  private botSpeedScale = 1;

  constructor(
    players: RoomPlayer[],
    private readonly random: () => number = Math.random,
    stored?: MatchStorageSnapshot,
    botSpeedScale = 1,
  ) {
    this.players = players.map((player) => ({
      id: player.id,
      name: player.name,
      isBot: player.isBot,
      connected: player.connected,
      hand: [],
      letters: 0,
    }));
    if (stored) {
      this.phase = stored.phase;
      this.players = stored.players.map(clonePlayer);
      this.roundNumber = stored.roundNumber;
      this.activeSeat = stored.activeSeat;
      this.slapOrder = [...stored.slapOrder];
      this.winningSeat = stored.winningSeat;
      this.winningCombo = stored.winningCombo;
      this.result = stored.result ? { ...stored.result, slapOrder: [...stored.result.slapOrder], penalized: [...stored.result.penalized] } : null;
      this.revision = stored.revision;
      this.lastEvent = stored.lastEvent ? { ...stored.lastEvent } : null;
      this.botSpeedScale = normalizeBotSpeedScale(stored.botSpeedScale ?? botSpeedScale);
      return;
    }
    this.botSpeedScale = normalizeBotSpeedScale(botSpeedScale);
    this.startNewGame();
  }

  storageSnapshot(): MatchStorageSnapshot {
    return {
      phase: this.phase,
      players: this.players.map(clonePlayer),
      roundNumber: this.roundNumber,
      activeSeat: this.activeSeat,
      slapOrder: [...this.slapOrder],
      winningSeat: this.winningSeat,
      winningCombo: this.winningCombo,
      result: this.result ? { ...this.result, slapOrder: [...this.result.slapOrder], penalized: [...this.result.penalized] } : null,
      revision: this.revision,
      lastEvent: this.lastEvent ? { ...this.lastEvent } : null,
      botSpeedScale: this.botSpeedScale,
    };
  }

  publicSnapshot(userId: string): PublicMatchSnapshot {
    const localSeat = this.requireSeat(userId);
    return {
      phase: this.phase,
      players: this.players.map(({ hand, ...player }) => ({ ...player, cardCount: hand.length })),
      roundNumber: this.roundNumber,
      activeSeat: this.activeSeat,
      slapOrder: [...this.slapOrder],
      winningSeat: this.winningSeat,
      winningCombo: this.winningCombo,
      result: this.result ? { ...this.result, slapOrder: [...this.result.slapOrder], penalized: [...this.result.penalized] } : null,
      revision: this.revision,
      lastEvent: this.lastEvent ? { ...this.lastEvent } : null,
      localSeat,
      hand: [...this.players[localSeat].hand],
      botSpeedScale: this.botSpeedScale,
    };
  }

  passCard(userId: string, cardIndex: number): void {
    if (this.phase !== "passing") throw new RoomCommandError("not_passing", "Cards cannot be passed right now.");
    const seat = this.requireSeat(userId);
    if (seat !== this.activeSeat) throw new RoomCommandError("not_your_turn", "Wait for your turn to pass.");
    if (!Number.isInteger(cardIndex) || cardIndex < 0 || cardIndex >= this.players[seat].hand.length) {
      throw new RoomCommandError("invalid_card", "Choose a card from your hand.");
    }
    this.transferCard(seat, cardIndex);
  }

  setBotSpeedScale(value: number): void {
    this.botSpeedScale = normalizeBotSpeedScale(value);
    this.touch({ type: "bot_speed_changed", botSpeedScale: this.botSpeedScale });
  }

  nextAutomationDelayMs(): number | null {
    if (this.phase === "passing") {
      const completed = this.findCompletedSeat();
      if (completed >= 0) {
        const player = this.players[completed];
        if (!player.isBot && player.connected) return null;
        return this.randomDelay(320, 720);
      }
      const player = this.players[this.activeSeat];
      if (!player.isBot && player.connected) return null;
      return this.randomDelay(420, 820);
    }
    if (this.phase === "slapping" && this.automatedSlapSeats().length > 0) {
      return this.randomDelay(300, 1250);
    }
    return null;
  }

  performAutomatedAction(): boolean {
    if (this.phase === "passing") {
      const completed = this.findCompletedSeat();
      if (completed >= 0) {
        const player = this.players[completed];
        if (!player.isBot && player.connected) return false;
        this.beginSlap(completed, evaluateHand(player.hand)!);
        return true;
      }
      const player = this.players[this.activeSeat];
      if (!player.isBot && player.connected) return false;
      this.transferCard(this.activeSeat, this.chooseBotCard(this.activeSeat));
      return true;
    }
    if (this.phase === "slapping") {
      const seats = this.automatedSlapSeats();
      if (seats.length === 0) return false;
      this.registerSlap(seats[Math.floor(this.random() * seats.length)]);
      return true;
    }
    return false;
  }

  slap(userId: string): void {
    const seat = this.requireSeat(userId);
    if (this.phase === "passing") {
      const combo = evaluateHand(this.players[seat].hand);
      if (!combo) throw new RoomCommandError("no_combo", "You do not have a complete set yet.");
      this.beginSlap(seat, combo);
      return;
    }
    if (this.phase !== "slapping") throw new RoomCommandError("not_slapping", "There is nothing to slap right now.");
    this.registerSlap(seat);
  }

  advanceRound(userId: string): void {
    this.requireSeat(userId);
    if (this.phase === "round_result") {
      this.startRound();
      return;
    }
    if (this.phase === "game_over") {
      this.startNewGame();
      return;
    }
    throw new RoomCommandError("round_active", "The current round is still active.");
  }

  updateConnection(userId: string, connected: boolean, name?: string): void {
    const seat = this.players.findIndex((player) => player.id === userId);
    if (seat < 0) return;
    this.players[seat].connected = connected;
    if (name?.trim()) this.players[seat].name = name.trim().slice(0, 32);
    if (!connected && this.phase === "slapping" && !this.slapOrder.includes(seat)) {
      this.registerSlap(seat);
    } else {
      this.touch({ type: connected ? "reconnected" : "disconnected", seat });
    }
  }

  private startNewGame(): void {
    for (const player of this.players) player.letters = 0;
    this.roundNumber = 0;
    this.startRound();
  }

  private startRound(): void {
    this.roundNumber += 1;
    this.slapOrder = [];
    this.winningSeat = null;
    this.winningCombo = null;
    this.result = null;
    for (const player of this.players) player.hand = [];

    const deck = [...CARD_IDS];
    for (let index = deck.length - 1; index > 0; index -= 1) {
      const other = Math.floor(this.random() * (index + 1));
      [deck[index], deck[other]] = [deck[other], deck[index]];
    }
    this.activeSeat = Math.floor(this.random() * this.players.length);
    for (let cardNumber = 0; cardNumber < 4; cardNumber += 1) {
      for (const player of this.players) player.hand.push(deck.pop()!);
    }
    this.players[this.activeSeat].hand.push(deck.pop()!);
    this.phase = "passing";
    this.touch({ type: "round_started", seat: this.activeSeat });
  }

  private transferCard(fromSeat: number, cardIndex: number): void {
    const toSeat = (fromSeat + 1) % this.players.length;
    const [card] = this.players[fromSeat].hand.splice(cardIndex, 1);
    this.players[toSeat].hand.push(card);
    this.activeSeat = toSeat;
    this.touch({ type: "card_passed", fromSeat, toSeat });
  }

  private chooseBotCard(seat: number): number {
    const hand = this.players[seat].hand;
    const counts = new Map<string, number>();
    for (const card of hand) {
      if (card !== "joker") counts.set(cardRank(card), (counts.get(cardRank(card)) ?? 0) + 1);
    }
    let smallest = Number.POSITIVE_INFINITY;
    let choices: number[] = [];
    hand.forEach((card, index) => {
      if (card === "joker") return;
      const count = counts.get(cardRank(card)) ?? 0;
      if (count < smallest) {
        smallest = count;
        choices = [index];
      } else if (count === smallest) {
        choices.push(index);
      }
    });
    return choices.length ? choices[Math.floor(this.random() * choices.length)] : 0;
  }

  private findCompletedSeat(): number {
    for (let offset = 0; offset < this.players.length; offset += 1) {
      const seat = (this.activeSeat + offset) % this.players.length;
      if (evaluateHand(this.players[seat].hand)) return seat;
    }
    return -1;
  }

  private beginSlap(seat: number, combo: Combo): void {
    this.phase = "slapping";
    this.winningSeat = seat;
    this.winningCombo = combo;
    this.slapOrder = [];
    this.registerSlap(seat);
  }

  private automatedSlapSeats(): number[] {
    return this.players
      .map((player, seat) => ({ player, seat }))
      .filter(({ player, seat }) => (player.isBot || !player.connected) && !this.slapOrder.includes(seat))
      .map(({ seat }) => seat);
  }

  private randomDelay(minimumMs: number, maximumMs: number): number {
    const duration = minimumMs + this.random() * (maximumMs - minimumMs);
    return Math.max(100, Math.round(duration / this.botSpeedScale));
  }

  private registerSlap(seat: number): void {
    if (this.phase !== "slapping" || this.slapOrder.includes(seat)) return;
    this.slapOrder.push(seat);
    this.touch({ type: "slap", seat, place: this.slapOrder.length });
    if (this.slapOrder.length === this.players.length) this.resolveRound();
  }

  private resolveRound(): void {
    if (this.winningSeat === null || this.winningCombo === null) return;
    let penalized: number[];
    if (this.winningCombo === "four_of_a_kind") {
      penalized = [this.slapOrder.at(-1)!];
    } else if (this.winningCombo === "three_with_joker") {
      penalized = this.slapOrder.slice(-2);
    } else {
      penalized = this.players.map((_, seat) => seat).filter((seat) => seat !== this.winningSeat);
    }
    for (const seat of penalized) this.players[seat].letters += 1;
    this.result = {
      winner: this.winningSeat,
      combo: this.winningCombo,
      slapOrder: [...this.slapOrder],
      penalized,
    };
    this.phase = this.players.some((player) => player.letters >= GAME_WORD.length) ? "game_over" : "round_result";
    this.touch({ type: "round_ended" });
  }

  private requireSeat(userId: string): number {
    const seat = this.players.findIndex((player) => player.id === userId);
    if (seat < 0 || this.players[seat].isBot) {
      throw new RoomCommandError("not_in_game", "You are not seated in this game.");
    }
    return seat;
  }

  private touch(event: Record<string, unknown>): void {
    this.revision += 1;
    this.lastEvent = event;
  }
}
