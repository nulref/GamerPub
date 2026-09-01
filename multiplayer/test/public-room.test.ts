import { describe, expect, it } from "vitest";
import {
  PUBLIC_ROOM_NAME,
  PUBLIC_ROOM_PATH,
  configuredPublicOrigins,
  publicOriginAllowed,
} from "../src/public-room";

describe("public web room", () => {
  it("uses one stable Durable Object name and endpoint", () => {
    expect(PUBLIC_ROOM_NAME).toBe("public-web-lobby");
    expect(PUBLIC_ROOM_PATH).toBe("/public");
  });

  it("accepts the configured production origin", () => {
    expect(
      publicOriginAllowed(
        "https://gamerpub.netlify.app",
        "https://gamerpub.netlify.app",
      ),
    ).toBe(true);
  });

  it("accepts any origin in a comma-separated production allowlist", () => {
    const origins = "https://gamerpub.netlify.app, https://1540543783626870804.discordsays.com";
    expect(configuredPublicOrigins(origins)).toEqual([
      "https://gamerpub.netlify.app",
      "https://1540543783626870804.discordsays.com",
    ]);
    expect(publicOriginAllowed("https://gamerpub.netlify.app", origins)).toBe(true);
  });

  it("accepts HTTP localhost for development", () => {
    expect(
      publicOriginAllowed("http://127.0.0.1:5173", "https://gamerpub.netlify.app"),
    ).toBe(true);
  });

  it("rejects missing, malformed, and unrelated origins", () => {
    expect(publicOriginAllowed(null, "https://gamerpub.netlify.app")).toBe(false);
    expect(publicOriginAllowed("not-a-url", "https://gamerpub.netlify.app")).toBe(false);
    expect(
      publicOriginAllowed("https://example.com", "https://gamerpub.netlify.app"),
    ).toBe(false);
  });
});
