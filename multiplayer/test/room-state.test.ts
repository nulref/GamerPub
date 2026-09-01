import { describe, expect, it } from "vitest";
import { LobbyRoom, RoomCommandError } from "../src/room-state";

describe("LobbyRoom", () => {
  it("makes the first connected player host", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice", 10);
    room.join("two", "Bob", 20);

    expect(room.snapshot().hostId).toBe("one");
    expect(room.snapshot().players).toHaveLength(2);
  });

  it("migrates the host when the current host disconnects", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice", 10);
    room.join("two", "Bob", 20);
    room.disconnect("one");

    expect(room.snapshot().hostId).toBe("two");
    expect(room.snapshot().players[0].ready).toBe(false);
  });

  it("requires every connected human to be ready", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice");
    room.join("two", "Bob");
    room.setReady("one", true);

    expect(() => room.start("one")).toThrowError(RoomCommandError);
    expect(room.snapshot().phase).toBe("waiting");
  });

  it("fills empty seats with bots when the host starts", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice", 10);
    room.join("two", "Bob", 20);
    room.setReady("one", true);
    room.setReady("two", true);
    room.start("one", 30);

    const snapshot = room.snapshot();
    expect(snapshot.phase).toBe("playing");
    expect(snapshot.players).toHaveLength(4);
    expect(snapshot.players.filter((player) => player.isBot)).toHaveLength(2);
    expect(snapshot.players.map((player) => player.seat)).toEqual([0, 1, 2, 3]);
  });

  it("rejects start commands from a non-host", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice");
    room.join("two", "Bob");
    room.setReady("one", true);
    room.setReady("two", true);

    expect(() => room.start("two")).toThrowError("Only the lobby host");
  });

  it("allows a disconnected player to reconnect to a running room", () => {
    const room = new LobbyRoom();
    room.join("one", "Alice");
    room.setReady("one", true);
    room.start("one");
    room.disconnect("one");
    room.join("one", "Alice Again");

    const alice = room.snapshot().players.find((player) => player.id === "one");
    expect(alice?.connected).toBe(true);
    expect(alice?.name).toBe("Alice Again");
  });
});
