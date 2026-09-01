import { DurableObject } from "cloudflare:workers";
import { ActivitySessionError, verifyActivitySession } from "./activity-session";
import { CribbageGame, type CribbageGameSnapshot } from "./cribbage-game";
import { CribbageLobbyRoom, type CribbageRoomSnapshot } from "./cribbage-room-state";
import { RoomCommandError } from "./room-state";

interface CribbageEnv {
  ACCESS_SESSION_SECRET?: string;
}

interface CribbageAttachment {
  connectionId: string;
  userId: string;
  displayName: string;
  connectedAt: number;
  authenticated: boolean;
  instanceId?: string;
}

type CribbageClientMessage =
  | { type: "join"; userId: string; name: string; sessionToken?: string }
  | { type: "configure"; mode: unknown; playerCount: unknown }
  | { type: "set_name"; name: string }
  | { type: "set_ready"; ready: boolean }
  | { type: "start_game" }
  | { type: "discard"; cardIndices: unknown }
  | { type: "play_card"; cardIndex: unknown }
  | { type: "next_deal" }
  | { type: "reset_game" }
  | { type: "leave" }
  | { type: "ping"; sentAt?: number };

const ROOM_STORAGE_KEY = "cribbage-room";
const GAME_STORAGE_KEY = "cribbage-game";
const MAX_CLIENT_MESSAGE_LENGTH = 96 * 1024;

function json(data: unknown, status: number): Response {
  return Response.json(data, { status, headers: { "Cache-Control": "no-store" } });
}

function parseMessage(raw: string): CribbageClientMessage {
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== "object" || !("type" in value)) {
    throw new RoomCommandError("invalid_message", "Messages require a type.");
  }
  return value as CribbageClientMessage;
}

export class CribbageRoom extends DurableObject<CribbageEnv> {
  private room = new CribbageLobbyRoom();
  private game: CribbageGame | null = null;
  private readonly environment: CribbageEnv;

