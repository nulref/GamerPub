import assert from "node:assert/strict";
import test from "node:test";
import { RoomClient } from "../src/room-client.js";

class FakeSocket extends EventTarget {
  static OPEN = 1;

  constructor(url) {
    super();
    this.url = url;
    this.readyState = 0;
    this.sent = [];
  }

  open() {
    this.readyState = FakeSocket.OPEN;
    this.dispatchEvent(new Event("open"));
  }

  send(raw) {
    this.sent.push(JSON.parse(raw));
  }

  receive(message) {
    this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(message) }));
  }

  close() {
    this.readyState = 3;
  }
}

test("authenticates and routes a Discord Joker room", () => {
  const previousWebSocket = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const roomStates = [];
    const gameStates = [];
    const client = new RoomClient({
      urlFactory: (instanceId) => `wss://example.test/api/socket?instance_id=${instanceId}`,
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      onState: (room) => roomStates.push(room),
      onGame: (game) => gameStates.push(game),
    });
    client.connect({
      instanceId: "activity-instance",
      userId: "123456789012345678",
      name: "Discord Player",
      sessionToken: "signed.activity.session",
    });
    socket.open();
    socket.receive({ type: "room_state", room: { phase: "waiting" } });
    socket.receive({ type: "game_state", game: { phase: "playing" } });
    assert.deepEqual(socket.sent[0], {
      type: "join",
      userId: "123456789012345678",
      name: "Discord Player",
      sessionToken: "signed.activity.session",
    });
    assert.equal(roomStates[0].phase, "waiting");
    assert.equal(gameStates[0].phase, "playing");
  } finally {
    globalThis.WebSocket = previousWebSocket;
  }
});
