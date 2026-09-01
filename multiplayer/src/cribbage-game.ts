import { RoomCommandError } from "./room-state";
import type { CribbageRoomPlayer } from "./cribbage-room-state";
import {
  type CribbageCard,
  type CribbageMode,
  CRIBBAGE_WINNING_SCORE,
  cribbageCardValue,
  cribbageDealPlan,
  cribbageDeck,
  cribbageTeam,
  scoreCribbageHand,
  scoreCribbagePeg,
} from "./cribbage-rules";

interface CribbagePlayer {
  id: string;
  name: string;
  team: number;
  connected: boolean;
}

interface CribbagePlay {
  player: number;
  card: CribbageCard;
  count: number;
  points: number;
}

interface CribbageShowItem {
  kind: "hand" | "crib";
  player: number;
  name: string;
  cards: CribbageCard[];
  points: number;
  detail: string;
}

export interface CribbageGameSnapshot {
  mode: CribbageMode;
  players: CribbagePlayer[];
  teamScores: Record<string, number>;
  dealer: number;
  activePlayer: number;
  phase: "discarding" | "pegging" | "show" | "game_over";
  hands: CribbageCard[][];
  keptHands: CribbageCard[][];
  crib: CribbageCard[];
  starter: CribbageCard | null;
  requiredDiscards: number[];
  discarded: boolean[];
  cutDeck: CribbageCard[];
  pegSequence: CribbageCard[];
  pegTotal: number;
  playHistory: CribbagePlay[];
  showItems: CribbageShowItem[];
  status: string;
  winnerTeam: number;
  dealNumber: number;
  revision: number;
}

export class CribbageGame {
  private mode: CribbageMode;
  private players: CribbagePlayer[];
  private teamScores: Record<string, number> = {};
  private dealer = 0;
  private activePlayer = -1;
  private phase: CribbageGameSnapshot["phase"] = "discarding";
  private hands: CribbageCard[][] = [];
  private keptHands: CribbageCard[][] = [];
  private crib: CribbageCard[] = [];
  private starter: CribbageCard | null = null;
  private requiredDiscards: number[] = [];
  private discarded: boolean[] = [];
  private cutDeck: CribbageCard[] = [];
  private pegSequence: CribbageCard[] = [];
  private pegTotal = 0;
  private playHistory: CribbagePlay[] = [];
  private showItems: CribbageShowItem[] = [];
  private status = "";
  private winnerTeam = -1;
  private dealNumber = 0;
  private revision = 0;

  constructor(
    roomPlayers: CribbageRoomPlayer[],
    mode: CribbageMode,
    private readonly random: () => number = Math.random,
    snapshot?: CribbageGameSnapshot | null,
  ) {
    this.mode = mode;
    this.players = roomPlayers.map((player, index) => ({
      id: player.id,
      name: player.name,
      team: cribbageTeam(mode, roomPlayers.length, index),
      connected: player.connected,
    }));
    if (snapshot) {
      this.restore(snapshot);
      return;
    }
    this.players.forEach((player) => { this.teamScores[player.team] = 0; });
    this.dealer = Math.floor(this.random() * this.players.length);
    this.deal();
  }

  discard(userId: string, rawIndices: unknown): void {
    this.requirePhase("discarding");
    const player = this.playerIndex(userId);
    if (this.discarded[player]) throw new RoomCommandError("already_discarded", "Your crib cards are already set.");
    if (!Array.isArray(rawIndices) || rawIndices.some((value) => !Number.isInteger(value))) {
      throw new RoomCommandError("invalid_cards", "Choose cards from your hand.");
    }
    const indices = [...new Set(rawIndices as number[])].sort((left, right) => right - left);
    if (indices.length !== this.requiredDiscards[player] ||
        indices.some((index) => index < 0 || index >= this.hands[player].length)) {
      throw new RoomCommandError("invalid_discard", `Choose exactly ${this.requiredDiscards[player]} card(s).`);
    }
    for (const index of indices) this.crib.push(this.hands[player].splice(index, 1)[0]);
    this.discarded[player] = true;
    this.status = `${this.players[player].name} is ready for the cut.`;
    this.touch();
    if (this.discarded.every(Boolean)) this.startPegging();
  }

  playCard(userId: string, cardIndex: unknown): void {
    this.requirePhase("pegging");
    const player = this.playerIndex(userId);
    if (player !== this.activePlayer) throw new RoomCommandError("not_your_turn", "Wait for your turn to peg.");
    if (!Number.isInteger(cardIndex) || (cardIndex as number) < 0 ||
        (cardIndex as number) >= this.hands[player].length) {
      throw new RoomCommandError("invalid_card", "Choose a card from your hand.");
    }
    const card = this.hands[player][cardIndex as number];
    if (this.pegTotal + cribbageCardValue(card) > 31) {
      throw new RoomCommandError("over_31", "That card would take the count over 31.");
    }
    this.hands[player].splice(cardIndex as number, 1);
    this.pegSequence.push(card);
    this.pegTotal += cribbageCardValue(card);
    const points = scoreCribbagePeg(this.pegSequence, this.pegTotal);
    this.playHistory.push({ player, card, count: this.pegTotal, points });
    if (points && this.award(this.players[player].team, points)) return;

    if (this.hands.every((hand) => hand.length === 0)) {
      if (this.pegTotal !== 31 && this.award(this.players[player].team, 1)) return;
      this.finishPegging();
      return;
    }
    if (this.pegTotal === 31) {
      this.resetPegSequence();
      this.activePlayer = this.nextPlayerWithCards(player);
    } else {
      const next = this.nextLegalPlayer(player);
      if (next < 0) {
        if (this.award(this.players[player].team, 1)) return;
        this.resetPegSequence();
        this.activePlayer = this.nextPlayerWithCards(player);
      } else {
        this.activePlayer = next;
      }
    }
    this.status = `${this.players[this.activePlayer].name} to play — count is ${this.pegTotal}.`;
    this.touch();
  }

