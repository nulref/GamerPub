const DEFAULT_VOICE_URL = "wss://gamerpub-multiplayer.joker-multiplayer.workers.dev/tenk";

export function tenkVoiceSocketUrl(identity, configuredUrl = DEFAULT_VOICE_URL) {
  const url = new URL(configuredUrl);
  if (url.protocol !== "wss:" && url.protocol !== "ws:") {
    throw new Error("The Tenk voice URL must use ws: or wss:.");
  }
  url.searchParams.set("user_id", identity.userId);
  url.searchParams.set("name", identity.name);
  return url.toString();
}

export class VoiceRoomClient {
  constructor({
    url = DEFAULT_VOICE_URL,
    socketFactory = (socketUrl) => new WebSocket(socketUrl),
    onStatus = () => {},
    onState = () => {},
    onGame = () => {},
    onVoice = () => {},
    onError = () => {},
    reconnectDelayMs = 1200,
  } = {}) {
    this.url = url;
    this.socketFactory = socketFactory;
    this.onStatus = onStatus;
    this.onState = onState;
    this.onGame = onGame;
    this.onVoice = onVoice;
    this.onError = onError;
    this.reconnectDelayMs = reconnectDelayMs;
    this.socket = null;
    this.identity = null;
    this.manualClose = false;
    this.reconnectTimer = null;
    this.roomState = null;
  }

  connect(identity) {
    if (!identity?.userId || !identity?.name?.trim()) {
      throw new Error("Voice connection requires a user ID and display name.");
    }
    this.disconnect({ announce: false });
    this.identity = {
      userId: identity.userId,
      name: identity.name.trim(),
      ...(identity.sessionToken ? { sessionToken: identity.sessionToken } : {}),
    };
    this.manualClose = false;
    this.open();
  }

  joinVoice() {
    return this.send("voice_join");
  }

  leaveVoice() {
    return this.send("voice_leave");
  }

  sendVoiceSignal(targetPeerId, signal) {
    return this.send("voice_signal", { targetPeerId, signal });
  }

  setName(name) {
    const normalized = name?.trim();
    if (!normalized) return false;
    this.identity = { ...this.identity, name: normalized };
    return this.send("set_name", { name: normalized });
  }

  setReady(ready) {
    return this.send("set_ready", { ready: Boolean(ready) });
  }

  startGame() {
    return this.send("start_game");
  }

  roll() {
    return this.send("roll");
  }

  setSelection(selectedIndices) {
    return this.send("set_selection", { selectedIndices });
  }

  reroll(selectedIndices) {
    return this.send("reroll", { selectedIndices });
  }

  keep(selectedIndices) {
    return this.send("keep", { selectedIndices });
  }

  nextPlayer() {
    return this.send("next_player");
  }

  resetGame() {
    return this.send("reset_game");
  }

  send(type, payload = {}) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return false;
    this.socket.send(JSON.stringify({ type, ...payload }));
    return true;
  }

  disconnect({ announce = true, leave = true } = {}) {
    this.manualClose = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket) {
      const oldSocket = this.socket;
      if (leave && oldSocket.readyState === WebSocket.OPEN) {
        oldSocket.send(JSON.stringify({ type: "leave" }));
      }
      this.socket = null;
      oldSocket.close();
    }
    if (announce) this.onStatus("disconnected");
  }

  open() {
    if (!this.identity) return;
    const socket = this.socketFactory(tenkVoiceSocketUrl(this.identity, this.url));
    this.socket = socket;
    this.onStatus("connecting");

    socket.addEventListener("open", () => {
      if (socket !== this.socket) return;
      if (this.identity.sessionToken) {
        socket.send(JSON.stringify({
          type: "join",
          userId: this.identity.userId,
          name: this.identity.name,
          sessionToken: this.identity.sessionToken,
        }));
      }
      this.onStatus("connected");
    });
    socket.addEventListener("message", (event) => {
      if (socket !== this.socket) return;
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        this.onError("The voice server sent an invalid response.");
        return;
      }
      if (message.type === "room_state") {
        this.roomState = message.room;
        this.onState(message.room);
      } else if (message.type === "game_state") {
        this.onGame(message.game);
      } else if (message.type === "voice_config" || message.type === "voice_presence" ||
          message.type === "voice_signal") {
        this.onVoice(message);
      } else if (message.type === "error") {
        this.onVoice({
          type: "voice_error",
          code: message.code,
          message: message.message ?? "The voice server reported an error.",
        });
      }
    });
    socket.addEventListener("error", () => {
      if (socket === this.socket) this.onError("Could not reach the Tenk voice server.");
    });
    socket.addEventListener("close", () => {
      if (socket !== this.socket) return;
      this.socket = null;
      this.onVoice({ type: "voice_disconnected" });
      this.onStatus("disconnected");
      if (!this.manualClose && this.identity) {
        this.onStatus("reconnecting");
        this.reconnectTimer = setTimeout(() => {
          this.reconnectTimer = null;
          if (!this.manualClose && !this.socket) this.open();
        }, this.reconnectDelayMs);
      }
    });
  }
}
