import { DurableObject } from "cloudflare:workers";
import { LobbyRoom, RoomCommandError, type RoomSnapshot } from "./room-state";
import { MultiplayerGame, type MatchStorageSnapshot } from "./game-state";
import {
  DiscordOAuthError,
  exchangeDiscordCode,
  validAuthorizationCode,
} from "./discord-oauth";
import {
  ActivitySessionError,
  signActivitySession,
  verifyActivitySession,
} from "./activity-session";
import {
  DiscordPremiumError,
  fetchDiscordUser,
  userCanHostDiscordRoom,
} from "./discord-premium";
import { PUBLIC_ROOM_NAME, PUBLIC_ROOM_PATH, publicOriginAllowed } from "./public-room";
import {
  MAX_TENK_VOICE_PARTICIPANTS,
  TENK_ROOM_NAME,
  TENK_ROOM_PATH,
  TENK_VOICE_PATH,
  publicVoiceName,
  validPublicVoiceUserId,
} from "./public-voice";
import { discordRoomAccessDecision } from "./room-access";
import {
  fallbackVoiceIceConfiguration,
  generateVoiceIceConfiguration,
  type VoiceIceConfiguration,
} from "./turn-credentials";
import { validVoicePeerId, validVoiceSignal, type VoiceSignal } from "./voice-signaling";
import { CRIBBAGE_PUBLIC_ROOM_NAME, CRIBBAGE_ROOM_PATH } from "./cribbage-room-state";

interface Env {
  GAME_ROOMS: DurableObjectNamespace<GameRoom>;
  TENK_ROOMS: DurableObjectNamespace<import("./tenk-room").TenkRoom>;
  CRIBBAGE_ROOMS: DurableObjectNamespace<import("./cribbage-room").CribbageRoom>;
  DISCORD_CLIENT_ID: string;
  DISCORD_CLIENT_SECRET?: string;
  DISCORD_BOT_TOKEN?: string;
  DISCORD_LIFETIME_SKU_ID?: string;
  DISCORD_HOST_ACCESS_MODE?: string;
  COMPLIMENTARY_HOST_USER_IDS?: string;
  ACCESS_SESSION_SECRET?: string;
  PUBLIC_ACTIVITY_ORIGIN?: string;
  PUBLIC_ACTIVITY_ORIGINS?: string;
  TURN_KEY_ID?: string;
  TURN_KEY_API_TOKEN?: string;
}

interface ConnectionAttachment {
  connectionId: string;
  userId?: string;
  canHost?: boolean;
  instanceId?: string;
  pendingName?: string;
  connectedAt: number;
  publicLobby?: boolean;
  voiceJoined?: boolean;
}

type ClientMessage =
  | { type: "join"; userId: string; name: string; sessionToken?: string }
  | { type: "set_name"; name: string }
  | { type: "set_ready"; ready: boolean }
  | { type: "start_game"; botSpeedScale?: number }
  | { type: "set_bot_speed"; botSpeedScale: number }
  | { type: "pass_card"; cardIndex: number }
  | { type: "slap" }
  | { type: "advance_round" }
  | { type: "leave" }
  | { type: "voice_join" }
  | { type: "voice_leave" }
  | { type: "voice_signal"; targetPeerId: string; signal: VoiceSignal }
  | { type: "ping"; sentAt?: number };

const ROOM_STORAGE_KEY = "room";
const GAME_STORAGE_KEY = "game";
const HOST_LICENSE_STORAGE_KEY = "host-license-active";
const EMPTY_ROOM_TTL_MS = 6 * 60 * 60 * 1000;
const MAX_CLIENT_MESSAGE_LENGTH = 96 * 1024;

function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store",
    },
  });
}

function validInstanceId(value: string | null): value is string {
  return Boolean(value && /^[A-Za-z0-9_.:-]{8,256}$/.test(value));
}

function validUserId(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,64}$/.test(value);
}

function parseMessage(raw: string): ClientMessage {
  const value: unknown = JSON.parse(raw);
  if (!value || typeof value !== "object" || !("type" in value)) {
    throw new RoomCommandError("invalid_message", "Messages require a type.");
  }
  return value as ClientMessage;
}

