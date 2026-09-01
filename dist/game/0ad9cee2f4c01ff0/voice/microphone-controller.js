const DEFAULT_AUDIO_CONSTRAINTS = {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
};

function microphoneErrorMessage(error) {
  switch (error?.name) {
    case "NotAllowedError":
    case "SecurityError":
      return "Microphone access was blocked. Allow it in your browser's site settings and try again.";
    case "NotFoundError":
      return "No microphone was found on this device.";
    case "NotReadableError":
    case "AbortError":
      return "The microphone is busy or could not be started.";
    default:
      return "The microphone could not be started.";
  }
}

export class MicrophoneController {
  constructor({
    mediaDevices = globalThis.navigator?.mediaDevices,
    onState = () => {},
  } = {}) {
    this.mediaDevices = mediaDevices;
    this.onState = onState;
    this.listeners = new Set();
    this.stream = null;
    this.status = "idle";
    this.message = "Microphone off";
  }

  emitState() {
    const state = { status: this.status, message: this.message };
    this.onState(state);
    for (const listener of this.listeners) listener(state);
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  setState(status, message) {
    this.status = status;
    this.message = message;
    this.emitState();
  }

  async enable() {
    if (this.status === "active" || this.status === "muted") return true;
    if (!this.mediaDevices?.getUserMedia) {
      this.setState("unsupported", "Microphone access is not supported in this browser.");
      return false;
    }

    this.setState("requesting", "Waiting for microphone permission...");
    try {
      const stream = await this.mediaDevices.getUserMedia({
        audio: DEFAULT_AUDIO_CONSTRAINTS,
        video: false,
      });
      const audioTrack = stream.getAudioTracks?.()[0];
      if (!audioTrack) {
        for (const track of stream.getTracks?.() ?? []) track.stop();
        throw new DOMException("No audio track was returned", "NotFoundError");
      }

      this.stream = stream;
      audioTrack.addEventListener?.("ended", () => {
        if (this.stream !== stream) return;
        this.stream = null;
        this.setState("idle", "Microphone off");
      });
      this.setState("active", "Microphone on");
      return true;
    } catch (error) {
      this.stream = null;
      this.setState("error", microphoneErrorMessage(error));
      return false;
    }
  }

  disable() {
    const stream = this.stream;
    this.stream = null;
    for (const track of stream?.getTracks?.() ?? []) track.stop();
    this.setState("idle", "Microphone off");
  }

  setMuted(muted) {
    if (!this.stream || (this.status !== "active" && this.status !== "muted")) return false;
    for (const track of this.stream.getAudioTracks?.() ?? []) track.enabled = !muted;
    this.setState(muted ? "muted" : "active", muted ? "Microphone muted" : "Microphone on");
    return true;
  }

  async toggle() {
    if (this.status === "active" || this.status === "muted") {
      this.disable();
      return false;
    }
    if (this.status === "requesting") return false;
    return this.enable();
  }
}

