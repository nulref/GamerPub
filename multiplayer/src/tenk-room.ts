import { DurableObject } from "cloudflare:workers";
import { ActivitySessionError, verifyActivitySession } from "./activity-session";
import { RoomCommandError } from "./room-state";
import { MAX_TENK_VOICE_PARTICIPANTS } from "./public-voice";
import { TenkGame, type TenkGameSnapshot } from "./tenk-game";
import { TenkLobbyRoom, type TenkRoomSnapshot } from "./tenk-room-state";
import {
  fallbackVoiceIceConfiguration,
  generateVoiceIceConfiguration,
  type VoiceIceConfiguration,
} from "./turn-credentials";
import { validVoicePeerId, validVoiceSignal, type VoiceSignal } from "./voice-signaling";

interface TenkEnv {
  ACCESS_SESSION_SECRET?: string;
  TURN_KEY_ID?: string;
  TURN_KEY_API_TOKEN?: string;
}

interface TenkAttachment {
  connectionId: string;
  userId: string;
  displayName: string;
  connectedAt: number;
  authenticated: boolean;
  instanceId?: string;
  voiceJoined?: boolean;
}

type TenkClientMessage =
  | { type: "join"; userId: string; name: string; sessionToken?: string }
  | { type: "set_name"; name: string }
  | { type: "set_ready"; ready: boolean }
  | { type: "start_game" }
  | { type: "roll" }
  | { type: "set_selection"; selectedIndices: unknown }
  | { type: "reroll"; selectedIndices: unknown }
  | { type: "keep"; selectedIndices: unknown }
  | { type: "next_player" }
  | { type: "reset_game" }
  | { type: "leave" }
  | { type: "voice_join" }
  | { type: "voice_leave" }
  | { type: "voice_signal"; targetPeerId: string; signal: VoiceSignal }
  | { type: "ping"; sentAt?: number };

const ROOM_STORAGE_KEY = "tenk-room";
const GAME_STORAGE_KEY = "tenk-game";
const MAX_CLIENT_MESSAGE_LENGTH = 96 * 1024;

function json(data: unknown, status: number): Response {
  return Response.json(data, { status, headers: { "Cache-Control": "no-store" } });
}

function parseMessage(raw: string): TenkClientMessage {
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== "object" || !("type" in value)) {
    throw new RoomCommandError("invalid_message", "Messages require a type.");
  }
  return value as TenkClientMessage;
}

export class TenkRoom extends DurableObject<TenkEnv> {
  private room = new TenkLobbyRoom();
  private game: TenkGame | null = null;
  private readonly environment: TenkEnv;

