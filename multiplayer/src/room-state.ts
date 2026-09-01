export const MAX_PLAYERS = 4;

export type RoomPhase = "waiting" | "playing";

export interface RoomPlayer {
  id: string;
  name: string;
  ready: boolean;
  connected: boolean;
  joinedAt: number;
  seat: number | null;
  isBot: boolean;
}

export interface RoomSnapshot {
  phase: RoomPhase;
  hostId: string | null;
  players: RoomPlayer[];
  revision: number;
  startedAt: number | null;
}

export class RoomCommandError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function cleanName(value: string): string {
  const cleaned = value.trim().replace(/\s+/g, " ").slice(0, 32);
  if (!cleaned) {
    throw new RoomCommandError("invalid_name", "Enter a player name.");
  }
  return cleaned;
}

function clonePlayer(player: RoomPlayer): RoomPlayer {
  return { ...player };
}

export class LobbyRoom {
  private phase: RoomPhase = "waiting";
  private hostId: string | null = null;
  private players: RoomPlayer[] = [];
  private revision = 0;
  private startedAt: number | null = null;

  constructor(snapshot?: RoomSnapshot | null) {
    if (!snapshot) return;
    this.phase = snapshot.phase;
    this.hostId = snapshot.hostId;
    this.players = snapshot.players.map(clonePlayer);
    this.revision = snapshot.revision;
    this.startedAt = snapshot.startedAt;
  }

  join(userId: string, name: string, now = Date.now()): void {
    const existing = this.findHuman(userId);
    if (existing) {
      existing.connected = true;
      existing.name = cleanName(name);
      this.ensureHost();
      this.touch();
      return;
    }
    if (this.phase !== "waiting") {
      throw new RoomCommandError("game_in_progress", "This game has already started.");
    }
    if (this.humans().length >= MAX_PLAYERS) {
      throw new RoomCommandError("room_full", "This room already has four players.");
    }

    this.players.push({
      id: userId,
      name: cleanName(name),
      ready: false,
      connected: true,
      joinedAt: now,
      seat: null,
      isBot: false,
    });
    this.ensureHost();
    this.touch();
  }

  setName(userId: string, name: string): void {
    this.requireWaiting();
    const player = this.requireHuman(userId);
    player.name = cleanName(name);
    this.touch();
  }

  setReady(userId: string, ready: boolean): void {
    this.requireWaiting();
    const player = this.requireHuman(userId);
    if (!player.connected) {
      throw new RoomCommandError("not_connected", "Reconnect before changing ready state.");
    }
    player.ready = ready;
    this.touch();
  }

  start(userId: string, now = Date.now()): void {
    this.requireWaiting();
    if (userId !== this.hostId) {
      throw new RoomCommandError("host_only", "Only the lobby host can start the game.");
    }

    this.players = this.humans().filter((player) => player.connected);
    if (this.players.length === 0) {
      throw new RoomCommandError("empty_room", "At least one player must be connected.");
    }
    if (this.players.some((player) => !player.ready)) {
      throw new RoomCommandError("players_not_ready", "Every connected player must be ready.");
    }

    const botCount = MAX_PLAYERS - this.players.length;
    for (let index = 0; index < botCount; index += 1) {
      this.players.push({
        id: `bot-${index + 1}`,
        name: `Bot ${index + 1}`,
        ready: true,
        connected: true,
        joinedAt: now + index,
        seat: null,
        isBot: true,
      });
    }
    this.players.forEach((player, seat) => {
      player.seat = seat;
    });
    this.phase = "playing";
    this.startedAt = now;
    this.touch();
  }

  leave(userId: string): void {
    if (this.phase === "playing") {
      this.disconnect(userId);
      return;
    }
    const previousLength = this.players.length;
    this.players = this.players.filter((player) => player.isBot || player.id !== userId);
    if (this.players.length === previousLength) return;
    this.ensureHost();
    this.touch();
  }

  disconnect(userId: string): void {
    const player = this.findHuman(userId);
    if (!player || !player.connected) return;
    player.connected = false;
    player.ready = false;
    this.ensureHost();
    this.touch();
  }

  reconcileConnectedUsers(userIds: Set<string>): void {
    let changed = false;
    for (const player of this.humans()) {
      const connected = userIds.has(player.id);
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

  snapshot(): RoomSnapshot {
    return {
      phase: this.phase,
      hostId: this.hostId,
      players: this.players.map(clonePlayer),
      revision: this.revision,
      startedAt: this.startedAt,
    };
  }

  private humans(): RoomPlayer[] {
    return this.players.filter((player) => !player.isBot);
  }

  private findHuman(userId: string): RoomPlayer | undefined {
    return this.humans().find((player) => player.id === userId);
  }

  private requireHuman(userId: string): RoomPlayer {
    const player = this.findHuman(userId);
    if (!player) {
      throw new RoomCommandError("join_required", "Join the lobby before sending this command.");
    }
    return player;
  }

  private requireWaiting(): void {
    if (this.phase !== "waiting") {
      throw new RoomCommandError("game_in_progress", "This command is unavailable after the game starts.");
    }
  }

  private ensureHost(): void {
    const currentHost = this.hostId ? this.findHuman(this.hostId) : undefined;
    if (currentHost?.connected) return;
    this.hostId =
      this.humans()
        .filter((player) => player.connected)
        .sort((left, right) => left.joinedAt - right.joinedAt)[0]?.id ?? null;
  }

  private touch(): void {
    this.revision += 1;
  }
}
