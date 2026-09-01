import assert from "node:assert/strict";
import test from "node:test";
import { CribbageRoomClient, cribbageSocketUrl } from "../web/cribbage/cribbage-room-client.js";

class FakeSocket extends EventTarget {
  static OPEN = 1;
  constructor(url) {
    super();
    this.url = url;
    this.readyState = 0;
    this.sent = [];
  }
  open() { this.readyState = FakeSocket.OPEN; this.dispatchEvent(new Event("open")); }
  send(value) { this.sent.push(JSON.parse(value)); }
  receive(value) { this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(value) })); }
  close() { this.readyState = 3; this.dispatchEvent(new Event("close")); }
}

test("builds a browser Cribbage room URL", () => {
  const url = new URL(cribbageSocketUrl({ userId: "crib_123", name: "Peggy" }, "wss://example.test/cribbage"));
  assert.equal(url.pathname, "/cribbage");
  assert.equal(url.searchParams.get("user_id"), "crib_123");
  assert.equal(url.searchParams.get("name"), "Peggy");
});

test("routes room, private game, commands, and server errors", () => {
  const previous = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const rooms = [];
    const games = [];
    const errors = [];
    const client = new CribbageRoomClient({
      url: "wss://example.test/cribbage",
      socketFactory: (url) => (socket = new FakeSocket(url)),
      onState: (room) => rooms.push(room),
      onGame: (game) => games.push(game),
      onError: (message) => errors.push(message),
    });
    client.connect({ userId: "crib_123", name: "Peggy" });
    socket.open();
    socket.receive({ type: "room_state", room: { phase: "waiting" } });
    socket.receive({ type: "game_state", game: { hand: [{ rank: 5 }] } });
    socket.receive({ type: "error", message: "Choose exactly one card." });
    assert.equal(rooms[0].phase, "waiting");
    assert.equal(games[0].hand[0].rank, 5);
    assert.equal(errors[0], "Choose exactly one card.");
    assert.equal(client.send("discard", { cardIndices: [1] }), true);
    assert.deepEqual(socket.sent, [{ type: "discard", cardIndices: [1] }]);
    client.disconnect();
  } finally {
    globalThis.WebSocket = previous;
  }
});

test("authenticates a Discord Cribbage socket on open", () => {
  const previous = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const client = new CribbageRoomClient({
      url: "wss://123.discordsays.com/api/cribbage?instance_id=room",
      socketFactory: (url) => (socket = new FakeSocket(url)),
    });
    client.connect({ userId: "123456", name: "Discord Player", sessionToken: "signed.session" });
    socket.open();
    assert.deepEqual(socket.sent, [{
      type: "join",
      userId: "123456",
      name: "Discord Player",
      sessionToken: "signed.session",
    }]);
  } finally {
    globalThis.WebSocket = previous;
  }
});