  nextDeal(): void {
    this.requirePhase("show");
    this.dealer = (this.dealer + 1) % this.players.length;
    this.deal();
  }

  updateConnection(userId: string, connected: boolean, name?: string): void {
    const player = this.players.find((candidate) => candidate.id === userId);
    if (!player) return;
    player.connected = connected;
    if (name?.trim()) player.name = name.trim().replace(/\s+/g, " ").slice(0, 32);
    this.touch();
  }

  publicSnapshot(userId: string) {
    const selfIndex = this.playerIndex(userId);
    const shownHand = this.phase === "show" || this.phase === "game_over"
      ? this.keptHands[selfIndex]
      : this.hands[selfIndex];
    return {
      mode: this.mode,
      playerCount: this.players.length,
      players: this.players.map((player, index) => ({
        ...player,
        score: this.teamScores[player.team] ?? 0,
        cardCount: this.hands[index].length,
      })),
      selfIndex,
      dealer: this.dealer,
      activePlayer: this.activePlayer,
      phase: this.phase,
      hand: shownHand.map((card) => ({ ...card })),
      starter: this.starter ? { ...this.starter } : {},
      cribCount: this.crib.length,
      pegTotal: this.pegTotal,
      playHistory: this.playHistory.map((play) => ({ ...play, card: { ...play.card } })),
      showItems: this.showItems.map((item) => ({
        ...item,
        cards: item.cards.map((card) => ({ ...card })),
      })),
      requiredDiscard: this.requiredDiscards[selfIndex],
      discarded: this.discarded[selfIndex],
      status: this.status,
      winnerTeam: this.winnerTeam,
      dealNumber: this.dealNumber,
      revision: this.revision,
    };
  }

  snapshot(): CribbageGameSnapshot {
    return {
      mode: this.mode,
      players: this.players.map((player) => ({ ...player })),
      teamScores: { ...this.teamScores },
      dealer: this.dealer,
      activePlayer: this.activePlayer,
      phase: this.phase,
      hands: this.hands.map((hand) => hand.map((card) => ({ ...card }))),
      keptHands: this.keptHands.map((hand) => hand.map((card) => ({ ...card }))),
      crib: this.crib.map((card) => ({ ...card })),
      starter: this.starter ? { ...this.starter } : null,
      requiredDiscards: [...this.requiredDiscards],
      discarded: [...this.discarded],
      cutDeck: this.cutDeck.map((card) => ({ ...card })),
      pegSequence: this.pegSequence.map((card) => ({ ...card })),
      pegTotal: this.pegTotal,
      playHistory: this.playHistory.map((play) => ({ ...play, card: { ...play.card } })),
      showItems: this.showItems.map((item) => ({ ...item, cards: item.cards.map((card) => ({ ...card })) })),
      status: this.status,
      winnerTeam: this.winnerTeam,
      dealNumber: this.dealNumber,
      revision: this.revision,
    };
  }

  private deal(): void {
    this.dealNumber += 1;
    this.phase = "discarding";
    this.hands = Array.from({ length: this.players.length }, () => []);
    this.keptHands = Array.from({ length: this.players.length }, () => []);
    this.crib = [];
    this.starter = null;
    this.pegSequence = [];
    this.pegTotal = 0;
    this.playHistory = [];
    this.showItems = [];
    this.activePlayer = -1;
    const plan = cribbageDealPlan(this.mode, this.players.length, this.dealer);
    this.requiredDiscards = [...plan.discards];
    this.discarded = plan.discards.map((count) => count === 0);
    this.cutDeck = this.shuffle(cribbageDeck());
    let remaining = plan.dealt.reduce((sum, count) => sum + count, 0);
    let seat = (this.dealer + 1) % this.players.length;
    while (remaining > 0) {
      if (this.hands[seat].length < plan.dealt[seat]) {
        this.hands[seat].push(this.cutDeck.pop()!);
        remaining -= 1;
      }
      seat = (seat + 1) % this.players.length;
    }
    for (let extra = 0; extra < plan.cribExtra; extra += 1) this.crib.push(this.cutDeck.pop()!);
    this.status = `${this.players[this.dealer].name} deals. Choose cards for the crib.`;
    this.touch();
  }

