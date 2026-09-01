import assert from "node:assert/strict";

const baseUrl = process.argv[2] ?? "ws://127.0.0.1:8787/socket";
const instanceId = `smoke-${Date.now()}`;
const url = `${baseUrl}?instance_id=${instanceId}`;

function nextMessage(socket, expectedType, predicate = () => true, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for ${expectedType}`));
    }, timeoutMs);

    const onMessage = (event) => {
      const message = JSON.parse(String(event.data));
      if (message.type !== expectedType || !predicate(message)) return;
      cleanup();
      resolve(message);
    };
    const onError = () => {
      cleanup();
      reject(new Error("WebSocket connection failed"));
    };
    const cleanup = () => {
      clearTimeout(timeout);
      socket.removeEventListener("message", onMessage);
      socket.removeEventListener("error", onError);
    };

    socket.addEventListener("message", onMessage);
    socket.addEventListener("error", onError);
  });
}

async function connect() {
  const socket = new WebSocket(url);
  const connected = await nextMessage(socket, "connected");
  return { socket, connected };
}

const alice = await connect();
const bob = await connect();

alice.socket.send(JSON.stringify({ type: "join", userId: "alice", name: "Alice" }));
await nextMessage(alice.socket, "room_state", (message) => message.room.hostId === "alice");
bob.socket.send(JSON.stringify({ type: "join", userId: "bob", name: "Bob" }));
const joined = await nextMessage(bob.socket, "room_state", (message) => message.room.players.length === 2);
assert.equal(joined.room.hostId, "alice");
assert.equal(joined.room.players.length, 2);

alice.socket.send(JSON.stringify({ type: "set_ready", ready: true }));
await nextMessage(
  alice.socket,
  "room_state",
  (message) => message.room.players.find((player) => player.id === "alice")?.ready === true,
);
bob.socket.send(JSON.stringify({ type: "set_ready", ready: true }));
await nextMessage(
  bob.socket,
  "room_state",
  (message) => message.room.players.every((player) => player.ready),
);

const aliceGameState = nextMessage(alice.socket, "game_state");
const bobGameState = nextMessage(bob.socket, "game_state");
alice.socket.send(JSON.stringify({ type: "start_game" }));
const started = await nextMessage(
  alice.socket,
  "room_state",
  (message) => message.room.phase === "playing",
);
assert.equal(started.room.phase, "playing");
assert.equal(started.room.players.length, 4);
assert.equal(started.room.players.filter((player) => player.isBot).length, 2);
const [aliceGame, bobGame] = await Promise.all([aliceGameState, bobGameState]);
assert.equal(aliceGame.game.players.length, 4);
assert.equal(aliceGame.game.players.reduce((total, player) => total + player.cardCount, 0), 17);
assert.equal(aliceGame.game.hand.length, aliceGame.game.players[aliceGame.game.localSeat].cardCount);
assert.equal(bobGame.game.hand.length, bobGame.game.players[bobGame.game.localSeat].cardCount);
assert.notEqual(aliceGame.game.localSeat, bobGame.game.localSeat);
assert.ok(aliceGame.game.players.every((player) => !("hand" in player)));

alice.socket.close();
bob.socket.close();
console.log(`Smoke test passed for ${url}`);
