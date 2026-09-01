import { RoomCommandError } from "./room-state";
import {
  type CribbageMode,
  validCribbageConfig,
} from "./cribbage-rules";

export const CRIBBAGE_ROOM_PATH = "/cribbage";
export const CRIBBAGE_PUBLIC_ROOM_NAME = "cribbage-public";

export interface CribbageRoomPlayer {
  id: string;
  name: string;
  ready: boolean;
  connected: boolean;
  joinedAt: number;
  seat: number | null;
}

export interface CribbageRoomSnapshot {
  phase: "waiting" | "playing";
  hostId: string | null;
  players: CribbageRoomPlayer[];
  configured: boolean;
  mode: CribbageMode | null;
  playerCount: number;
  revision: number;
}

function cleanName(value: string): string {
  const cleaned = value.trim().replace(/\s+/g, " ").slice(0, 32);
  if (!cleaned) throw new RoomCommandError("invalid_name", "Enter a player name.");
  return cleaned;
}

export class CribbageLobbyRoom {
  private phase: "waiting" | "playing" = "waiting";
  private hostId: string | null = null;
  private players: CribbageRoomPlayer[] = [];
  private configured = false;
  private mode: CribbageMode | null = null;
  private playerCount = 0;
  private revision = 0;

  constructor(snapshot?: CribbageRoomSnapshot | null) {
    if (!snapshot) return;
    this.phase = snapshot.phase;
    this.hostId = snapshot.hostId;
    this.players = snapshot.players.map((player) => ({ ...player }));
    this.configured = snapshot.configured;
    this.mode = snapshot.mode;
    this.playerCount = snapshot.playerCount;
    this.revision = snapshot.revision;
  }

  join(userId: string, name: string, now = Date.now()): void {
    const existing = this.players.find((player) => player.id === userId);
    if (existing) {
      existing.connected = true;
      existing.name = cleanName(name);
      this.ensureHost();
      this.touch();
      return;
    }
    if (this.phase !== "waiting") throw new RoomCommandError("game_in_progress", "This Cribbage game has started.");
    if (this.players.length >= (this.configured ? this.playerCount : 6)) {
      throw new RoomCommandError("room_full", "This Cribbage table is full.");
    }
    this.players.push({ id: userId, name: cleanName(name), ready: false, connected: true, joinedAt: now, seat: null });
    this.ensureHost();
    this.touch();
  }

  configure(userId: string, mode: unknown, playerCount: unknown): void {
    this.requireWaiting();
    if (userId !== this.hostId) throw new RoomCommandError("host_only", "Only the host chooses the Cribbage table.");
    if (!validCribbageConfig(mode, playerCount)) {
      throw new RoomCommandError("invalid_configuration", "Choose a valid Cribbage mode and player count.");
    }
    const configuredPlayerCount = playerCount as number;
    if (this.players.length > configuredPlayerCount) {
      throw new RoomCommandError("too_many_players", "Too many players have joined for that table size.");
    }
    this.configured = true;
    this.mode = mode;
    this.playerCount = configuredPlayerCount;
    this.players.forEach((player) => { player.ready = false; });
    this.touch();
  }

  setName(userId: string, name: string): void {
    this.requireWaiting();
    this.requirePlayer(userId).name = cleanName(name);
    this.touch();
  }

  setReady(userId: string, ready: boolean): void {
    this.requireWaiting();
    if (!this.configured) throw new RoomCommandError("configuration_required", "The host must choose the table first.");
    const player = this.requirePlayer(userId);
    if (!player.connected) throw new RoomCommandError("not_connected", "Reconnect before readying up.");
    player.ready = ready;
    this.touch();
  }

  start(userId: string): void {
    this.requireWaiting();
    if (userId !== this.hostId) throw new RoomCommandError("host_only", "Only the host can start Cribbage.");
    if (!this.configured || !this.mode) throw new RoomCommandError("configuration_required", "Choose the table first.");
    const connected = this.players.filter((player) => player.connected);
    if (connected.length !== this.playerCount) {
      throw new RoomCommandError("seat_count", `This table needs exactly ${this.playerCount} players.`);
    }
    if (connected.some((player) => !player.ready)) {
      throw new RoomCommandError("players_not_ready", "Every player must be ready.");
    }
    this.players = connected;
    this.players.forEach((player, seat) => { player.seat = seat; });
    this.phase = "playing";
    this.touch();
  }

  reset(userId: string): void {
    if (userId !== this.hostId) throw new RoomCommandError("host_only", "Only the host can reset Cribbage.");
    this.players = this.players.filter((player) => player.connected).map((player) => ({ ...player, ready: false, seat: null }));
    this.phase = "waiting";
    this.ensureHost();
    this.touch();
  }

  leave(userId: string): void {
    if (this.phase === "playing") return this.disconnect(userId);
    const length = this.players.length;
    this.players = this.players.filter((player) => player.id !== userId);
    if (this.players.length !== length) {
      this.ensureHost();
      this.touch();
    }
  }

  disconnect(userId: string): void {
    const player = this.players.find((candidate) => candidate.id === userId);
    if (!player || !player.connected) return;
    player.connected = false;
    player.ready = false;
    this.ensureHost();
    this.touch();
  }

  reconcileConnectedUsers(connectedIds: ReadonlySet<string>): void {
    let changed = false;
    for (const player of this.players) {
      const connected = connectedIds.has(player.id);
      if (player.connected !== connected) {
        player.connected = connected;
        if (!connected) player.ready = false;
        changed = true;
      }
    }
    if (changed) {
      this.ensureHost();
      this.touch();
    }
  }

  snapshot(): CribbageRoomSnapshot {
    return {
      phase: this.phase,
      hostId: this.hostId,
      players: this.players.map((player) => ({ ...player })),
      configured: this.configured,
      mode: this.mode,
      playerCount: this.playerCount,
      revision: this.revision,
    };
  }

  private requireWaiting(): void {
    if (this.phase !== "waiting") throw new RoomCommandError("game_in_progress", "This Cribbage game has started.");
  }

  private requirePlayer(userId: string): CribbageRoomPlayer {
    const player = this.players.find((candidate) => candidate.id === userId);
    if (!player) throw new RoomCommandError("join_required", "Join the Cribbage room first.");
    return player;
  }

  private ensureHost(): void {
    const connected = this.players.filter((player) => player.connected)
      .sort((left, right) => left.joinedAt - right.joinedAt);
    if (!this.hostId || !connected.some((player) => player.id === this.hostId)) {
      this.hostId = connected[0]?.id ?? null;
    }
  }

  private touch(): void { this.revision += 1; }
}
