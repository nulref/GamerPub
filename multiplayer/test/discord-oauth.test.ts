import { describe, expect, it, vi } from "vitest";
import { DiscordOAuthError, exchangeDiscordCode, validAuthorizationCode } from "../src/discord-oauth";

describe("Discord OAuth exchange", () => {
  it("validates authorization codes before making a request", async () => {
    expect(validAuthorizationCode("short")).toBe(false);
    await expect(
      exchangeDiscordCode("short", { clientId: "client", clientSecret: "secret" }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("keeps the client secret in the server-side token request", async () => {
    const fetcher = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      const values = new URLSearchParams(String(init?.body));
      expect(values.get("client_id")).toBe("client-id");
      expect(values.get("client_secret")).toBe("server-secret");
      expect(values.get("code")).toBe("authorization-code");
      return Response.json({ access_token: "access-token", token_type: "Bearer" });
    });

    const token = await exchangeDiscordCode(
      "authorization-code",
      { clientId: "client-id", clientSecret: "server-secret" },
      fetcher as typeof fetch,
    );
    expect(token.access_token).toBe("access-token");
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it("reports missing Worker configuration without exposing a secret", async () => {
    await expect(
      exchangeDiscordCode("authorization-code", { clientId: "client", clientSecret: "" }),
    ).rejects.toBeInstanceOf(DiscordOAuthError);
  });
});
