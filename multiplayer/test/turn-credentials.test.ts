import { describe, expect, it, vi } from "vitest";
import {
  fallbackVoiceIceConfiguration,
  generateVoiceIceConfiguration,
} from "../src/turn-credentials";

describe("Cloudflare TURN credentials", () => {
  it("uses STUN-only connectivity when TURN is not configured", async () => {
    expect(await generateVoiceIceConfiguration({})).toEqual(fallbackVoiceIceConfiguration());
  });

  it("requests short-lived credentials without exposing the API token", async () => {
    const fetcher = vi.fn(async () => Response.json({
      iceServers: [
        { urls: ["stun:stun.cloudflare.com:3478", "stun:stun.cloudflare.com:53"] },
        {
          urls: [
            "turn:turn.cloudflare.com:3478?transport=udp",
            "turn:turn.cloudflare.com:53?transport=udp",
            "turns:turn.cloudflare.com:443?transport=tcp",
          ],
          username: "temporary-user",
          credential: "temporary-password",
        },
      ],
    }, { status: 201 })) as unknown as typeof fetch;

    const result = await generateVoiceIceConfiguration({
      TURN_KEY_ID: "turn-key-id",
      TURN_KEY_API_TOKEN: "secret-api-token",
    }, fetcher);

    expect(fetcher).toHaveBeenCalledOnce();
    const [url, options] = (fetcher as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toContain("/turn-key-id/credentials/generate-ice-servers");
    expect(options.headers.Authorization).toBe("Bearer secret-api-token");
    expect(JSON.parse(options.body)).toEqual({ ttl: 43_200 });
    expect(result.relayAvailable).toBe(true);
    expect(result.ttlSeconds).toBe(43_200);
    expect(JSON.stringify(result)).not.toContain(":53");
    expect(JSON.stringify(result)).not.toContain("secret-api-token");
  });

  it("fails closed when Cloudflare returns no relay", async () => {
    const fetcher = vi.fn(async () => Response.json({
      iceServers: [{ urls: ["stun:stun.cloudflare.com:3478"] }],
    }, { status: 201 })) as unknown as typeof fetch;

    await expect(generateVoiceIceConfiguration({
      TURN_KEY_ID: "turn-key-id",
      TURN_KEY_API_TOKEN: "secret-api-token",
    }, fetcher)).rejects.toThrow(/relay server/);
  });
});
