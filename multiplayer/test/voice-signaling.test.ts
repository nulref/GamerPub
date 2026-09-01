import { describe, expect, it } from "vitest";
import { validVoicePeerId, validVoiceSignal } from "../src/voice-signaling";

describe("voice signaling validation", () => {
  it("accepts bounded descriptions and candidates", () => {
    expect(validVoiceSignal({
      kind: "description",
      description: { type: "offer", sdp: "v=0\r\n" },
    })).toBe(true);
    expect(validVoiceSignal({
      kind: "candidate",
      candidate: {
        candidate: "candidate:1 1 UDP 2122252543 192.0.2.1 54321 typ host",
        sdpMid: "0",
        sdpMLineIndex: 0,
      },
    })).toBe(true);
    expect(validVoiceSignal({ kind: "candidate", candidate: null })).toBe(true);
  });

  it("rejects malformed or excessive signaling payloads", () => {
    expect(validVoiceSignal({
      kind: "description",
      description: { type: "rollback", sdp: "v=0" },
    })).toBe(false);
    expect(validVoiceSignal({
      kind: "description",
      description: { type: "offer", sdp: "x".repeat(64 * 1024 + 1) },
    })).toBe(false);
    expect(validVoiceSignal({
      kind: "candidate",
      candidate: { candidate: "candidate", sdpMLineIndex: -1 },
    })).toBe(false);
  });

  it("accepts only server-style connection IDs as targets", () => {
    expect(validVoicePeerId("7d8fc082-0c12-4a3c-bffe-a89aef097861")).toBe(true);
    expect(validVoicePeerId("short")).toBe(false);
    expect(validVoicePeerId("peer id with spaces")).toBe(false);
  });
});
