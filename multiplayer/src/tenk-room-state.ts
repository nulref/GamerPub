import { RoomCommandError } from "./room-state";

export const MAX_TENK_PLAYERS = 8;
export const MIN_TENK_PLAYERS = 2;

export interface TenkRoomPlayer {
  id: string;
  name: string;
  ready: boolean;
  connected: boolean;
  joinedAt: number;
  seat: number | null;
}

export interface TenkRoomSnapshot {
  phase: "waiting" | "playing";
  hostId: string | null;
  players: TenkRoomPlayer[];
  revision: number;
}

function cleanName(value: string): string {
  const cleaned = value.trim().replace(/\s+/g, " ").slice(0, 32);
  if (!cleaned) throw new RoomCommandError("invalid_name", "Enter a player name.");
  return cleaned;
}

export class TenkLobbyRoom {
  private phase: "waiting" | "playing" = "waiting";
  private hostId: string | null = null;
  private players: TenkRoomPlayer[] = [];
  private revision = 0;

  constructor(snapshot?: TenkRoomSnapshot | null) {
    if (!snapshot) return;
    this.phase = snapshot.phase;
    this.hostId = snapshot.hostId;
    this.players = snapshot.players.map((player) => ({ ...player }));
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
    if (this.phase !== "waiting") {
      throw new RoomCommandError("game_in_progress", "This Tenk game has already started.");
    }
    if (this.players.length >= MAX_TENK_PLAYERS) {
      throw new RoomCommandError("room_full", "This Tenk room already has eight players.");
    }
    this.players.push({
      id: userId,
      name: cleanName(name),
      ready: false,
      connected: true,
      joinedAt: now,
      seat: null,
    });
    this.ensureHost();
    this.touch();
  }

  setName(userId: string, name: string): void {
    this.requireWaiting();
    this.requirePlayer(userId).name = cleanName(name);
    this.touch();
  }

  setReady(userId: string, ready: boolean): void {
    this.requireWaiting();
    const player = this.requirePlayer(userId);
    if (!player.connected) throw new RoomCommandError("not_connected", "Reconnect before readying up.");
    player.ready = ready;
    this.touch();
  }

  start(userId: string): void {
    this.requireWaiting();
    if (userId !== this.hostId) throw new RoomCommandError("host_only", "Only the host can start Tenk.");
    const connected = this.players.filter((player) => player.connected);
    if (connected.length < MIN_TENK_PLAYERS) {
      throw new RoomCommandError("not_enough_players", "At least two players are required.");
    }
    if (connected.some((player) => !player.ready)) {
      throw new RoomCommandError("players_not_ready", "Every connected player must be ready.");
    }
    this.players = connected;
    this.players.forEach((player, seat) => { player.seat = seat; });
    this.phase = "playing";
    this.touch();
  }

  reset(userId: string): void {
    if (userId !== this.hostId) throw new RoomCommandError("host_only", "Only the host can reset Tenk.");
    this.players = this.players.filter((player) => player.connected).map((player) => ({
      ...player,
      ready: false,
      seat: null,
    }));
    this.phase = "waiting";
    this.ensureHost();
    this.touch();
  }

  leave(userId: string): void {
    if (this.phase === "playing") {
      this.disconnect(userId);
      return;
    }
    const previousLength = this.players.length;
    this.players = this.players.filter((player) => player.id !== userId);
    if (this.players.length === previousLength) return;
    this.ensureHost();
    this.touch();
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

  snapshot(): TenkRoomSnapshot {
    return {
      phase: this.phase,
      hostId: this.hostId,
      players: this.players.map((player) => ({ ...player })),
      revision: this.revision,
    };
  }

  private requireWaiting(): void {
    if (this.phase !== "waiting") {
      throw new RoomCommandError("game_in_progress", "This Tenk game has already started.");
    }
  }

  private requirePlayer(userId: string): TenkRoomPlayer {
    const player = this.players.find((candidate) => candidate.id === userId);
    if (!player) throw new RoomCommandError("join_required", "Join the Tenk room first.");
    return player;
  }

  private ensureHost(): void {
    const connected = this.players
      .filter((player) => player.connected)
      .sort((left, right) => left.joinedAt - right.joinedAt);
    if (!this.hostId || !connected.some((player) => player.id === this.hostId)) {
      this.hostId = connected[0]?.id ?? null;
    }
  }

  private touch(): void {
    this.revision += 1;
  }
}
