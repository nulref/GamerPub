import { describe, expect, it } from "vitest";
import { discordRoomAccessDecision } from "../src/room-access";

describe("Discord room host licensing", () => {
  it("lets an entitled user activate a new room", () => {
    expect(discordRoomAccessDecision(false, true)).toBe("activate");
  });

  it("holds an unpaid guest until a host activates the room", () => {
    expect(discordRoomAccessDecision(false, false)).toBe("wait_for_host");
  });

  it("admits unpaid guests after activation", () => {
    expect(discordRoomAccessDecision(true, false)).toBe("join");
  });
});
