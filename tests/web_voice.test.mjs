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

  close() {
    this.readyState = 3;
    this.dispatchEvent(new Event("close"));
  }
}

test("builds the dedicated Tenk voice URL with browser identity", () => {
  const url = new URL(tenkVoiceSocketUrl(
    { userId: "gamer_abcd", name: "Player ABCD" },
    "wss://voice.example/voice/tenk",
  ));
  assert.equal(url.pathname, "/voice/tenk");
  assert.equal(url.searchParams.get("user_id"), "gamer_abcd");
  assert.equal(url.searchParams.get("name"), "Player ABCD");
});

test("sends only voice protocol messages after the socket connects", () => {
  const previousWebSocket = globalThis.WebSocket;
  globalThis.WebSocket = FakeSocket;
  try {
    let socket;
    const statuses = [];
    const client = new VoiceRoomClient({
      url: "wss://voice.example/voice/tenk",
      socketFactory: (url) => {
        socket = new FakeSocket(url);
        return socket;
      },
      onStatus: (status) => statuses.push(status),
    });
    client.connect({ userId: "gamer_abcd", name: "Player ABCD" });
    assert.deepEqual(statuses, ["connecting"]);
    assert.equal(client.joinVoice(), false);
    socket.open();
    assert.equal(client.joinVoice(), true);
    assert.equal(client.sendVoiceSignal("peer-id", { kind: "candidate", candidate: null }), true);
    assert.deepEqual(socket.sent, [
      { type: "voice_join" },
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
