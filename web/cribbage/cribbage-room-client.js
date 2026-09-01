const DEFAULT_CRIBBAGE_URL = "wss://gamerpub-multiplayer.joker-multiplayer.workers.dev/cribbage";

export function cribbageSocketUrl(identity, configuredUrl = DEFAULT_CRIBBAGE_URL) {
  const url = new URL(configuredUrl);
  if (url.protocol !== "wss:" && url.protocol !== "ws:") {
    throw new Error("The Cribbage room URL must use ws: or wss:.");
  }
  url.searchParams.set("user_id", identity.userId);
  url.searchParams.set("name", identity.name);
  return url.toString();
}

export class CribbageRoomClient {
  constructor({
    url = DEFAULT_CRIBBAGE_URL,
    socketFactory = (socketUrl) => new WebSocket(socketUrl),
    onStatus = () => {},
    onState = () => {},
    onGame = () => {},
    onError = () => {},
    reconnectDelayMs = 1200,
  } = {}) {
    this.url = url;
    this.socketFactory = socketFactory;
    this.onStatus = onStatus;
    this.onState = onState;
    this.onGame = onGame;
    this.onError = onError;
    this.reconnectDelayMs = reconnectDelayMs;
    this.socket = null;
    this.identity = null;
    this.manualClose = false;
    this.reconnectTimer = null;
  }

  connect(identity) {
    if (!identity?.userId || !identity?.name?.trim()) {
      throw new Error("Cribbage requires a player ID and display name.");
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

  setName(name) {
    const normalized = name?.trim();
    if (!normalized) return false;
    this.identity = { ...this.identity, name: normalized };
    return this.send("set_name", { name: normalized });
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
      const previous = this.socket;
      if (leave && previous.readyState === WebSocket.OPEN) previous.send(JSON.stringify({ type: "leave" }));
      this.socket = null;
      previous.close();
    }
    if (announce) this.onStatus("disconnected");
  }

  open() {
    if (!this.identity) return;
    const socket = this.socketFactory(cribbageSocketUrl(this.identity, this.url));
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
      try { message = JSON.parse(event.data); } catch {
        this.onError("The Cribbage server sent an invalid response.");
        return;
      }
      if (message.type === "room_state") this.onState(message.room);
      else if (message.type === "game_state") this.onGame(message.game);
      else if (message.type === "error") this.onError(message.message ?? "The Cribbage server reported an error.");
    });
    socket.addEventListener("error", () => {
      if (socket === this.socket) this.onError("Could not reach the Cribbage room.");
    });
    socket.addEventListener("close", () => {
      if (socket !== this.socket) return;
      this.socket = null;
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
