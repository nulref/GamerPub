import { Common, DiscordSDK, Events } from "@discord/embedded-app-sdk";
import "./style.css";
import {
  activitySocketUrl,
  DISCORD_CLIENT_ID_PLACEHOLDER,
  discordDisplayName,
  isDiscordActivity,
  validatedGameEntry,
} from "./activity-client.js";
import { RoomClient } from "./room-client.js";

const clientId = import.meta.env.VITE_DISCORD_CLIENT_ID?.trim();
const gameFrame = document.querySelector("#game-frame");
const connectionStatus = document.querySelector("#connection-status");
const embeddedInDiscord = isDiscordActivity();
const activityContext = {
  connected: false,
  connectionMode: embeddedInDiscord ? "discord" : "public-web",
  clientId: clientId ?? null,
  instanceId: null,
  channelId: null,
  guildId: null,
  participants: [],
  currentUser: null,
  canHost: false,
};

let discordSdk = null;
let sessionToken = null;
let pendingRoomConnect = null;
let latestRoomState = null;
let latestGameState = null;
let roomStatus = "disconnected";
let statusTimer = null;

function updateStatus(message, autoHide = false) {
  clearTimeout(statusTimer);
  connectionStatus.textContent = message;
  connectionStatus.hidden = false;
  if (autoHide) {
    statusTimer = setTimeout(() => {
      connectionStatus.hidden = true;
    }, 1600);
  }
}

function postToGame(source, type, payload) {
  gameFrame.contentWindow?.postMessage({
    source,
    type,
    payload,
    payloadJson: JSON.stringify(payload ?? null),
  }, window.location.origin);
}

function sendContextsToGame() {
  postToGame("joker-discord-activity", "discord-context", activityContext);
  const user = activityContext.currentUser;
  postToGame("gamer-pub-activity", "discord-context", {
    connected: activityContext.connected,
    connectionMode: activityContext.connectionMode,
    instanceId: activityContext.instanceId,
    currentUser: user?.id ? {
      userId: user.id,
      name: discordDisplayName(user),
    } : null,
    tenkSocketUrl: activityContext.instanceId
      ? activitySocketUrl("/api/tenk", activityContext.instanceId)
      : null,
    cribbageSocketUrl: activityContext.instanceId
      ? activitySocketUrl("/api/cribbage", activityContext.instanceId)
      : null,
    sessionToken,
  });
}

const roomClient = new RoomClient({
  urlFactory: (instanceId) => activitySocketUrl("/api/socket", instanceId),
  onStatus: (status) => {
    roomStatus = status;
    postToGame("joker-discord-activity", "room-status", { status });
  },
  onState: (room) => {
    latestRoomState = room;
    postToGame("joker-discord-activity", "room-state", room);
  },
  onGame: (game) => {
    latestGameState = game;
    postToGame("joker-discord-activity", "game-state", game);
  },
  onHostAccessRequired: () => {
    postToGame("joker-discord-activity", "room-error", {
      message: "This Gamer Pub room is waiting for a player who can host.",
    });
  },
  onError: (message) => {
    postToGame("joker-discord-activity", "room-error", { message });
  },
});

function connectPendingRoom() {
  const user = activityContext.currentUser;
  if (!pendingRoomConnect || !activityContext.connected || !activityContext.instanceId ||
      !user?.id || !sessionToken) return false;
  const request = pendingRoomConnect;
  pendingRoomConnect = null;
  roomClient.connect({
    instanceId: activityContext.instanceId,
    userId: user.id,
    name: request.name?.trim() || discordDisplayName(user),
    sessionToken,
  });
  return true;
}

function handleRoomCommand(payload) {
  switch (payload?.command) {
    case "connect":
      pendingRoomConnect = payload;
      if (!connectPendingRoom()) {
        roomStatus = "waiting_for_discord";
        postToGame("joker-discord-activity", "room-status", { status: roomStatus });
      }
      break;
    case "set_name": roomClient.setName(payload.name); break;
    case "set_ready": roomClient.send("set_ready", { ready: Boolean(payload.ready) }); break;
    case "start_game": roomClient.send("start_game", { botSpeedScale: payload.botSpeedScale }); break;
    case "set_bot_speed": roomClient.send("set_bot_speed", { botSpeedScale: payload.botSpeedScale }); break;
    case "pass_card": roomClient.send("pass_card", { cardIndex: payload.cardIndex }); break;
    case "slap": roomClient.send("slap"); break;
    case "advance_round": roomClient.send("advance_round"); break;
    case "leave":
      pendingRoomConnect = null;
      roomClient.disconnect();
      latestRoomState = null;
      latestGameState = null;
      break;
    default:
      postToGame("joker-discord-activity", "room-error", {
        message: "Unknown multiplayer command.",
      });
  }
}

