import assert from "node:assert/strict";

const baseUrl = process.argv[2] ?? "ws://127.0.0.1:8787/socket";
const instanceId = `pacing-${Date.now()}`;
const socket = new WebSocket(`${baseUrl}?instance_id=${instanceId}`);
const queued = [];
const waiters = [];

socket.addEventListener("message", (event) => {
  const entry = { receivedAt: Date.now(), message: JSON.parse(String(event.data)) };
  const waiterIndex = waiters.findIndex(({ predicate }) => predicate(entry.message));
  if (waiterIndex >= 0) {
    const [waiter] = waiters.splice(waiterIndex, 1);
    clearTimeout(waiter.timeout);
    waiter.resolve(entry);
  } else {
    queued.push(entry);
  }
});

function nextMessage(predicate, timeoutMs = 12000) {
  const queuedIndex = queued.findIndex(({ message }) => predicate(message));
  if (queuedIndex >= 0) return Promise.resolve(queued.splice(queuedIndex, 1)[0]);
  return new Promise((resolve, reject) => {
    const waiter = {
      predicate,
      resolve,
      timeout: setTimeout(() => {
        const index = waiters.indexOf(waiter);
        if (index >= 0) waiters.splice(index, 1);
        reject(new Error("Timed out waiting for a paced bot action"));
      }, timeoutMs),
    };
    waiters.push(waiter);
  });
}

await nextMessage((message) => message.type === "connected");
socket.send(JSON.stringify({ type: "join", userId: "alice", name: "Alice" }));
await nextMessage((message) => message.type === "room_state" && message.room.players.length === 1);
socket.send(JSON.stringify({ type: "set_ready", ready: true }));
await nextMessage(
  (message) => message.type === "room_state" && message.room.players[0]?.ready === true,
);
socket.send(JSON.stringify({ type: "start_game", botSpeedScale: 0.65 }));
const initial = await nextMessage((message) => message.type === "game_state");
const localSeat = initial.message.game.localSeat;
const players = initial.message.game.players;

function hasCombo(hand) {
  const jokerCount = hand.filter((card) => card === "joker").length;
  const counts = new Map();
  for (const card of hand) {
    if (card === "joker") continue;
    const rank = card.slice(card.indexOf("_") + 1);
    counts.set(rank, (counts.get(rank) ?? 0) + 1);
  }
  const largestGroup = Math.max(0, ...counts.values());
  return largestGroup >= 4 || (jokerCount >= 1 && largestGroup >= 3);
}

function isBotAction(message) {
  if (message.type !== "game_state") return false;
  const event = message.game.lastEvent ?? {};
  if (event.type === "card_passed") return players[event.fromSeat]?.isBot === true;
  if (event.type === "slap") return players[event.seat]?.isBot === true;
  return false;
}

function respondForHuman(game) {
  if (game.phase !== "passing") return;
  if (hasCombo(game.hand)) {
    socket.send(JSON.stringify({ type: "slap" }));
  } else if (game.activeSeat === localSeat) {
    socket.send(JSON.stringify({ type: "pass_card", cardIndex: 0 }));
  }
}

let latestRevision = initial.message.game.revision;
const botEvents = [];
respondForHuman(initial.message.game);
while (botEvents.length < 2) {
  const entry = await nextMessage(
    (message) => message.type === "game_state" && message.game.revision > latestRevision,
  );
  latestRevision = entry.message.game.revision;
  if (isBotAction(entry.message)) botEvents.push(entry);
  respondForHuman(entry.message.game);
}

const [first, second] = botEvents;
const spacingMs = second.receivedAt - first.receivedAt;
assert.ok(spacingMs >= 200, `Expected paced bot events, received them only ${spacingMs} ms apart`);

socket.close();
console.log(`Pacing smoke test passed with ${spacingMs} ms between bot events for ${baseUrl}`);
