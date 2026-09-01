export interface VoiceIceServer {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export interface VoiceIceConfiguration {
  iceServers: VoiceIceServer[];
  relayAvailable: boolean;
  ttlSeconds: number | null;
}

export interface TurnCredentialsEnv {
  TURN_KEY_ID?: string;
  TURN_KEY_API_TOKEN?: string;
}

const TURN_CREDENTIAL_TTL_SECONDS = 12 * 60 * 60;
const CLOUDFLARE_STUN_URL = "stun:stun.cloudflare.com:3478";

export function fallbackVoiceIceConfiguration(): VoiceIceConfiguration {
  return {
    iceServers: [{ urls: [CLOUDFLARE_STUN_URL] }],
    relayAvailable: false,
    ttlSeconds: null,
  };
}

function supportedIceUrl(value: unknown): value is string {
  if (typeof value !== "string") return false;
  if (!/^(stun|turn|turns):/i.test(value)) return false;
  // Cloudflare documents port 53 as blocked by popular browsers. Keeping it
  // out also avoids unnecessary ICE timeouts on mobile clients.
  return !/:53(?:\?|$)/.test(value);
}

function cleanIceServer(value: unknown): VoiceIceServer | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Record<string, unknown>;
  const urls = (Array.isArray(candidate.urls) ? candidate.urls : [candidate.urls])
    .filter(supportedIceUrl);
  if (urls.length === 0) return null;

  const hasTurn = urls.some((url) => /^turns?:/i.test(url));
  if (hasTurn && (typeof candidate.username !== "string" || typeof candidate.credential !== "string")) {
    return null;
  }

  return {
    urls,
    ...(typeof candidate.username === "string" ? { username: candidate.username } : {}),
    ...(typeof candidate.credential === "string" ? { credential: candidate.credential } : {}),
  };
}

export async function generateVoiceIceConfiguration(
  env: TurnCredentialsEnv,
  fetcher: typeof fetch = fetch,
): Promise<VoiceIceConfiguration> {
  const keyId = env.TURN_KEY_ID?.trim();
  const apiToken = env.TURN_KEY_API_TOKEN?.trim();
  if (!keyId || !apiToken) return fallbackVoiceIceConfiguration();

  const response = await fetcher(
    `https://rtc.live.cloudflare.com/v1/turn/keys/${encodeURIComponent(keyId)}/credentials/generate-ice-servers`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ ttl: TURN_CREDENTIAL_TTL_SECONDS }),
    },
  );
  if (!response.ok) {
    throw new Error(`Cloudflare TURN credential request failed (${response.status}).`);
  }

  const body = await response.json() as { iceServers?: unknown };
  if (!Array.isArray(body.iceServers)) {
    throw new Error("Cloudflare TURN response did not contain ICE servers.");
  }
  const iceServers = body.iceServers.map(cleanIceServer).filter((value): value is VoiceIceServer => Boolean(value));
  if (!iceServers.some((server) => {
    const urls = Array.isArray(server.urls) ? server.urls : [server.urls];
    return urls.some((url) => /^turns?:/i.test(url));
  })) {
    throw new Error("Cloudflare TURN response did not contain a relay server.");
  }

  return {
    iceServers,
    relayAvailable: true,
    ttlSeconds: TURN_CREDENTIAL_TTL_SECONDS,
  };
}
