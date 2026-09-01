const FALLBACK_ICE_SERVERS = [{ urls: ["stun:stun.cloudflare.com:3478"] }];

function validPeer(peer) {
  return peer && typeof peer.peerId === "string" && typeof peer.userId === "string";
}

export class VoiceChatClient {
  constructor({
    roomClient,
    microphone,
    audioContainer = null,
    peerConnectionFactory = (configuration) => new RTCPeerConnection(configuration),
    mediaStreamFactory = (tracks) => new MediaStream(tracks),
    audioElementFactory = () => document.createElement("audio"),
    webRtcSupported = typeof globalThis.RTCPeerConnection === "function",
    onState = () => {},
    onError = () => {},
    setTimeoutFn = setTimeout,
    clearTimeoutFn = clearTimeout,
  }) {
    this.roomClient = roomClient;
    this.microphone = microphone;
    this.audioContainer = audioContainer;
    this.peerConnectionFactory = peerConnectionFactory;
    this.mediaStreamFactory = mediaStreamFactory;
    this.audioElementFactory = audioElementFactory;
    this.webRtcSupported = webRtcSupported;
    this.onState = onState;
    this.onError = onError;
    this.setTimeoutFn = setTimeoutFn;
    this.clearTimeoutFn = clearTimeoutFn;
    this.roomAvailable = false;
    this.desiredJoined = false;
    this.joined = false;
    this.joinRequestPending = false;
    this.selfPeerId = null;
    this.iceServers = FALLBACK_ICE_SERVERS;
    this.relayAvailable = false;
    this.playbackBlocked = false;
    this.peers = new Map();
    this.knownPeers = new Map();
    this.lastError = null;

    this.unsubscribeMicrophone = microphone.subscribe?.(({ status }) => {
      if ((status === "idle" || status === "error" || status === "unsupported") &&
          this.desiredJoined && this.joined) {
        this.leave({ stopMicrophone: false });
        return;
      }
      this.emitState();
    });
  }

  state() {
    let status = "unavailable";
    if (this.lastError) status = "error";
    else if (this.joinRequestPending) status = "joining";
    else if (this.desiredJoined && !this.joined) status = "reconnecting";
    else if (this.joined && this.microphone.status === "muted") status = "muted";
    else if (this.joined) status = "active";
    else if (this.roomAvailable) status = "ready";

    return {
      status,
      participantCount: this.joined ? this.knownPeers.size : 0,
      relayAvailable: this.relayAvailable,
      playbackBlocked: this.playbackBlocked,
      message: this.lastError,
    };
  }

  emitState() {
    this.onState(this.state());
  }

  setRoomState(room, userId) {
    this.roomAvailable = Boolean(
      userId && room?.players?.some(
        (player) => player.id === userId && player.connected && !player.isBot,
      ),
    );
    if (!this.roomAvailable && this.desiredJoined) {
      this.leave();
      return;
    }
    if (this.roomAvailable && this.desiredJoined && !this.joined) this.requestServerJoin();
    this.emitState();
  }

  async join() {
    this.lastError = null;
    if (!this.roomAvailable) {
      this.fail("Join the multiplayer lobby before joining voice.");
      return false;
    }
    if (!this.webRtcSupported) {
      this.fail("Voice chat is not supported in this browser.");
      return false;
    }

    this.desiredJoined = true;
    this.joinRequestPending = true;
    this.emitState();
    if (!await this.microphone.enable()) {
      this.desiredJoined = false;
      this.joinRequestPending = false;
      this.fail(this.microphone.message);
      return false;
    }
    return this.requestServerJoin();
  }

  requestServerJoin() {
    if (!this.desiredJoined || !this.roomAvailable || this.joined) return false;
    this.joinRequestPending = true;
    const sent = this.roomClient.joinVoice();
    if (!sent) {
      this.joinRequestPending = false;
      this.emitState();
    }
    return sent;
  }

  async togglePrimary() {
    if (!this.joined) return this.join();
    const muted = this.microphone.status !== "muted";
    if (!this.microphone.setMuted(muted)) {
      this.fail("The microphone is no longer available.");
      return false;
    }
    this.lastError = null;
    this.emitState();
    return true;
  }

