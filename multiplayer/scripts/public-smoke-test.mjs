import assert from "node:assert/strict";
import WebSocket from "ws";

const url = process.argv[2] ??
  "wss://gamerpub-multiplayer.joker-multiplayer.workers.dev/public";
const origin = process.argv[3] ?? "https://gamerpub.netlify.app";

function nextMessage(socket, expectedType, predicate = () => true, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for ${expectedType}`));
    }, timeoutMs);
    const onMessage = (data) => {
      const message = JSON.parse(String(data));
      if (message.type !== expectedType || !predicate(message)) return;
      cleanup();
      resolve(message);
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      clearTimeout(timeout);
      socket.off("message", onMessage);
      socket.off("error", onError);
    };
    socket.on("message", onMessage);
    socket.on("error", onError);
  });
}

async function connect() {
  const socket = new WebSocket(url, { origin });
  const connected = await nextMessage(socket, "connected");
  return { socket, connected };
}

function close(socket) {
  return new Promise((resolve) => {
    socket.once("close", resolve);
    socket.close();
  });
}

const first = await connect();
const second = await connect();

first.socket.send(JSON.stringify({ type: "join", userId: "public-first", name: "First" }));
await nextMessage(first.socket, "room_state", (message) => message.room.hostId === "public-first");
second.socket.send(JSON.stringify({ type: "join", userId: "public-second", name: "Second" }));
const joined = await nextMessage(
  second.socket,
  "room_state",
  (message) => message.room.players.length === 2,
);
assert.equal(joined.room.hostId, "public-first");

second.socket.send(JSON.stringify({ type: "start_game" }));
const rejected = await nextMessage(second.socket, "error");
assert.equal(rejected.code, "host_only");

await Promise.all([close(first.socket), close(second.socket)]);
await new Promise((resolve) => setTimeout(resolve, 500));

const replacement = await connect();
assert.equal(replacement.connected.room.players.length, 0);
replacement.socket.send(
  JSON.stringify({ type: "join", userId: "public-replacement", name: "Replacement" }),
);
const freshRoom = await nextMessage(
  replacement.socket,
  "room_state",
  (message) => message.room.hostId === "public-replacement",
);
assert.equal(freshRoom.room.players.length, 1);
await close(replacement.socket);

console.log(`Public-room smoke test passed for ${url}`);
