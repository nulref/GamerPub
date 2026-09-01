export class RoomClient {
  constructor({
    socketFactory = (url) => new WebSocket(url),
    urlFactory,
    onStatus = () => {},
    onState = () => {},
    onGame = () => {},
    onHostAccessRequired = () => {},
    onError = () => {},
    reconnectDelayMs = 1200,
  } = {}) {
    this.socketFactory = socketFactory;
    this.urlFactory = urlFactory;
    this.onStatus = onStatus;
    this.onState = onState;
    this.onGame = onGame;
    this.onHostAccessRequired = onHostAccessRequired;
    this.onError = onError;
    this.reconnectDelayMs = reconnectDelayMs;
    this.socket = null;
    this.identity = null;
    this.manualClose = false;
    this.reconnectTimer = null;
  }

  connect(identity) {
    if (!identity?.instanceId || !identity?.userId || !identity?.name?.trim() ||
        !identity?.sessionToken) {
      throw new Error("The Discord room requires an authenticated Activity identity.");
    }
    this.disconnect({ announce: false, leave: false });
    this.identity = { ...identity, name: identity.name.trim() };
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
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      this.onError("The multiplayer room is not connected yet.");
      return false;
    }
    this.socket.send(JSON.stringify({ type, ...payload }));
    return true;
  }

  disconnect({ leave = true, announce = true } = {}) {
    this.manualClose = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket) {
      const previous = this.socket;
      if (leave && previous.readyState === WebSocket.OPEN) {
        previous.send(JSON.stringify({ type: "leave" }));
      }
      this.socket = null;
      previous.close();
    }
    if (announce) this.onStatus("disconnected");
  }

  open() {
    const socket = this.socketFactory(this.urlFactory(this.identity.instanceId));
    this.socket = socket;
    this.onStatus("connecting");
    socket.addEventListener("open", () => {
      if (socket !== this.socket) return;
      socket.send(JSON.stringify({
        type: "join",
        userId: this.identity.userId,
        name: this.identity.name,
        sessionToken: this.identity.sessionToken,
      }));
      this.onStatus("connected");
    });
    socket.addEventListener("message", (event) => {
      if (socket !== this.socket) return;
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        this.onError("The multiplayer server sent an invalid response.");
        return;
      }
      if (message.type === "room_state") this.onState(message.room);
      else if (message.type === "game_state") this.onGame(message.game);
      else if (message.type === "host_license_required") this.onHostAccessRequired(message);
      else if (message.type === "error") {
        this.onError(message.message ?? "The multiplayer server reported an error.");
      }
    });
    socket.addEventListener("error", () => {
      if (socket === this.socket) this.onError("Could not reach the multiplayer server.");
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