function handleGameMessage(event) {
  if (event.source !== gameFrame.contentWindow || event.origin !== window.location.origin) return;
  if (event.data?.source === "gamer-pub-cribbage-shell" && event.data.type === "orientation") {
    void setGameOrientation(event.data.landscape === true);
    return;
  }
  if (event.data?.source !== "joker-godot") return;
  if (event.data.type === "bridge-ready") {
    sendContextsToGame();
    postToGame("joker-discord-activity", "room-status", { status: roomStatus });
    if (latestRoomState) postToGame("joker-discord-activity", "room-state", latestRoomState);
    if (latestGameState) postToGame("joker-discord-activity", "game-state", latestGameState);
  } else if (event.data.type === "room-command") {
    handleRoomCommand(event.data.payload);
  }
}

async function setGameOrientation(landscape) {
  if (!discordSdk) return;
  try {
    const lockState = landscape
      ? Common.OrientationLockStateTypeObject.LANDSCAPE
      : Common.OrientationLockStateTypeObject.PORTRAIT;
    await discordSdk.commands.setOrientationLockState({
      lock_state: lockState,
      picture_in_picture_lock_state: lockState,
      grid_lock_state: lockState,
    });
  } catch (error) {
    console.warn("Discord could not change Gamer Pub orientation.", error);
  }
}

async function loadGame() {
  const response = await fetch("/game-manifest.json", { cache: "no-store" });
  if (!response.ok) throw new Error(`Gamer Pub build manifest failed to load (${response.status}).`);
  const entry = validatedGameEntry(await response.json());
  const url = new URL(entry, window.location.origin);
  if (embeddedInDiscord) url.searchParams.set("gamer_pub_activity", "discord");
  gameFrame.src = url.toString();
}

async function authenticateCurrentUser() {
  const { code } = await discordSdk.commands.authorize({
    client_id: clientId,
    response_type: "code",
    state: "",
    prompt: "none",
    scope: ["identify"],
  });
  const response = await fetch("/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code, instance_id: activityContext.instanceId }),
  });
  if (!response.ok) throw new Error(`Discord token exchange failed (${response.status}).`);
  const result = await response.json();
  if (!result.access_token || !result.session_token) {
    throw new Error("Discord returned an incomplete Gamer Pub session.");
  }
  sessionToken = result.session_token;
  activityContext.canHost = result.can_host === true;
  const auth = await discordSdk.commands.authenticate({ access_token: result.access_token });
  if (!auth?.user?.id) throw new Error("Discord authentication returned no user.");
  activityContext.currentUser = auth.user;
}

async function initializeDiscord() {
  if (!embeddedInDiscord) {
    updateStatus("Gamer Pub ready", true);
    sendContextsToGame();
    return;
  }
  if (!clientId || clientId === DISCORD_CLIENT_ID_PLACEHOLDER) {
    throw new Error("Add VITE_DISCORD_CLIENT_ID before launching Gamer Pub in Discord.");
  }

  discordSdk = new DiscordSDK(clientId);
  await discordSdk.subscribe(Events.READY, (event) => {
    if (event?.user) activityContext.currentUser = event.user;
  });
  await discordSdk.ready();
  activityContext.connected = true;
  activityContext.instanceId = discordSdk.instanceId ?? null;
  activityContext.channelId = discordSdk.channelId ?? null;
  activityContext.guildId = discordSdk.guildId ?? null;
  if (!activityContext.instanceId) throw new Error("Discord supplied no Activity instance ID.");

  try {
    const portrait = Common.OrientationLockStateTypeObject.PORTRAIT;
    await discordSdk.commands.setOrientationLockState({
      lock_state: portrait,
      picture_in_picture_lock_state: portrait,
      grid_lock_state: portrait,
    });
  } catch (error) {
    console.warn("Discord could not lock Gamer Pub to portrait orientation.", error);
  }

  await authenticateCurrentUser();
  sendContextsToGame();
  connectPendingRoom();
  try {
    const response = await discordSdk.commands.getInstanceConnectedParticipants();
    activityContext.participants = response?.participants ?? [];
    await discordSdk.subscribe(Events.ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE, (event) => {
      activityContext.participants = event?.participants ?? [];
      sendContextsToGame();
    });
  } catch (error) {
    console.warn("Discord participant information is unavailable.", error);
  }
  updateStatus("Connected to Discord", true);
  sendContextsToGame();
}

gameFrame.addEventListener("load", sendContextsToGame);
window.addEventListener("message", handleGameMessage);
window.addEventListener("pagehide", () => roomClient.disconnect({ announce: false }));

try {
  await Promise.all([loadGame(), initializeDiscord()]);
} catch (error) {
  console.error("Gamer Pub Activity initialization failed", error);
  updateStatus(error instanceof Error ? error.message : "Gamer Pub could not start.");
  sendContextsToGame();
}
