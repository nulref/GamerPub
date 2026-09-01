import { describe, expect, it, vi } from "vitest";
import {
  fetchDiscordUser,
  parseComplimentaryHostUserIds,
  userCanHostDiscordRoom,
} from "../src/discord-premium";

const config = {
  applicationId: "1537971830701293720",
  botToken: "server-only-bot-token",
  hostSkuId: "1539068279992229988",
};
const userId = "1537971830701293721";

describe("Discord premium access", () => {
  it("derives identity from Discord instead of the browser", async () => {
    const fetcher = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      expect(new Headers(init?.headers).get("Authorization")).toBe("Bearer oauth-access-token");
      return Response.json({ id: userId, username: "Ace" });
    });
    await expect(fetchDiscordUser("oauth-access-token", fetcher as typeof fetch))
      .resolves.toMatchObject({ id: userId });
  });

  it("accepts an active entitlement for the configured durable SKU", async () => {
    const fetcher = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      const parsed = new URL(String(url));
      expect(parsed.searchParams.get("user_id")).toBe(userId);
      expect(parsed.searchParams.get("sku_ids")).toBe(config.hostSkuId);
      expect(parsed.searchParams.get("exclude_ended")).toBe("true");
      expect(new Headers(init?.headers).get("Authorization")).toBe(`Bot ${config.botToken}`);
      return Response.json([{ sku_id: config.hostSkuId, user_id: userId, deleted: false }]);
    });
    await expect(userCanHostDiscordRoom(userId, config, fetcher as typeof fetch)).resolves.toBe(true);
  });

  it("grants an allowlisted user without calling Discord's entitlement API", async () => {
    const fetcher = vi.fn();
    const complimentaryConfig = {
      applicationId: "",
      botToken: "",
      hostSkuId: "",
      complimentaryHostUserIds: `1537971830701293799,\n${userId}`,
    };
    await expect(userCanHostDiscordRoom(userId, complimentaryConfig, fetcher as typeof fetch))
      .resolves.toBe(true);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it("accepts comma or whitespace separated allowlist entries and rejects invalid configuration", () => {
    expect(parseComplimentaryHostUserIds(`1537971830701293799  ${userId},1537971830701293788`))
      .toEqual(new Set(["1537971830701293799", userId, "1537971830701293788"]));
    expect(() => parseComplimentaryHostUserIds(`${userId},not-a-discord-id`))
      .toThrow("complimentary host allowlist is invalid");
  });

  it("rejects deleted, expired, future, and unrelated entitlements", async () => {
    const fetcher = vi.fn(async () => Response.json([
      { sku_id: config.hostSkuId, user_id: userId, deleted: true },
      { sku_id: config.hostSkuId, user_id: userId, ends_at: "2020-01-01T00:00:00Z" },
      { sku_id: config.hostSkuId, user_id: userId, starts_at: "2030-01-01T00:00:00Z" },
      { sku_id: "another-sku", user_id: userId },
    ]));
    const now = Date.parse("2026-01-01T00:00:00Z");
    await expect(userCanHostDiscordRoom(userId, config, fetcher as typeof fetch, now)).resolves.toBe(false);
  });
});
