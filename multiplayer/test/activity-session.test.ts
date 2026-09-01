import { describe, expect, it } from "vitest";
import {
  ActivitySessionError,
  signActivitySession,
  verifyActivitySession,
} from "../src/activity-session";

const secret = "test-session-secret-with-at-least-thirty-two-characters";
const identity = {
  userId: "1537971830701293720",
  instanceId: "activity-instance-123",
  canHost: true,
};

describe("activity sessions", () => {
  it("signs and verifies a room-bound host identity", async () => {
    const token = await signActivitySession(identity, secret, 1_000, 10_000);
    await expect(verifyActivitySession(token, secret, identity.instanceId, 2_000)).resolves.toMatchObject(identity);
  });

  it("rejects tampering, expiration, and use in another room", async () => {
    const token = await signActivitySession(identity, secret, 1_000, 1_000);
    const tampered = `${token.slice(0, -1)}${token.endsWith("a") ? "b" : "a"}`;
    await expect(verifyActivitySession(tampered, secret, identity.instanceId, 1_500))
      .rejects.toBeInstanceOf(ActivitySessionError);
    await expect(verifyActivitySession(token, secret, identity.instanceId, 2_000))
      .rejects.toThrow("expired");
    await expect(verifyActivitySession(token, secret, "another-instance", 1_500))
      .rejects.toThrow("another room");
  });
});
