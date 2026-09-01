import { describe, expect, it } from "vitest";
import { TenkLobbyRoom } from "../src/tenk-room-state";

describe("Tenk browser lobby", () => {
  it("assigns a host, requires readiness, and seats up to eight players", () => {
    const room = new TenkLobbyRoom();
    for (let index = 1; index <= 8; index += 1) {
      room.join(`player-${index}`, `Player ${index}`, index);
      room.setReady(`player-${index}`, true);
    }
    expect(room.snapshot().hostId).toBe("player-1");
    expect(() => room.join("player-9", "Player 9", 9)).toThrowError("eight players");
    room.start("player-1");
    expect(room.snapshot()).toMatchObject({ phase: "playing" });
    expect(room.snapshot().players.map((player) => player.seat)).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });

  it("requires at least two ready players and migrates the host", () => {
    const room = new TenkLobbyRoom();
    room.join("one", "One", 1);
    room.setReady("one", true);
    expect(() => room.start("one")).toThrowError("At least two");
    room.join("two", "Two", 2);
    expect(() => room.start("one")).toThrowError("must be ready");
    room.disconnect("one");
    expect(room.snapshot().hostId).toBe("two");
  });
});
