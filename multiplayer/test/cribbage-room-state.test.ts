import { describe, expect, it } from "vitest";
import { CribbageLobbyRoom } from "../src/cribbage-room-state";

describe("Cribbage lobby", () => {
  it("requires the host configuration, exact seats, and ready-up", () => {
    const room = new CribbageLobbyRoom();
    room.join("host", "Host", 1);
    room.join("partner", "Partner", 2);
    room.configure("host", "partnership", 2);
    room.setReady("host", true);
    room.setReady("partner", true);
    room.start("host");
    expect(room.snapshot()).toMatchObject({
      phase: "playing",
      mode: "partnership",
      playerCount: 2,
    });
  });

  it("rejects invalid mode/player-count combinations", () => {
    const room = new CribbageLobbyRoom();
    room.join("host", "Host", 1);
    expect(() => room.configure("host", "variant", 4)).toThrow(/valid Cribbage mode/i);
  });
});