  constructor(ctx: DurableObjectState, env: TenkEnv) {
    super(ctx, env);
    this.environment = env;
    this.ctx.blockConcurrencyWhile(async () => {
      const storedRoom = await this.ctx.storage.get<TenkRoomSnapshot>(ROOM_STORAGE_KEY);
      this.room = new TenkLobbyRoom(storedRoom);
      const storedGame = await this.ctx.storage.get<TenkGameSnapshot>(GAME_STORAGE_KEY);
      if (storedGame) {
        this.game = new TenkGame(
          this.room.snapshot().players,
          Math.random,
          storedGame,
          (entry) => console.info(`[Tenk game] ${entry}`),
        );
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
      return json({ error: "invalid_voice_identity" }, 400);
    }

    if (!activityRoom) {
      try {
        this.room.join(userId, displayName);
        this.game?.updateConnection(userId, true, displayName);
      } catch (error) {
        if (error instanceof RoomCommandError) {
          return json({ error: error.code, message: error.message }, 409);
        }
        throw error;
      }
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    const attachment: TenkAttachment = {
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
      this.send(server, {
        type: "connected",
        connectionId: attachment.connectionId,
        room: this.room.snapshot(),
      });
      this.broadcastState();
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(socket: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    if (typeof raw !== "string") {
      this.sendError(socket, "invalid_message", "Binary messages are not supported.");
      return;
    }
    if (raw.length > MAX_CLIENT_MESSAGE_LENGTH) {
      this.sendError(socket, "message_too_large", "The message is too large.");
      return;
    }

    try {
      const message = parseMessage(raw);
      const attachment = socket.deserializeAttachment() as TenkAttachment;
      if (message.type === "join") {
        await this.joinActivity(socket, attachment, message);
        return;
      }
      if (!attachment.authenticated || !attachment.userId) {
        throw new RoomCommandError("activity_auth_required", "Authenticate this Activity session first.");
      }
      switch (message.type) {
        case "set_name":
          this.room.setName(attachment.userId, message.name);
          attachment.displayName = message.name.trim().replace(/\s+/g, " ").slice(0, 32);
          socket.serializeAttachment(attachment);
          break;
        case "set_ready":
          this.room.setReady(attachment.userId, message.ready === true);
          break;
        case "start_game":
          this.room.start(attachment.userId);
          this.game = new TenkGame(
            this.room.snapshot().players,
            Math.random,
            undefined,
            (entry) => console.info(`[Tenk game] ${entry}`),
          );
          break;
        case "roll":
          this.requireGame().roll(attachment.userId);
          break;
        case "set_selection":
          this.requireGame().setSelection(attachment.userId, message.selectedIndices);
          break;
        case "reroll":
          this.requireGame().reroll(attachment.userId, message.selectedIndices);
          break;
        case "keep":
          this.requireGame().keep(attachment.userId, message.selectedIndices);
          break;
        case "next_player":
          this.requireGame().nextPlayer(attachment.userId);
          break;
        case "reset_game":
          this.room.reset(attachment.userId);
          this.game = null;
          break;
        case "leave":
          this.room.leave(attachment.userId);
          this.game?.updateConnection(attachment.userId, false);
          if (attachment.voiceJoined) {
            attachment.voiceJoined = false;
            socket.serializeAttachment(attachment);
            this.broadcastVoicePresence();
          }
          break;
        case "voice_join":
          await this.joinVoice(socket, attachment);
          return;
        case "voice_leave":
          if (attachment.voiceJoined) {
            attachment.voiceJoined = false;
            socket.serializeAttachment(attachment);
            this.broadcastVoicePresence();
          }
          return;
        case "voice_signal":
          this.relayVoiceSignal(socket, attachment, message.targetPeerId, message.signal);
          return;
        case "ping":
          this.send(socket, { type: "pong", sentAt: message.sentAt ?? null });
          return;
        default:
          throw new RoomCommandError("unknown_command", "Unknown Tenk room command.");
      }
      await this.persist();
      this.broadcastState();
    } catch (error) {
      if (error instanceof RoomCommandError) {
        this.sendError(socket, error.code, error.message);
      } else if (error instanceof SyntaxError) {
        this.sendError(socket, "invalid_json", "Message must be valid JSON.");
      } else {
        console.error("Unhandled Tenk room message error", error);
        this.sendError(socket, "internal_error", "The Tenk room could not process that command.");
      }
    }
  }

  async webSocketClose(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as TenkAttachment | null;
    if (!attachment) return;
    if (attachment.authenticated && attachment.userId &&
        !this.hasAnotherConnection(socket, attachment.userId)) {
      if (this.room.snapshot().phase === "waiting") this.room.leave(attachment.userId);
      else this.room.disconnect(attachment.userId);
      this.game?.updateConnection(attachment.userId, false);
    }
    if (attachment.voiceJoined) this.broadcastVoicePresence(socket);
    const remaining = this.ctx.getWebSockets().filter((candidate) => candidate !== socket);
    if (remaining.length === 0) {
      await this.ctx.storage.deleteAll();
      this.room = new TenkLobbyRoom();
      this.game = null;
      return;
    }
    await this.persist();
    this.broadcastState();
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    await this.webSocketClose(socket);
  }

  private requireGame(): TenkGame {
    if (!this.game) throw new RoomCommandError("game_not_started", "The Tenk game has not started.");
    return this.game;
  }

  private async joinActivity(
    socket: WebSocket,
    attachment: TenkAttachment,
    message: Extract<TenkClientMessage, { type: "join" }>,
  ): Promise<void> {
    if (attachment.authenticated || !attachment.instanceId) {
      throw new RoomCommandError("already_joined", "This Tenk connection has already joined.");
    }
    let claims;
    try {
      claims = await verifyActivitySession(
        message.sessionToken,
        this.environment.ACCESS_SESSION_SECRET ?? "",
        attachment.instanceId,
      );
    } catch (error) {
      if (error instanceof ActivitySessionError) {
        throw new RoomCommandError("invalid_activity_session", error.message);
      }
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
    this.send(socket, {
      type: "connected",
      connectionId: attachment.connectionId,
      room: this.room.snapshot(),
    });
    this.broadcastState();
  }

  private connectedUserIds(): Set<string> {
    return new Set(this.ctx.getWebSockets().map((socket) =>
      (socket.deserializeAttachment() as TenkAttachment | null))
      .filter((attachment) => attachment?.authenticated && attachment.userId)
      .map((attachment) => attachment?.userId) as string[]);
  }

  private hasAnotherConnection(closingSocket: WebSocket, userId: string): boolean {
    return this.ctx.getWebSockets().some((socket) => {
      if (socket === closingSocket) return false;
      return (socket.deserializeAttachment() as TenkAttachment | null)?.userId === userId;
    });
  }

  private syncGameConnections(): void {
    if (!this.game) return;
    const connected = this.connectedUserIds();
    for (const player of this.room.snapshot().players) {
      this.game.updateConnection(player.id, connected.has(player.id), player.name);
    }
  }

  private async joinVoice(socket: WebSocket, attachment: TenkAttachment): Promise<void> {
    const player = this.room.snapshot().players.find((candidate) => candidate.id === attachment.userId);
    if (!player?.connected) throw new RoomCommandError("voice_unavailable", "Join the Tenk lobby first.");
    if (!attachment.voiceJoined) {
      const participantCount = this.ctx.getWebSockets().filter((candidate) =>
        (candidate.deserializeAttachment() as TenkAttachment | null)?.voiceJoined === true).length;
      if (participantCount >= MAX_TENK_VOICE_PARTICIPANTS) {
        throw new RoomCommandError("voice_room_full", "This Tenk voice room already has eight players.");
      }
    }
    attachment.voiceJoined = true;
    socket.serializeAttachment(attachment);
    let iceConfiguration: VoiceIceConfiguration;
    try {
      iceConfiguration = await generateVoiceIceConfiguration(this.environment);
    } catch (error) {
      console.warn("TURN credentials are unavailable; continuing with STUN only", error);
      iceConfiguration = fallbackVoiceIceConfiguration();
    }
    const currentAttachment = socket.deserializeAttachment() as TenkAttachment | null;
    if (!currentAttachment?.voiceJoined) return;
    this.send(socket, {
      type: "voice_config",
      selfPeerId: attachment.connectionId,
      ...iceConfiguration,
    });
    this.broadcastVoicePresence();
  }

  private relayVoiceSignal(
    socket: WebSocket,
    attachment: TenkAttachment,
    targetPeerId: unknown,
    signal: unknown,
  ): void {
    if (!attachment.voiceJoined) {
      throw new RoomCommandError("voice_join_required", "Join voice before signaling another player.");
    }
    if (!validVoicePeerId(targetPeerId) || !validVoiceSignal(signal)) {
      throw new RoomCommandError("invalid_voice_signal", "The voice signaling message is invalid.");
    }
    if (targetPeerId === attachment.connectionId) {
      throw new RoomCommandError("invalid_voice_target", "A voice peer cannot signal itself.");
    }
    const target = this.ctx.getWebSockets().find((candidate) => {
      const candidateAttachment = candidate.deserializeAttachment() as TenkAttachment | null;
      return candidateAttachment?.connectionId === targetPeerId && candidateAttachment.voiceJoined === true;
    });
    if (!target) throw new RoomCommandError("voice_peer_unavailable", "The voice peer is unavailable.");
    this.send(target, {
      type: "voice_signal",
      fromPeerId: attachment.connectionId,
      fromUserId: attachment.userId,
      signal,
    });
  }

  private broadcastVoicePresence(excludedSocket?: WebSocket): void {
    const sockets = this.ctx.getWebSockets().filter((socket) => socket !== excludedSocket);
    const peers = sockets.flatMap((socket) => {
      const attachment = socket.deserializeAttachment() as TenkAttachment | null;
      if (!attachment?.voiceJoined) return [];
      return [{
        peerId: attachment.connectionId,
        userId: attachment.userId,
        name: attachment.displayName,
      }];
    });
    for (const socket of sockets) {
      const attachment = socket.deserializeAttachment() as TenkAttachment | null;
      if (attachment?.voiceJoined) this.send(socket, { type: "voice_presence", peers });
    }
  }

  private async persist(): Promise<void> {
    await this.ctx.storage.put(ROOM_STORAGE_KEY, this.room.snapshot());
    if (this.game) await this.ctx.storage.put(GAME_STORAGE_KEY, this.game.snapshot());
    else await this.ctx.storage.delete(GAME_STORAGE_KEY);
  }

  private broadcastState(): void {
    const room = this.room.snapshot();
    const game = this.game?.snapshot() ?? null;
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as TenkAttachment | null;
      if (!attachment?.authenticated) continue;
      this.send(socket, { type: "room_state", room });
      if (game) this.send(socket, { type: "game_state", game });
    }
  }

  private send(socket: WebSocket, value: unknown): void {
    socket.send(JSON.stringify(value));
  }

  private sendError(socket: WebSocket, code: string, message: string): void {
    this.send(socket, { type: "error", code, message });
  }
}
