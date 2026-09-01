import { CribbageRoomClient } from "./cribbage-room-client.js";

const productionUrl = document.querySelector('meta[name="gamer-pub-cribbage-url"]')?.content?.trim();
const configuredUrl = ["localhost", "127.0.0.1"].includes(window.location.hostname)
  ? `ws://${window.location.hostname}:8787/cribbage`
  : productionUrl;
const PLAYER_ID_KEY = "gamer-pub.cribbage-player-id";
const awaitingActivityContext =
  new URLSearchParams(window.location.search).get("gamer_pub_activity") === "discord";

let activityContextReady = !awaitingActivityContext;
let connectRequested = false;
let connected = false;
let latestRoom = null;
let latestGame = null;
let latestStatus = "disconnected";

function postToGame(type, payload) {
  window.postMessage({
    source: "gamer-pub-cribbage-web",
    type,
    payloadJson: JSON.stringify(payload ?? null),
  }, window.location.origin);
}

function localIdentity() {
  const testPlayer = ["localhost", "127.0.0.1"].includes(window.location.hostname)
    ? new URLSearchParams(window.location.search).get("cribbage_player")
    : null;
  if (testPlayer && /^[A-Za-z0-9_-]{1,32}$/.test(testPlayer)) {
    return { userId: `crib_${testPlayer}`, name: `Player ${testPlayer}` };
  }
  let userId = null;
  try { userId = localStorage.getItem(PLAYER_ID_KEY); } catch { /* session identity is fine */ }
  if (!userId || !/^[A-Za-z0-9_-]{1,64}$/.test(userId)) {
    const randomPart = globalThis.crypto?.randomUUID?.().replaceAll("-", "") ??
      Math.random().toString(36).slice(2);
    userId = `crib_${randomPart}`.slice(0, 64);
    try { localStorage.setItem(PLAYER_ID_KEY, userId); } catch { /* session identity is fine */ }
  }
  return { userId, name: `Player ${userId.slice(-4).toUpperCase()}` };
}

let identity = localIdentity();
const client = new CribbageRoomClient({
  ...(configuredUrl ? { url: configuredUrl } : {}),
  onStatus: (status) => {
    latestStatus = status;
    connected = status === "connected";
    postToGame("room-status", { status });
  },
  onState: (room) => {
    latestRoom = room;
    postToGame("room-state", room);
  },
  onGame: (game) => {
    latestGame = game;
    postToGame("game-state", game);
  },
  onError: (message) => postToGame("room-error", { message }),
});

function postContext() {
  postToGame("cribbage-context", {
    connected: activityContextReady,
    connectionMode: awaitingActivityContext ? "discord" : "public-web",
    currentUser: identity,
  });
}

function connectIfReady(name = "") {
  if (!connectRequested || !activityContextReady || connected || client.socket) return;
  if (name?.trim()) identity = { ...identity, name: name.trim() };
  client.connect(identity);
  postContext();
}

function applyActivityContext(payload) {
  if (!awaitingActivityContext) return;
  const user = payload?.currentUser;
  if (!payload?.connected || !user?.userId || !user?.name || !payload?.cribbageSocketUrl ||
      !payload?.sessionToken) {
    activityContextReady = false;
    postContext();
    return;
  }
  const changed = identity.userId !== user.userId ||
    identity.sessionToken !== payload.sessionToken || client.url !== payload.cribbageSocketUrl;
  activityContextReady = true;
  identity = { userId: user.userId, name: user.name, sessionToken: payload.sessionToken };
  client.url = payload.cribbageSocketUrl;
  if (changed && client.socket) client.disconnect({ announce: false });
  postContext();
  connectIfReady();
}

function handleCommand(command, payload = {}) {
  if (command === "connect") {
    connectRequested = true;
    connectIfReady(payload.name);
    return;
  }
  if (command === "leave") {
    connectRequested = false;
    connected = false;
    client.disconnect();
    return;
  }
  if (command === "set_name") {
    client.setName(payload.name);
    return;
  }
  client.send(command, payload);
}

window.addEventListener("message", (event) => {
  if (event.origin !== window.location.origin) return;
  if (event.data?.source === "gamer-pub-activity" && event.data.type === "discord-context") {
    let payload = event.data.payload;
    if (!payload && typeof event.data.payloadJson === "string") {
      try { payload = JSON.parse(event.data.payloadJson); } catch { payload = null; }
    }
    applyActivityContext(payload);
    return;
  }
  if (event.data?.source !== "gamer-pub-cribbage-godot") return;
  if (event.data.type === "bridge-ready") {
    postContext();
    postToGame("room-status", { status: latestStatus });
    if (latestRoom) postToGame("room-state", latestRoom);
    if (latestGame) postToGame("game-state", latestGame);
  } else if (event.data.type === "room-command") {
    handleCommand(event.data.payload?.command, event.data.payload?.payload ?? {});
  } else if (event.data.type === "orientation" && awaitingActivityContext) {
    window.parent.postMessage({
      source: "gamer-pub-cribbage-shell",
      type: "orientation",
      landscape: event.data.payload?.landscape === true,
    }, window.location.origin);
  }
});

window.addEventListener("beforeunload", () => client.disconnect({ announce: false }));
postContext();
