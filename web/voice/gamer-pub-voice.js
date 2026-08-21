import { MicrophoneController } from "./microphone-controller.js";
import { VoiceChatClient } from "./voice-chat.js";
import { VoiceRoomClient } from "./voice-room-client.js";

const toolbar = document.querySelector("#tenk-voice-toolbar");
const microphoneButton = document.querySelector("#tenk-microphone-toggle");
const microphoneLabel = document.querySelector("#tenk-microphone-label");
const participantCount = document.querySelector("#tenk-voice-count");
const playbackButton = document.querySelector("#tenk-voice-playback");
const leaveButton = document.querySelector("#tenk-voice-leave");
const statusLabel = document.querySelector("#tenk-voice-status");
const remoteAudio = document.querySelector("#tenk-remote-audio");
const configuredUrl = document.querySelector('meta[name="gamer-pub-voice-url"]')?.content?.trim();
const PLAYER_ID_KEY = "gamer-pub.voice-player-id";

let visible = false;
let socketConnected = false;

function playerIdentity() {
  let userId = null;
  try {
    userId = localStorage.getItem(PLAYER_ID_KEY);
  } catch {
    // A session-only identity is enough when persistent storage is unavailable.
  }
  if (!userId || !/^[A-Za-z0-9_-]{1,64}$/.test(userId)) {
    const randomPart = globalThis.crypto?.randomUUID?.().replaceAll("-", "") ??
      Math.random().toString(36).slice(2);
    userId = `gamer_${randomPart}`.slice(0, 64);
    try {
      localStorage.setItem(PLAYER_ID_KEY, userId);
    } catch {
      // Keep the generated ID for this page session.
    }
  }
  const suffix = userId.slice(-4).toUpperCase();
  return { userId, name: `Player ${suffix}` };
}

const identity = playerIdentity();
const microphone = new MicrophoneController();
const roomClient = new VoiceRoomClient({
  ...(configuredUrl ? { url: configuredUrl } : {}),
  onStatus: (status) => {
    socketConnected = status === "connected";
    if (socketConnected) {
      voiceChat.setRoomState(
        { players: [{ id: identity.userId, connected: true, isBot: false }] },
        identity.userId,
      );
    } else if (status === "disconnected") {
      voiceChat.handleRoomDisconnect();
    }
    if (visible && (status === "connecting" || status === "reconnecting")) {
      setStatus(status === "connecting" ? "Connecting voice..." : "Reconnecting voice...");
    }
  },
  onVoice: (message) => {
    if (message.type === "voice_disconnected") voiceChat.handleRoomDisconnect();
    else void voiceChat.handleServerMessage(message);
  },
  onError: setStatus,
});

function setStatus(message = "") {
  statusLabel.textContent = message;
  statusLabel.hidden = !message;
}

function renderVoiceState(state) {
  const labels = {
    unavailable: "Connecting...",
    ready: "Join voice",
    joining: "Joining...",
    reconnecting: "Reconnecting...",
    active: "Mute",
    muted: "Unmute",
    error: "Retry voice",
  };
  const active = state.status === "active" || state.status === "muted";
  microphoneButton.dataset.status = state.status;
  microphoneButton.disabled = state.status === "unavailable" || state.status === "joining" ||
    state.status === "reconnecting";
  microphoneButton.setAttribute("aria-pressed", String(state.status === "muted"));
  microphoneButton.setAttribute("aria-label", labels[state.status] ?? "Voice chat");
  microphoneLabel.textContent = labels[state.status] ?? "Voice chat";
  leaveButton.hidden = !active;
  playbackButton.hidden = !state.playbackBlocked;
  participantCount.hidden = !active;
  participantCount.textContent = active ? `${state.participantCount}/8 in voice` : "";

  if (state.status === "active") {
    setStatus(state.relayAvailable ? "Voice connected" : "Voice connected directly");
  } else if (state.status === "muted") {
    setStatus("Microphone muted");
  } else if (state.status === "error") {
    setStatus(state.message ?? "Voice chat could not connect.");
  } else if (state.status === "ready") {
    setStatus("");
  }
}

const voiceChat = new VoiceChatClient({
  roomClient,
  microphone,
  audioContainer: remoteAudio,
  onState: renderVoiceState,
  onError: setStatus,
});
renderVoiceState(voiceChat.state());

function setVisible(nextVisible) {
  visible = Boolean(nextVisible);
  toolbar.hidden = !visible;
  if (visible) {
    if (!socketConnected && !roomClient.socket) roomClient.connect(identity);
  } else {
    voiceChat.leave();
    roomClient.disconnect();
    setStatus("");
  }
}

microphoneButton.addEventListener("click", () => void voiceChat.togglePrimary());
leaveButton.addEventListener("click", () => voiceChat.leave());
playbackButton.addEventListener("click", () => voiceChat.retryPlayback());
window.addEventListener("beforeunload", () => {
  voiceChat.destroy();
  roomClient.disconnect({ announce: false });
});

window.GamerPubVoice = { setVisible };