  private startPegging(): void {
    this.keptHands = this.hands.map((hand) => hand.map((card) => ({ ...card })));
    this.starter = this.cutDeck.pop()!;
    this.cutDeck = [];
    if (this.starter.rank === 11 && this.award(this.players[this.dealer].team, 2)) return;
    this.phase = "pegging";
    this.activePlayer = this.nextPlayerWithCards(this.dealer);
    this.status = `${this.players[this.activePlayer].name} leads. Count starts at zero.`;
    this.touch();
  }

  private finishPegging(): void {
    this.phase = "show";
    this.showItems = [];
    for (let offset = 1; offset <= this.players.length; offset += 1) {
      const player = (this.dealer + offset) % this.players.length;
      const score = scoreCribbageHand(this.keptHands[player], this.starter!);
      this.showItems.push({
        kind: "hand",
        player,
        name: this.players[player].name,
        cards: this.keptHands[player].map((card) => ({ ...card })),
        points: score.total,
        detail: score.detail,
      });
      if (score.total && this.award(this.players[player].team, score.total)) return;
    }
    const cribScore = scoreCribbageHand(this.crib, this.starter!, true);
    this.showItems.push({
      kind: "crib",
      player: this.dealer,
      name: `${this.players[this.dealer].name}'s crib`,
      cards: this.crib.map((card) => ({ ...card })),
      points: cribScore.total,
      detail: cribScore.detail,
    });
    if (cribScore.total && this.award(this.players[this.dealer].team, cribScore.total)) return;
    this.status = `Hands counted. ${this.players[(this.dealer + 1) % this.players.length].name} deals next.`;
    this.touch();
  }

  private award(team: number, points: number): boolean {
    this.teamScores[team] = (this.teamScores[team] ?? 0) + points;
    if (this.teamScores[team] >= CRIBBAGE_WINNING_SCORE) {
      this.winnerTeam = team;
      this.phase = "game_over";
      const names = this.players.filter((player) => player.team === team).map((player) => player.name).join(" & ");
      this.status = `${names} wins with ${this.teamScores[team]} points!`;
      this.touch();
      return true;
    }
    return false;
  }

  private legalIndices(player: number): number[] {
    return this.hands[player].flatMap((card, index) =>
      this.pegTotal + cribbageCardValue(card) <= 31 ? [index] : []);
  }

  private nextPlayerWithCards(after: number): number {
    for (let offset = 1; offset <= this.players.length; offset += 1) {
      const candidate = (after + offset) % this.players.length;
      if (this.hands[candidate].length) return candidate;
    }
    return -1;
  }

  private nextLegalPlayer(after: number): number {
    for (let offset = 1; offset <= this.players.length; offset += 1) {
      const candidate = (after + offset) % this.players.length;
      if (this.legalIndices(candidate).length) return candidate;
    }
    return -1;
  }

  private resetPegSequence(): void {
    this.pegSequence = [];
    this.pegTotal = 0;
  }

  private shuffle(cards: CribbageCard[]): CribbageCard[] {
    for (let index = cards.length - 1; index > 0; index -= 1) {
      const other = Math.floor(this.random() * (index + 1));
      [cards[index], cards[other]] = [cards[other], cards[index]];
    }
    return cards;
  }

  private playerIndex(userId: string): number {
    const index = this.players.findIndex((player) => player.id === userId);
    if (index < 0) throw new RoomCommandError("not_in_game", "You are not seated in this Cribbage game.");
    return index;
  }

  private requirePhase(phase: CribbageGameSnapshot["phase"]): void {
    if (this.phase !== phase) throw new RoomCommandError("wrong_phase", `Cribbage is currently ${this.phase}.`);
  }

  private restore(snapshot: CribbageGameSnapshot): void {
    this.mode = snapshot.mode;
    this.players = snapshot.players.map((player) => ({ ...player }));
    this.teamScores = { ...snapshot.teamScores };
    this.dealer = snapshot.dealer;
    this.activePlayer = snapshot.activePlayer;
    this.phase = snapshot.phase;
    this.hands = snapshot.hands.map((hand) => hand.map((card) => ({ ...card })));
    this.keptHands = snapshot.keptHands.map((hand) => hand.map((card) => ({ ...card })));
    this.crib = snapshot.crib.map((card) => ({ ...card }));
    this.starter = snapshot.starter ? { ...snapshot.starter } : null;
    this.requiredDiscards = [...snapshot.requiredDiscards];
    this.discarded = [...snapshot.discarded];
    this.cutDeck = snapshot.cutDeck.map((card) => ({ ...card }));
    this.pegSequence = snapshot.pegSequence.map((card) => ({ ...card }));
    this.pegTotal = snapshot.pegTotal;
    this.playHistory = snapshot.playHistory.map((play) => ({ ...play, card: { ...play.card } }));
    this.showItems = snapshot.showItems.map((item) => ({ ...item, cards: item.cards.map((card) => ({ ...card })) }));
    this.status = snapshot.status;
    this.winnerTeam = snapshot.winnerTeam;
    this.dealNumber = snapshot.dealNumber;
    this.revision = snapshot.revision;
  }

  private touch(): void { this.revision += 1; }
}
