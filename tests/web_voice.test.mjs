import assert from "node:assert/strict";
import test from "node:test";
import { VoiceRoomClient, tenkVoiceSocketUrl } from "../web/voice/voice-room-client.js";

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

  send(message) {
    this.sent.push(JSON.parse(message));
  }

  receive(message) {
    this.dispatchEvent(new MessageEvent("message", { data: JSON.stringify(message) }));
  }

  close() {
    this.readyState = 3;
    this.dispatchEvent(new Event("close"));
  }
}

test("builds the dedicated Tenk voice URL with browser identity", () => {
  const url = new URL(tenkVoiceSocketUrl(
    { userId: "gamer_abcd", name: "Player ABCD" },
    "wss://voice.example/tenk",
  ));
  assert.equal(url.pathname, "/tenk");
  assert.equal(url.searchParams.get("user_id"), "gamer_abcd");
  assert.equal(url.searchParams.get("name"), "Player ABCD");
});

test("routes Tenk lobby, game, and voice messages after the socket connects", () => {
  const previousWebSocket = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const statuses = [];
    const roomStates = [];
    const gameStates = [];
    const client = new VoiceRoomClient({
      url: "wss://voice.example/tenk",
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      onStatus: (status) => statuses.push(status),
      onState: (room) => roomStates.push(room),
      onGame: (game) => gameStates.push(game),
    });
    client.connect({ userId: "gamer_abcd", name: "Player ABCD" });
    assert.deepEqual(statuses, ["connecting"]);
    assert.equal(client.joinVoice(), false);
    socket.open();
    socket.receive({ type: "room_state", room: { phase: "waiting", players: [] } });
    socket.receive({ type: "game_state", game: { currentPlayer: 0 } });
    assert.equal(roomStates[0].phase, "waiting");
    assert.equal(gameStates[0].currentPlayer, 0);
    assert.equal(client.joinVoice(), true);
    assert.equal(client.setReady(true), true);
    assert.equal(client.roll(), true);
    assert.equal(client.setSelection([0, 4]), true);
    assert.equal(client.sendVoiceSignal("peer-id", { kind: "candidate", candidate: null }), true);
    assert.deepEqual(socket.sent, [
      { type: "voice_join" },
      { type: "set_ready", ready: true },
      { type: "roll" },
      { type: "set_selection", selectedIndices: [0, 4] },
      {
        type: "voice_signal",
        targetPeerId: "peer-id",
        signal: { kind: "candidate", candidate: null },
      },
    ]);
    client.disconnect();
  } finally {
    globalThis.WebSocket = previousWebSocket;
  }
});

test("authenticates an Activity Tenk socket immediately after opening", () => {
  const previousWebSocket = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const client = new VoiceRoomClient({
      url: "wss://123.discordsays.com/api/tenk?instance_id=activity-room",
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
    });
    client.connect({
      userId: "123456789012345678",
      name: "Discord Player",
      sessionToken: "signed.activity.session",
    });
    socket.open();
    assert.deepEqual(socket.sent, [{
      type: "join",
      userId: "123456789012345678",
      name: "Discord Player",
      sessionToken: "signed.activity.session",
    }]);
  } finally {
    globalThis.WebSocket = previousWebSocket;
  }
});
