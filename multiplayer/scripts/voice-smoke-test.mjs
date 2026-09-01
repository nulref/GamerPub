import assert from "node:assert/strict";
import WebSocket from "ws";

const url = process.env.JOKER_PUBLIC_SOCKET_URL ?? "ws://127.0.0.1:8787/public";
const origin = process.env.JOKER_PUBLIC_ORIGIN ?? "http://127.0.0.1:5173";

function createClient() {
  const socket = new WebSocket(url, { origin });
  const messages = [];
  const waiters = [];

  socket.on("message", (raw) => {
    const message = JSON.parse(raw.toString());
    const waiterIndex = waiters.findIndex((waiter) => waiter.predicate(message));
    if (waiterIndex >= 0) {
      const [waiter] = waiters.splice(waiterIndex, 1);
      clearTimeout(waiter.timer);
      waiter.resolve(message);
    } else {
      messages.push(message);
    }
  });

  function next(predicate, timeoutMs = 5000) {
    const existingIndex = messages.findIndex(predicate);
    if (existingIndex >= 0) return Promise.resolve(messages.splice(existingIndex, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve, reject, timer: null };
      waiter.timer = setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error("Timed out waiting for a voice smoke-test message."));
      }, timeoutMs);
      waiters.push(waiter);
    });
  }

  return { socket, next };
}

async function openClient(userId, name) {
  const client = createClient();
  await new Promise((resolve, reject) => {
    client.socket.once("open", resolve);
    client.socket.once("error", reject);
  });
  await client.next((message) => message.type === "connected");
  client.socket.send(JSON.stringify({ type: "join", userId, name }));
  await client.next((message) =>
    message.type === "room_state" && message.room.players.some((player) => player.id === userId));
  return client;
}

const first = await openClient("voice-first", "First");
const second = await openClient("voice-second", "Second");

first.socket.send(JSON.stringify({ type: "voice_join" }));
const firstConfig = await first.next((message) => message.type === "voice_config");
second.socket.send(JSON.stringify({ type: "voice_join" }));
const secondConfig = await second.next((message) => message.type === "voice_config");
const presence = await first.next((message) =>
  message.type === "voice_presence" && message.peers.length === 2);

assert.equal(typeof firstConfig.selfPeerId, "string");
assert.equal(typeof secondConfig.selfPeerId, "string");
assert.notEqual(firstConfig.selfPeerId, secondConfig.selfPeerId);
assert.equal(firstConfig.iceServers.length > 0, true);
assert.deepEqual(new Set(presence.peers.map((peer) => peer.userId)),
  new Set(["voice-first", "voice-second"]));

const offer = {
  kind: "description",
  description: { type: "offer", sdp: "v=0\r\ns=Joker voice smoke test\r\n" },
};
first.socket.send(JSON.stringify({
  type: "voice_signal",
  targetPeerId: secondConfig.selfPeerId,
  fromPeerId: "forged-client-value",
  signal: offer,
}));
const relayed = await second.next((message) => message.type === "voice_signal");
assert.equal(relayed.fromPeerId, firstConfig.selfPeerId);
assert.equal(relayed.fromUserId, "voice-first");
assert.deepEqual(relayed.signal, offer);

second.socket.send(JSON.stringify({ type: "voice_leave" }));
const afterLeave = await first.next((message) =>
  message.type === "voice_presence" && message.peers.length === 1);
assert.equal(afterLeave.peers[0].peerId, firstConfig.selfPeerId);

first.socket.close();
second.socket.close();
console.log(`Voice signaling smoke test passed (${firstConfig.relayAvailable ? "TURN" : "STUN-only"}).`);
