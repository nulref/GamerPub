export interface DiscordOAuthConfig {
  clientId: string;
  clientSecret: string;
}

export interface DiscordTokenResponse {
  access_token: string;
  token_type?: string;
  expires_in?: number;
  refresh_token?: string;
  scope?: string;
}

export class DiscordOAuthError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function validAuthorizationCode(value: unknown): value is string {
  return typeof value === "string" && value.length >= 8 && value.length <= 2048;
}

export async function exchangeDiscordCode(
  code: string,
  config: DiscordOAuthConfig,
  fetcher: typeof fetch = fetch,
): Promise<DiscordTokenResponse> {
  if (!validAuthorizationCode(code)) {
    throw new DiscordOAuthError(400, "A valid Discord authorization code is required.");
  }
  if (!config.clientId || !config.clientSecret) {
    throw new DiscordOAuthError(503, "Discord OAuth is not configured on the multiplayer service.");
  }

  const response = await fetcher("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      grant_type: "authorization_code",
      code,
    }),
  });

  if (!response.ok) {
    throw new DiscordOAuthError(502, "Discord rejected the authorization code exchange.");
  }
  const token = (await response.json()) as Partial<DiscordTokenResponse>;
  if (!token.access_token || typeof token.access_token !== "string") {
    throw new DiscordOAuthError(502, "Discord returned an invalid token response.");
  }
  return token as DiscordTokenResponse;
}