function discordPremiumConfig(env: Env) {
  return {
    applicationId: env.DISCORD_CLIENT_ID,
    botToken: env.DISCORD_BOT_TOKEN ?? "",
    hostSkuId: env.DISCORD_LIFETIME_SKU_ID ?? "",
    complimentaryHostUserIds: env.COMPLIMENTARY_HOST_USER_IDS,
  };
}

function freeDiscordHosting(env: Env): boolean {
  return env.DISCORD_HOST_ACCESS_MODE?.trim().toLowerCase() === "free";
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({
        ok: true,
        service: "gamerpub-multiplayer",
        version: "0.8.0",
        hostLicensingConfigured: Boolean(
          env.ACCESS_SESSION_SECRET && (freeDiscordHosting(env) ||
            (env.DISCORD_BOT_TOKEN && env.DISCORD_LIFETIME_SKU_ID)),
        ),
        hostAccessMode: freeDiscordHosting(env) ? "free" : "licensed",
        voiceRelayConfigured: Boolean(env.TURN_KEY_ID && env.TURN_KEY_API_TOKEN),
        tenkMultiplayer: true,
        tenkVoiceCapacity: MAX_TENK_VOICE_PARTICIPANTS,
        cribbageMultiplayer: true,
      });
    }

    // Discord strips the /api URL-mapping prefix, so the Activity's
    // /api/token request arrives here as /token.
    if (url.pathname === "/token") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      try {
        const body = (await request.json()) as { code?: unknown; instance_id?: unknown };
        if (!validAuthorizationCode(body.code)) {
          throw new DiscordOAuthError(400, "A valid Discord authorization code is required.");
        }
        if (typeof body.instance_id !== "string" || !validInstanceId(body.instance_id)) {
          throw new DiscordOAuthError(400, "A valid Discord Activity instance is required.");
        }
        const token = await exchangeDiscordCode(body.code, {
          clientId: env.DISCORD_CLIENT_ID,
          clientSecret: env.DISCORD_CLIENT_SECRET ?? "",
        });
        const user = await fetchDiscordUser(token.access_token);
        const canHost = freeDiscordHosting(env) ||
          await userCanHostDiscordRoom(user.id, discordPremiumConfig(env));
        const sessionToken = await signActivitySession(
          { userId: user.id, instanceId: body.instance_id, canHost },
          env.ACCESS_SESSION_SECRET ?? "",
        );
        return json({
          access_token: token.access_token,
          session_token: sessionToken,
          can_host: canHost,
        });
      } catch (error) {
        if (error instanceof DiscordOAuthError) {
          return json({ error: "oauth_exchange_failed", message: error.message }, error.status);
        }
        if (error instanceof DiscordPremiumError) {
          return json({ error: "discord_verification_failed", message: error.message }, error.status);
        }
        if (error instanceof ActivitySessionError) {
          return json({ error: "session_configuration_failed", message: error.message }, 503);
        }
        return json({ error: "invalid_request", message: "The token request was invalid." }, 400);
      }
    }

    // This refresh endpoint is retained for a future paid-access model. In
    // free-hosting mode it simply reissues the authenticated Activity session.
    if (url.pathname === "/entitlement") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
      try {
        const body = (await request.json()) as { session_token?: unknown };
        const claims = await verifyActivitySession(
          body.session_token,
          env.ACCESS_SESSION_SECRET ?? "",
        );
        const canHost = freeDiscordHosting(env) ||
          await userCanHostDiscordRoom(claims.userId, discordPremiumConfig(env));
        const sessionToken = await signActivitySession(
          { userId: claims.userId, instanceId: claims.instanceId, canHost },
          env.ACCESS_SESSION_SECRET ?? "",
        );
        return json({ session_token: sessionToken, can_host: canHost });
      } catch (error) {
        if (error instanceof ActivitySessionError) {
          return json({ error: "invalid_session", message: error.message }, 401);
        }
        if (error instanceof DiscordPremiumError) {
          return json({ error: "discord_verification_failed", message: error.message }, error.status);
        }
        return json({ error: "invalid_request", message: "The entitlement request was invalid." }, 400);
      }
    }

    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "websocket_upgrade_required" }, 426);
    }

    const publicOrigins = env.PUBLIC_ACTIVITY_ORIGINS ?? env.PUBLIC_ACTIVITY_ORIGIN ??
      "https://gamerpub.netlify.app";
    if (url.pathname === TENK_ROOM_PATH || url.pathname === TENK_VOICE_PATH) {
      if (!publicOriginAllowed(request.headers.get("Origin"), publicOrigins)) {
        return json({ error: "public_origin_forbidden" }, 403);
      }
      const instanceId = url.searchParams.get("instance_id");
      const activityRoom = validInstanceId(instanceId);
      if (!activityRoom && (!validPublicVoiceUserId(url.searchParams.get("user_id")) ||
          !publicVoiceName(url.searchParams.get("name")))) {
        return json({ error: "invalid_tenk_identity" }, 400);
      }
      const tenkRoom = env.TENK_ROOMS.getByName(
        activityRoom ? `discord:${instanceId}` : TENK_ROOM_NAME,
      );
      return tenkRoom.fetch(request);
    }

    if (url.pathname === CRIBBAGE_ROOM_PATH) {
      if (!publicOriginAllowed(request.headers.get("Origin"), publicOrigins)) {
        return json({ error: "public_origin_forbidden" }, 403);
      }
      const instanceId = url.searchParams.get("instance_id");
      const activityRoom = validInstanceId(instanceId);
      if (!activityRoom && (!validPublicVoiceUserId(url.searchParams.get("user_id")) ||
          !publicVoiceName(url.searchParams.get("name")))) {
        return json({ error: "invalid_cribbage_identity" }, 400);
      }
      const cribbageRoom = env.CRIBBAGE_ROOMS.getByName(
        activityRoom ? `discord:${instanceId}` : CRIBBAGE_PUBLIC_ROOM_NAME,
      );
      return cribbageRoom.fetch(request);
    }

    let roomName: string;
    if (url.pathname === PUBLIC_ROOM_PATH) {
      if (!publicOriginAllowed(request.headers.get("Origin"), publicOrigins)) {
        return json({ error: "public_origin_forbidden" }, 403);
      }
      roomName = PUBLIC_ROOM_NAME;
    } else {
      // Discord strips the matched /api proxy prefix before forwarding to the
      // target, so /api/socket at discordsays.com may arrive as /socket or /.
      if (url.pathname !== "/socket" && url.pathname !== "/") {
        return json({ error: "not_found" }, 404);
      }
      const instanceId = url.searchParams.get("instance_id");
      if (!validInstanceId(instanceId)) {
        return json({ error: "invalid_instance_id" }, 400);
      }
      roomName = instanceId;
    }

    const room = env.GAME_ROOMS.getByName(roomName);
    return room.fetch(request);
  },
} satisfies ExportedHandler<Env>;

