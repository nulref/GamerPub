const DISCORD_API_BASE = "https://discord.com/api/v10";

export interface DiscordPremiumConfig {
  applicationId: string;
  botToken: string;
  hostSkuId: string;
  complimentaryHostUserIds?: string;
}

export interface DiscordUser {
  id: string;
  username?: string;
  global_name?: string | null;
}

interface DiscordEntitlement {
  sku_id?: unknown;
  user_id?: unknown;
  deleted?: unknown;
  starts_at?: unknown;
  ends_at?: unknown;
}

export class DiscordPremiumError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function configured(value: string): boolean {
  return value.trim().length > 0;
}

export function parseComplimentaryHostUserIds(value = ""): ReadonlySet<string> {
  if (value.length > 64 * 1024) {
    throw new DiscordPremiumError(503, "The complimentary host allowlist is too large.");
  }
  const userIds = value.trim() ? value.trim().split(/[\s,]+/) : [];
  if (userIds.some((userId) => !/^\d{17,20}$/.test(userId))) {
    throw new DiscordPremiumError(503, "The complimentary host allowlist is invalid.");
  }
  return new Set(userIds);
}

export async function fetchDiscordUser(
  accessToken: string,
  fetcher: typeof fetch = fetch,
): Promise<DiscordUser> {
  if (!configured(accessToken)) throw new DiscordPremiumError(401, "Discord authentication is required.");
  const response = await fetcher(`${DISCORD_API_BASE}/users/@me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new DiscordPremiumError(502, "Discord could not verify the current user.");
  const user = (await response.json()) as Partial<DiscordUser>;
  if (!user.id || !/^\d{17,20}$/.test(user.id)) {
    throw new DiscordPremiumError(502, "Discord returned an invalid current user.");
  }
  return user as DiscordUser;
}

export async function userCanHostDiscordRoom(
  userId: string,
  config: DiscordPremiumConfig,
  fetcher: typeof fetch = fetch,
  now = Date.now(),
): Promise<boolean> {
  if (!/^\d{17,20}$/.test(userId)) throw new DiscordPremiumError(400, "A valid Discord user is required.");
  if (parseComplimentaryHostUserIds(config.complimentaryHostUserIds).has(userId)) return true;
  if (!configured(config.applicationId) || !configured(config.botToken) || !configured(config.hostSkuId)) {
    throw new DiscordPremiumError(503, "Discord host licensing is not configured.");
  }

  const query = new URLSearchParams({
    user_id: userId,
    sku_ids: config.hostSkuId,
    exclude_ended: "true",
    exclude_deleted: "true",
  });
  const response = await fetcher(
    `${DISCORD_API_BASE}/applications/${config.applicationId}/entitlements?${query}`,
    { headers: { Authorization: `Bot ${config.botToken}` } },
  );
  if (!response.ok) throw new DiscordPremiumError(502, "Discord could not verify host access.");

  const value: unknown = await response.json();
  if (!Array.isArray(value)) throw new DiscordPremiumError(502, "Discord returned invalid entitlements.");
  return value.some((entry: DiscordEntitlement) => {
    if (entry.sku_id !== config.hostSkuId || entry.user_id !== userId || entry.deleted === true) return false;
    const startsAt = typeof entry.starts_at === "string" ? Date.parse(entry.starts_at) : null;
    const endsAt = typeof entry.ends_at === "string" ? Date.parse(entry.ends_at) : null;
    if (startsAt !== null && (!Number.isFinite(startsAt) || startsAt > now)) return false;
    if (endsAt !== null && (!Number.isFinite(endsAt) || endsAt <= now)) return false;
    return true;
  });
}