  constructor(ctx: DurableObjectState, env: CribbageEnv) {
    super(ctx, env);
    this.environment = env;
    this.ctx.blockConcurrencyWhile(async () => {
      const storedRoom = await this.ctx.storage.get<CribbageRoomSnapshot>(ROOM_STORAGE_KEY);
      this.room = new CribbageLobbyRoom(storedRoom);
      const storedGame = await this.ctx.storage.get<CribbageGameSnapshot>(GAME_STORAGE_KEY);
      if (storedGame?.mode) {
        this.game = new CribbageGame(this.room.snapshot().players, storedGame.mode, Math.random, storedGame);
      }
      this.room.reconcileConnectedUsers(this.connectedUserIds());
      this.syncGameConnections();
      await this.persist();
    });
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "websocket_upgrade_required" }, 426);
    }
    const url = new URL(request.url);
    const instanceId = url.searchParams.get("instance_id") ?? "";
    const activityRoom = Boolean(instanceId);
    const userId = url.searchParams.get("user_id") ?? "";
    const displayName = url.searchParams.get("name")?.trim() ?? "";
    if (!activityRoom && (!/^[A-Za-z0-9_-]{1,64}$/.test(userId) || !displayName)) {
      return json({ error: "invalid_cribbage_identity" }, 400);
    }
    if (!activityRoom) {
      try {
        this.room.join(userId, displayName);
        this.game?.updateConnection(userId, true, displayName);
      } catch (error) {
        if (error instanceof RoomCommandError) return json({ error: error.code, message: error.message }, 409);
        throw error;
      }
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    const attachment: CribbageAttachment = {
      connectionId: crypto.randomUUID(),
      userId,
      displayName: displayName.replace(/\s+/g, " ").slice(0, 32),
      connectedAt: Date.now(),
      authenticated: !activityRoom,
      ...(activityRoom ? { instanceId } : {}),
    };
    server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server);
    if (!activityRoom) {
      await this.persist();
      this.send(server, { type: "connected", connectionId: attachment.connectionId, room: this.room.snapshot() });
      this.broadcastState();
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    if (typeof raw !== "string") return this.sendError(socket, "invalid_message", "Binary messages are not supported.");
    if (raw.length > MAX_CLIENT_MESSAGE_LENGTH) return this.sendError(socket, "message_too_large", "The message is too large.");
    try {
      const message = parseMessage(raw);
      const attachment = socket.deserializeAttachment() as CribbageAttachment;
      if (message.type === "join") {
        await this.joinActivity(socket, attachment, message);
        return;
      }
      if (!attachment.authenticated || !attachment.userId) {
        throw new RoomCommandError("activity_auth_required", "Authenticate this Activity session first.");
      }
      switch (message.type) {
        case "configure":
          this.room.configure(attachment.userId, message.mode, message.playerCount);
          break;
        case "set_name":
          this.room.setName(attachment.userId, message.name);
          attachment.displayName = message.name.trim().replace(/\s+/g, " ").slice(0, 32);
          socket.serializeAttachment(attachment);
          break;
        case "set_ready":
          this.room.setReady(attachment.userId, message.ready === true);
          break;
        case "start_game": {
          this.room.start(attachment.userId);
          const room = this.room.snapshot();
          this.game = new CribbageGame(room.players, room.mode!, Math.random);
          break;
        }
        case "discard":
          this.requireGame().discard(attachment.userId, message.cardIndices);
          break;
        case "play_card":
          this.requireGame().playCard(attachment.userId, message.cardIndex);
          break;
        case "next_deal":
          this.requireHost(attachment.userId);
          this.requireGame().nextDeal();
          break;
        case "reset_game":
          this.room.reset(attachment.userId);
          this.game = null;
          break;
        case "leave":
          this.room.leave(attachment.userId);
          this.game?.updateConnection(attachment.userId, false);
          break;
        case "ping":
          this.send(socket, { type: "pong", sentAt: message.sentAt ?? null });
          return;
        default:
          throw new RoomCommandError("unknown_command", "Unknown Cribbage room command.");
      }
      await this.persist();
      this.broadcastState();
    } catch (error) {
      if (error instanceof RoomCommandError) this.sendError(socket, error.code, error.message);
      else if (error instanceof SyntaxError) this.sendError(socket, "invalid_json", "Message must be valid JSON.");
      else {
        console.error("Unhandled Cribbage room message error", error);
        this.sendError(socket, "internal_error", "The Cribbage room could not process that command.");
      }
    }
  }

  async webSocketClose(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as CribbageAttachment | null;
    if (!attachment) return;
    if (attachment.authenticated && attachment.userId && !this.hasAnotherConnection(socket, attachment.userId)) {
      if (this.room.snapshot().phase === "waiting") this.room.leave(attachment.userId);
      else this.room.disconnect(attachment.userId);
      this.game?.updateConnection(attachment.userId, false);
    }
    const remaining = this.ctx.getWebSockets().filter((candidate) => candidate !== socket);
    if (!remaining.length) {
      await this.ctx.storage.deleteAll();
      this.room = new CribbageLobbyRoom();
      this.game = null;
      return;
    }
    await this.persist();
    this.broadcastState();
  }

  async webSocketError(socket: WebSocket): Promise<void> { await this.webSocketClose(socket); }

  private async joinActivity(
    socket: WebSocket,
    attachment: CribbageAttachment,
    message: Extract<CribbageClientMessage, { type: "join" }>,
  ): Promise<void> {
    if (attachment.authenticated || !attachment.instanceId) {
      throw new RoomCommandError("already_joined", "This Cribbage connection has already joined.");
    }
    let claims;
    try {
      claims = await verifyActivitySession(
        message.sessionToken,
        this.environment.ACCESS_SESSION_SECRET ?? "",
        attachment.instanceId,
      );
    } catch (error) {
      if (error instanceof ActivitySessionError) throw new RoomCommandError("invalid_activity_session", error.message);
      throw error;
    }
    if (message.userId !== claims.userId) {
      throw new RoomCommandError("activity_identity_mismatch", "The Discord identity does not match this session.");
    }
    const displayName = message.name?.trim().replace(/\s+/g, " ").slice(0, 32);
    if (!displayName) throw new RoomCommandError("invalid_name", "Enter a player name first.");
    this.room.join(claims.userId, displayName);
    this.game?.updateConnection(claims.userId, true, displayName);
    attachment.userId = claims.userId;
    attachment.displayName = displayName;
    attachment.authenticated = true;
    socket.serializeAttachment(attachment);
    await this.persist();
    this.send(socket, { type: "connected", connectionId: attachment.connectionId, room: this.room.snapshot() });
    this.broadcastState();
  }

  private connectedUserIds(): Set<string> {
    return new Set(this.ctx.getWebSockets().map((socket) =>
      socket.deserializeAttachment() as CribbageAttachment | null)
      .filter((attachment) => attachment?.authenticated && attachment.userId)
      .map((attachment) => attachment!.userId));
  }

  private hasAnotherConnection(closingSocket: WebSocket, userId: string): boolean {
    return this.ctx.getWebSockets().some((socket) => socket !== closingSocket &&
      (socket.deserializeAttachment() as CribbageAttachment | null)?.userId === userId);
  }

  private syncGameConnections(): void {
    if (!this.game) return;
    const connected = this.connectedUserIds();
    for (const player of this.room.snapshot().players) {
      this.game.updateConnection(player.id, connected.has(player.id), player.name);
    }
  }

  private requireGame(): CribbageGame {
    if (!this.game) throw new RoomCommandError("game_not_started", "The Cribbage game has not started.");
    return this.game;
  }

  private requireHost(userId: string): void {
    if (this.room.snapshot().hostId !== userId) throw new RoomCommandError("host_only", "Only the host can deal the next hand.");
  }

  private async persist(): Promise<void> {
    await this.ctx.storage.put(ROOM_STORAGE_KEY, this.room.snapshot());
    if (this.game) await this.ctx.storage.put(GAME_STORAGE_KEY, this.game.snapshot());
    else await this.ctx.storage.delete(GAME_STORAGE_KEY);
  }

  private broadcastState(): void {
    const room = this.room.snapshot();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as CribbageAttachment | null;
      if (!attachment?.authenticated) continue;
      this.send(socket, { type: "room_state", room });
      if (this.game) this.send(socket, { type: "game_state", game: this.game.publicSnapshot(attachment.userId) });
    }
  }

  private send(socket: WebSocket, value: unknown): void { socket.send(JSON.stringify(value)); }
  private sendError(socket: WebSocket, code: string, message: string): void {
    this.send(socket, { type: "error", code, message });
  }
}
