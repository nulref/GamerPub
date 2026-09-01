import assert from "node:assert/strict";
import WebSocket from "ws";

const baseUrl = process.env.TENK_SOCKET_URL ?? "ws://127.0.0.1:8787/tenk";
const origin = process.env.TENK_ORIGIN ?? "http://127.0.0.1:4173";

function roomUrl(userId, name) {
  const url = new URL(baseUrl);
  url.searchParams.set("user_id", userId);
  url.searchParams.set("name", name);
  return url;
}

function createClient(userId, name) {
  const socket = new WebSocket(roomUrl(userId, name), { origin });
  const queued = [];
  const waiters = [];
  socket.on("message", (raw) => {
    const message = JSON.parse(raw.toString());
    const waiterIndex = waiters.findIndex((waiter) => waiter.predicate(message));
    if (waiterIndex >= 0) {
      const [waiter] = waiters.splice(waiterIndex, 1);
      clearTimeout(waiter.timer);
      waiter.resolve(message);
    } else {
      queued.push(message);
    }
  });

  function next(predicate, timeoutMs = 5000) {
    const queuedIndex = queued.findIndex(predicate);
    if (queuedIndex >= 0) return Promise.resolve(queued.splice(queuedIndex, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, timer: null };
      waiter.timer = setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error("Timed out waiting for a Tenk room message."));
      }, timeoutMs);
      waiters.push(waiter);
    });
  }
  return { socket, next };
}

async function openClient(userId, name) {
  const client = createClient(userId, name);
  await new Promise((resolve, reject) => {
    client.socket.once("open", resolve);
    client.socket.once("error", reject);
  });
  await client.next((message) => message.type === "connected");
  return client;
}

async function close(client) {
  if (client.socket.readyState === WebSocket.CLOSED) return;
  await new Promise((resolve) => {
    client.socket.once("close", resolve);
    client.socket.close();
  });
}

const first = await openClient("tenk-first", "First");
const second = await openClient("tenk-second", "Second");
try {
  const lobby = await first.next((message) =>
    message.type === "room_state" && message.room.players.length === 2);
  assert.equal(lobby.room.hostId, "tenk-first");

  first.socket.send(JSON.stringify({ type: "set_ready", ready: true }));
  second.socket.send(JSON.stringify({ type: "set_ready", ready: true }));
  await first.next((message) =>
    message.type === "room_state" && message.room.players.every((player) => player.ready));
  first.socket.send(JSON.stringify({ type: "start_game" }));
  const started = await second.next((message) =>
    message.type === "game_state" && message.game.players.length === 2);
  assert.equal(started.game.players[0].id, "tenk-first");

  second.socket.send(JSON.stringify({ type: "roll" }));
  const rejected = await second.next((message) => message.type === "error");
  assert.equal(rejected.code, "not_your_turn");
  first.socket.send(JSON.stringify({ type: "roll" }));
  const rolled = await second.next((message) =>
    message.type === "game_state" && message.game.currentRoll.length === 6);
  assert.equal(rolled.game.currentPlayer, 0);

  first.socket.send(JSON.stringify({ type: "voice_join" }));
  const firstConfig = await first.next((message) => message.type === "voice_config");
  second.socket.send(JSON.stringify({ type: "voice_join" }));
  const secondConfig = await second.next((message) => message.type === "voice_config");
  const presence = await first.next((message) =>
    message.type === "voice_presence" && message.peers.length === 2);
  assert.deepEqual(new Set(presence.peers.map((peer) => peer.userId)),
    new Set(["tenk-first", "tenk-second"]));

  const offer = {
    kind: "description",
    description: { type: "offer", sdp: "v=0\r\ns=Tenk room smoke test\r\n" },
  };
  first.socket.send(JSON.stringify({
    type: "voice_signal",
    targetPeerId: secondConfig.selfPeerId,
    signal: offer,
  }));
  const relayed = await second.next((message) => message.type === "voice_signal");
  assert.equal(relayed.fromPeerId, firstConfig.selfPeerId);
  assert.equal(relayed.fromUserId, "tenk-first");
  assert.deepEqual(relayed.signal, offer);
} finally {
  await Promise.all([close(first), close(second)]);
}

console.log("Tenk shared lobby, turn authority, and voice signaling smoke test passed.");
