import { describe, expect, it } from "vitest";
import {
  MAX_TENK_VOICE_PARTICIPANTS,
  TENK_ROOM_NAME,
  TENK_ROOM_PATH,
  TENK_VOICE_PATH,
  publicVoiceName,
  validPublicVoiceUserId,
} from "../src/public-voice";

describe("Tenk public voice room", () => {
  it("uses a dedicated endpoint, room, and eight-person limit", () => {
    expect(TENK_ROOM_PATH).toBe("/tenk");
    expect(TENK_VOICE_PATH).toBe("/voice/tenk");
    expect(TENK_ROOM_NAME).toBe("gamer-pub-tenk-room");
    expect(MAX_TENK_VOICE_PARTICIPANTS).toBe(8);
  });

  it("accepts bounded browser identities and normalizes display names", () => {
    expect(validPublicVoiceUserId("gamer_abcd-1234")).toBe(true);
    expect(validPublicVoiceUserId("bad id")).toBe(false);
    expect(publicVoiceName("  Player   One  ")).toBe("Player One");
    expect(publicVoiceName(" ")).toBeNull();
    expect(publicVoiceName("x".repeat(40))).toHaveLength(32);
  });
});