  leave({ notify = true, stopMicrophone = true } = {}) {
    if (notify && (this.joined || this.joinRequestPending)) this.roomClient.leaveVoice();
    this.desiredJoined = false;
    this.joined = false;
    this.joinRequestPending = false;
    this.selfPeerId = null;
    this.knownPeers.clear();
    this.closeAllPeers();
    this.playbackBlocked = false;
    if (stopMicrophone) this.microphone.disable();
    this.emitState();
  }

  handleRoomDisconnect() {
    if (!this.desiredJoined) return;
    this.joined = false;
    this.joinRequestPending = false;
    this.selfPeerId = null;
    this.knownPeers.clear();
    this.closeAllPeers();
    this.emitState();
  }

  async handleServerMessage(message) {
    try {
      if (message?.type === "voice_config") {
        if (!this.desiredJoined) {
          this.roomClient.leaveVoice();
          return;
        }
        if (typeof message.selfPeerId !== "string" || !Array.isArray(message.iceServers)) {
          throw new Error("The voice server returned an invalid configuration.");
        }
        this.selfPeerId = message.selfPeerId;
        this.iceServers = message.iceServers.length > 0 ? message.iceServers : FALLBACK_ICE_SERVERS;
        this.relayAvailable = message.relayAvailable === true;
        this.joined = true;
        this.joinRequestPending = false;
        this.lastError = null;
        this.emitState();
      } else if (message?.type === "voice_presence") {
        await this.updatePresence(message.peers);
      } else if (message?.type === "voice_signal") {
        await this.acceptSignal(message.fromPeerId, message.signal);
      } else if (message?.type === "voice_error") {
        if (this.joinRequestPending && !this.joined) {
          this.desiredJoined = false;
          this.joinRequestPending = false;
          this.microphone.disable();
          this.fail(message.message ?? "Voice chat could not be joined.");
        } else {
          this.onError(message.message ?? "Voice chat reported an error.");
        }
      }
    } catch (error) {
      this.fail(error instanceof Error ? error.message : "Voice chat could not process a server message.");
    }
  }

  async updatePresence(peers) {
    if (!this.joined || !Array.isArray(peers)) return;
    const nextPeers = new Map(peers.filter(validPeer).map((peer) => [peer.peerId, peer]));
    if (this.selfPeerId && !nextPeers.has(this.selfPeerId)) {
      nextPeers.set(this.selfPeerId, { peerId: this.selfPeerId, userId: "self", name: "You" });
    }
    for (const peerId of this.peers.keys()) {
      if (!nextPeers.has(peerId)) this.closePeer(peerId);
    }
    this.knownPeers = nextPeers;
    for (const peerId of nextPeers.keys()) {
      if (peerId !== this.selfPeerId) await this.ensurePeer(peerId, true);
    }
    this.emitState();
  }

  async ensurePeer(peerId, mayInitiate) {
    if (this.peers.has(peerId)) return this.peers.get(peerId);
    if (!this.microphone.stream || !this.selfPeerId) return null;

    const connection = this.peerConnectionFactory({ iceServers: this.iceServers });
    const peer = {
      connection,
      pendingCandidates: [],
      makingOffer: false,
      ignoreOffer: false,
      restartTimer: null,
      audio: null,
    };
    this.peers.set(peerId, peer);
    for (const track of this.microphone.stream.getAudioTracks?.() ?? []) {
      connection.addTrack(track, this.microphone.stream);
    }
    connection.onicecandidate = (event) => {
      const candidate = event.candidate?.toJSON?.() ?? event.candidate ?? null;
      this.roomClient.sendVoiceSignal(peerId, { kind: "candidate", candidate });
    };
    connection.ontrack = (event) => void this.attachRemoteAudio(peerId, event);
    connection.onconnectionstatechange = () => this.handleConnectionState(peerId);

    if (mayInitiate && this.selfPeerId.localeCompare(peerId) < 0) await this.makeOffer(peerId);
    return peer;
  }