export class GameRoom extends DurableObject<Env> {
  private room = new LobbyRoom();
  private game: MultiplayerGame | null = null;
  private hostLicenseActive = false;
  private readonly environment: Env;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.environment = env;
    this.ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<RoomSnapshot>(ROOM_STORAGE_KEY);
      this.room = new LobbyRoom(stored);
      const storedGame = await this.ctx.storage.get<MatchStorageSnapshot>(GAME_STORAGE_KEY);
      if (storedGame) this.game = new MultiplayerGame(this.room.snapshot().players, Math.random, storedGame);
      this.hostLicenseActive = await this.ctx.storage.get<boolean>(HOST_LICENSE_STORAGE_KEY) === true;
      this.room.reconcileConnectedUsers(this.connectedUserIds());
      this.syncGameConnections();
      await this.persist();
      await this.scheduleNextAutomation();
    });
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "websocket_upgrade_required" }, 426);
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    const url = new URL(request.url);
    const publicLobby = url.pathname === PUBLIC_ROOM_PATH;
    const instanceId = url.searchParams.get("instance_id") ?? undefined;
    const attachment: ConnectionAttachment = {
      connectionId: crypto.randomUUID(),
      connectedAt: Date.now(),
      instanceId,
      publicLobby,
    };
    server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server);
    await this.ctx.storage.deleteAlarm();

    this.send(server, {
      type: "connected",
      connectionId: attachment.connectionId,
      hostLicenseActive: publicLobby || this.hostLicenseActive,
      room: this.room.snapshot(),
    });
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
      const attachment = socket.deserializeAttachment() as ConnectionAttachment;
      let voicePresenceChanged = false;

      switch (message.type) {
        case "join":
          if (!validUserId(message.userId) || typeof message.name !== "string") {
            throw new RoomCommandError("invalid_join", "Join requires a valid user ID and name.");
          }
          if (message.name.trim().length === 0) {
            throw new RoomCommandError("invalid_name", "Enter a player name.");
          }

          if (attachment.publicLobby) {
            attachment.userId ??= message.userId;
          } else if (!attachment.userId) {
            if (!attachment.instanceId || !validInstanceId(attachment.instanceId)) {
              throw new RoomCommandError("invalid_instance_id", "A valid Discord Activity instance is required.");
            }
            try {
              const claims = await verifyActivitySession(
                message.sessionToken,
                this.environment.ACCESS_SESSION_SECRET ?? "",
                attachment.instanceId,
              );
              attachment.userId = claims.userId;
              attachment.canHost = claims.canHost;
            } catch (error) {
              if (error instanceof ActivitySessionError) {
                throw new RoomCommandError("invalid_session", error.message);
              }
              throw error;
            }
          }

          if (attachment.userId !== message.userId) {
            throw new RoomCommandError("identity_locked", "This connection is already bound to a player.");
          }

          if (!attachment.publicLobby) {
            const access = discordRoomAccessDecision(this.hostLicenseActive, attachment.canHost === true);
            if (access === "wait_for_host") {
              attachment.pendingName = message.name;
              socket.serializeAttachment(attachment);
              this.send(socket, { type: "host_license_required" });
              return;
            }
            if (access === "activate") {
              this.hostLicenseActive = true;
              await this.ctx.storage.put(HOST_LICENSE_STORAGE_KEY, true);
            }
          }

          this.room.join(attachment.userId, message.name, attachment.connectedAt);
          attachment.pendingName = undefined;
          socket.serializeAttachment(attachment);
          this.game?.updateConnection(attachment.userId, true, message.name);
          if (!attachment.publicLobby && this.hostLicenseActive) this.admitWaitingGuests(socket);
          break;
        case "set_name":
          this.room.setName(this.requireUser(attachment), message.name);
          break;
        case "set_ready":
          this.room.setReady(this.requireUser(attachment), message.ready === true);
          break;
        case "start_game":
          this.room.start(this.requireUser(attachment));
          this.game = new MultiplayerGame(
            this.room.snapshot().players,
            Math.random,
            undefined,
            message.botSpeedScale,
          );
          break;
        case "set_bot_speed":
          {
            const userId = this.requireUser(attachment);
            if (this.room.snapshot().hostId !== userId) {
              throw new RoomCommandError("host_only", "Only the host can change bot speed.");
            }
            this.requireGame().setBotSpeedScale(message.botSpeedScale);
          }
          break;
        case "pass_card":
          this.requireGame().passCard(this.requireUser(attachment), message.cardIndex);
          break;
        case "slap":
          this.requireGame().slap(this.requireUser(attachment));
          break;
        case "advance_round":
          this.requireGame().advanceRound(this.requireUser(attachment));
          break;
        case "leave":
          {
            const userId = this.requireUser(attachment);
            this.room.leave(userId);
            this.game?.updateConnection(userId, false);
          }
          voicePresenceChanged = attachment.voiceJoined === true;
          attachment.voiceJoined = false;
          attachment.userId = undefined;
          attachment.canHost = undefined;
          attachment.pendingName = undefined;
          socket.serializeAttachment(attachment);
          break;
        case "voice_join":
          await this.joinVoice(socket, attachment);
          return;
        case "voice_leave":
          this.requireUser(attachment);
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
          throw new RoomCommandError("unknown_command", "Unknown room command.");
      }

      await this.persist();
      this.broadcastState();
      if (voicePresenceChanged) this.broadcastVoicePresence();
      await this.scheduleNextAutomation();
    } catch (error) {
      if (error instanceof RoomCommandError) {
        this.sendError(socket, error.code, error.message);
        return;
      }
      if (error instanceof SyntaxError) {
        this.sendError(socket, "invalid_json", "Message must be valid JSON.");
        return;
      }
      console.error("Unhandled room message error", error);
      this.sendError(socket, "internal_error", "The room could not process that command.");
    }
  }

  async webSocketClose(socket: WebSocket): Promise<void> {
    const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
    const userId = attachment?.userId;
    if (userId && !this.hasAnotherConnection(socket, userId)) {
      this.room.disconnect(userId);
      this.game?.updateConnection(userId, false);
      await this.persist();
      this.broadcastState();
    }
    if (attachment?.voiceJoined) this.broadcastVoicePresence(socket);
    const remainingSockets = this.ctx.getWebSockets().filter((candidate) => candidate !== socket);
    if (attachment?.publicLobby && remainingSockets.length === 0) {
      await this.ctx.storage.deleteAll();
      this.room = new LobbyRoom();
      this.game = null;
      this.hostLicenseActive = false;
      return;
    }
    if (remainingSockets.length === 0) {
      await this.ctx.storage.setAlarm(Date.now() + EMPTY_ROOM_TTL_MS);
    } else {
      await this.scheduleNextAutomation();
    }
  }

  async webSocketError(socket: WebSocket): Promise<void> {
    await this.webSocketClose(socket);
  }

  async alarm(): Promise<void> {
    if (this.ctx.getWebSockets().length === 0) {
      await this.ctx.storage.deleteAll();
      this.room = new LobbyRoom();
      this.game = null;
      this.hostLicenseActive = false;
      return;
    }
    if (this.game?.performAutomatedAction()) {
      await this.persist();
      this.broadcastState();
    }
    await this.scheduleNextAutomation();
  }

  private connectedUserIds(): Set<string> {
    const userIds = new Set<string>();
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
      if (attachment?.userId) userIds.add(attachment.userId);
    }
    return userIds;
  }

  private hasAnotherConnection(closingSocket: WebSocket, userId: string): boolean {
    return this.ctx.getWebSockets().some((socket) => {
      if (socket === closingSocket) return false;
      const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
      return attachment?.userId === userId;
    });
  }

  private requireUser(attachment: ConnectionAttachment): string {
    if (!attachment.userId) {
      throw new RoomCommandError("join_required", "Join the lobby before sending this command.");
    }
    return attachment.userId;
  }

  private admitWaitingGuests(activatingSocket: WebSocket): void {
    const waiting = this.ctx.getWebSockets()
      .filter((socket) => socket !== activatingSocket)
      .map((socket) => ({
        socket,
        attachment: socket.deserializeAttachment() as ConnectionAttachment | null,
      }))
      .filter((entry): entry is { socket: WebSocket; attachment: ConnectionAttachment } =>
        Boolean(entry.attachment?.userId && entry.attachment.pendingName && !entry.attachment.publicLobby)
      )
      .sort((left, right) => left.attachment.connectedAt - right.attachment.connectedAt);

    for (const { socket, attachment } of waiting) {
      try {
        this.room.join(attachment.userId!, attachment.pendingName!, attachment.connectedAt);
        this.game?.updateConnection(attachment.userId!, true, attachment.pendingName!);
        attachment.pendingName = undefined;
        socket.serializeAttachment(attachment);
        this.send(socket, { type: "host_license_granted" });
      } catch (error) {
        attachment.pendingName = undefined;
        socket.serializeAttachment(attachment);
        if (error instanceof RoomCommandError) {
          this.sendError(socket, error.code, error.message);
        } else {
          console.warn("Could not admit a waiting Discord guest", error);
          this.sendError(socket, "internal_error", "The room could not admit this guest.");
        }
      }
    }
  }

  private async joinVoice(socket: WebSocket, attachment: ConnectionAttachment): Promise<void> {
    const userId = this.requireUser(attachment);
    if (!attachment.publicLobby) {
      throw new RoomCommandError("voice_unavailable", "Discord voice is used for Activity sessions.");
    }
    const player = this.room.snapshot().players.find((candidate) => candidate.id === userId);
    if (!player?.connected || player.isBot) {
      throw new RoomCommandError("voice_unavailable", "Join the multiplayer lobby before joining voice.");
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
    const currentAttachment = socket.deserializeAttachment() as ConnectionAttachment | null;
    if (!currentAttachment?.voiceJoined || currentAttachment.connectionId !== attachment.connectionId) return;
    this.send(socket, {
      type: "voice_config",
      selfPeerId: attachment.connectionId,
      ...iceConfiguration,
    });
    this.broadcastVoicePresence();
  }

  private relayVoiceSignal(
    socket: WebSocket,
    attachment: ConnectionAttachment,
    targetPeerId: unknown,
    signal: unknown,
  ): void {
    const userId = this.requireUser(attachment);
    if (!attachment.publicLobby || !attachment.voiceJoined) {
      throw new RoomCommandError("voice_join_required", "Join voice before signaling another player.");
    }
    if (!validVoicePeerId(targetPeerId) || !validVoiceSignal(signal)) {
      throw new RoomCommandError("invalid_voice_signal", "The voice signaling message is invalid.");
    }
    if (targetPeerId === attachment.connectionId) {
      throw new RoomCommandError("invalid_voice_target", "A voice peer cannot signal itself.");
    }
    const target = this.ctx.getWebSockets().find((candidate) => {
      const candidateAttachment = candidate.deserializeAttachment() as ConnectionAttachment | null;
      return candidateAttachment?.connectionId === targetPeerId &&
        candidateAttachment.publicLobby === true && candidateAttachment.voiceJoined === true;
    });
    if (!target) {
      throw new RoomCommandError("voice_peer_unavailable", "The voice peer is no longer available.");
    }
    this.send(target, {
      type: "voice_signal",
      fromPeerId: attachment.connectionId,
      fromUserId: userId,
      signal,
    });
  }

  private broadcastVoicePresence(excludedSocket?: WebSocket): void {
    const sockets = this.ctx.getWebSockets().filter((socket) => socket !== excludedSocket);
    const names = new Map(this.room.snapshot().players.map((player) => [player.id, player.name]));
    const peers = sockets.flatMap((socket) => {
      const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
      if (!attachment?.voiceJoined || !attachment.userId || !attachment.publicLobby) return [];
      return [{
        peerId: attachment.connectionId,
        userId: attachment.userId,
        name: names.get(attachment.userId) ?? "Player",
      }];
    });
    for (const socket of sockets) {
      const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
      if (attachment?.voiceJoined) this.send(socket, { type: "voice_presence", peers });
    }
  }

  private requireGame(): MultiplayerGame {
    if (!this.game) throw new RoomCommandError("game_not_started", "The game has not started yet.");
    return this.game;
  }

  private syncGameConnections(): void {
    if (!this.game) return;
    const connected = this.connectedUserIds();
    for (const player of this.room.snapshot().players) {
      if (!player.isBot) this.game.updateConnection(player.id, connected.has(player.id), player.name);
    }
  }

  private async persist(): Promise<void> {
    await this.ctx.storage.put(ROOM_STORAGE_KEY, this.room.snapshot());
    if (this.game) await this.ctx.storage.put(GAME_STORAGE_KEY, this.game.storageSnapshot());
    else await this.ctx.storage.delete(GAME_STORAGE_KEY);
  }

  private async scheduleNextAutomation(): Promise<void> {
    if (this.ctx.getWebSockets().length === 0) return;
    const delay = this.game?.nextAutomationDelayMs() ?? null;
    if (delay === null) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    await this.ctx.storage.setAlarm(Date.now() + delay);
  }

  private broadcastState(): void {
    for (const socket of this.ctx.getWebSockets()) {
      try {
        this.send(socket, { type: "room_state", room: this.room.snapshot() });
        const attachment = socket.deserializeAttachment() as ConnectionAttachment | null;
        if (this.game && attachment?.userId) {
          this.send(socket, { type: "game_state", game: this.game.publicSnapshot(attachment.userId) });
        }
      } catch (error) {
        console.warn("Could not broadcast room state", error);
      }
    }
  }

  private send(socket: WebSocket, value: unknown): void {
    socket.send(JSON.stringify(value));
  }

  private sendError(socket: WebSocket, code: string, message: string): void {
    this.send(socket, { type: "error", code, message });
  }
}

export { TenkRoom } from "./tenk-room";
export { CribbageRoom } from "./cribbage-room";