  async makeOffer(peerId, iceRestart = false) {
    const peer = this.peers.get(peerId);
    if (!peer || peer.makingOffer || peer.connection.signalingState !== "stable") return;
    peer.makingOffer = true;
    try {
      const offer = await peer.connection.createOffer(iceRestart ? { iceRestart: true } : undefined);
      await peer.connection.setLocalDescription(offer);
      const description = peer.connection.localDescription ?? offer;
      this.roomClient.sendVoiceSignal(peerId, {
        kind: "description",
        description: { type: description.type, sdp: description.sdp ?? "" },
      });
    } finally {
      peer.makingOffer = false;
    }
  }

  async acceptSignal(peerId, signal) {
    if (!this.joined || typeof peerId !== "string" || !signal) return;
    const peer = await this.ensurePeer(peerId, false);
    if (!peer) return;
    const connection = peer.connection;

    if (signal.kind === "description") {
      const description = signal.description;
      const offerCollision = description?.type === "offer" &&
        (peer.makingOffer || connection.signalingState !== "stable");
      const polite = this.selfPeerId.localeCompare(peerId) > 0;
      peer.ignoreOffer = !polite && offerCollision;
      if (peer.ignoreOffer) return;

      if (offerCollision && polite) await connection.setLocalDescription({ type: "rollback" });

      await connection.setRemoteDescription(description);
      for (const candidate of peer.pendingCandidates.splice(0)) {
        await connection.addIceCandidate(candidate);
      }
      if (description.type === "offer") {
        const answer = await connection.createAnswer();
        await connection.setLocalDescription(answer);
        const localDescription = connection.localDescription ?? answer;
        this.roomClient.sendVoiceSignal(peerId, {
          kind: "description",
          description: { type: localDescription.type, sdp: localDescription.sdp ?? "" },
        });
      }
    } else if (signal.kind === "candidate") {
      if (peer.ignoreOffer) return;
      if (!connection.remoteDescription) peer.pendingCandidates.push(signal.candidate);
      else await connection.addIceCandidate(signal.candidate);
    }
  }

  async attachRemoteAudio(peerId, event) {
    const peer = this.peers.get(peerId);
    if (!peer) return;
    const audio = peer.audio ?? this.audioElementFactory();
    audio.autoplay = true;
    audio.playsInline = true;
    audio.dataset.voicePeerId = peerId;
    audio.srcObject = event.streams?.[0] ?? this.mediaStreamFactory([event.track]);
    if (!peer.audio) this.audioContainer?.append(audio);
    peer.audio = audio;
    try {
      await audio.play?.();
    } catch {
      this.playbackBlocked = true;
      this.emitState();
    }
  }

  async retryPlayback() {
    let blocked = false;
    for (const peer of this.peers.values()) {
      if (!peer.audio) continue;
      try {
        await peer.audio.play?.();
      } catch {
        blocked = true;
      }
    }
    this.playbackBlocked = blocked;
    this.emitState();
    return !blocked;
  }

  handleConnectionState(peerId) {
    const peer = this.peers.get(peerId);
    if (!peer) return;
    const state = peer.connection.connectionState;
    if (state === "failed") {
      void this.makeOffer(peerId, true);
    } else if (state === "disconnected" && peer.restartTimer === null) {
      peer.restartTimer = this.setTimeoutFn(() => {
        peer.restartTimer = null;
        if (peer.connection.connectionState === "disconnected") void this.makeOffer(peerId, true);
      }, 4000);
    } else if (state === "closed") {
      this.closePeer(peerId);
    }
  }

  closePeer(peerId) {
    const peer = this.peers.get(peerId);
    if (!peer) return;
    this.peers.delete(peerId);
    if (peer.restartTimer !== null) this.clearTimeoutFn(peer.restartTimer);
    peer.connection.close();
    if (peer.audio) {
      peer.audio.pause?.();
      peer.audio.srcObject = null;
      peer.audio.remove?.();
    }
  }

  closeAllPeers() {
    for (const peerId of [...this.peers.keys()]) this.closePeer(peerId);
  }

  fail(message) {
    this.lastError = message;
    this.onError(message);
    this.emitState();
  }

  destroy() {
    this.leave({ notify: false });
    this.unsubscribeMicrophone?.();
  }
}

