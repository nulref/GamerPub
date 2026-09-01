const SESSION_HEADER = { alg: "HS256", typ: "JOKER" } as const;
const DEFAULT_SESSION_TTL_MS = 6 * 60 * 60 * 1000;

export interface ActivitySessionClaims {
  version: 1;
  userId: string;
  instanceId: string;
  canHost: boolean;
  issuedAt: number;
  expiresAt: number;
}

export class ActivitySessionError extends Error {}

function encodeBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function decodeBytes(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new ActivitySessionError("Invalid session encoding.");
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  try {
    return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
  } catch {
    throw new ActivitySessionError("Invalid session encoding.");
  }
}

function encodeJson(value: unknown): string {
  return encodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function decodeJson<T>(value: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(decodeBytes(value))) as T;
  } catch (error) {
    if (error instanceof ActivitySessionError) throw error;
    throw new ActivitySessionError("Invalid session payload.");
  }
}

async function signingKey(secret: string): Promise<CryptoKey> {
  if (secret.length < 32) throw new ActivitySessionError("Activity session signing is not configured.");
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function validClaims(value: unknown): value is ActivitySessionClaims {
  if (!value || typeof value !== "object") return false;
  const claims = value as Partial<ActivitySessionClaims>;
  return claims.version === 1 &&
    typeof claims.userId === "string" && /^\d{17,20}$/.test(claims.userId) &&
    typeof claims.instanceId === "string" && claims.instanceId.length >= 8 && claims.instanceId.length <= 256 &&
    typeof claims.canHost === "boolean" &&
    typeof claims.issuedAt === "number" && Number.isSafeInteger(claims.issuedAt) &&
    typeof claims.expiresAt === "number" && Number.isSafeInteger(claims.expiresAt);
}

export async function signActivitySession(
  identity: Pick<ActivitySessionClaims, "userId" | "instanceId" | "canHost">,
  secret: string,
  now = Date.now(),
  ttlMs = DEFAULT_SESSION_TTL_MS,
): Promise<string> {
  const claims: ActivitySessionClaims = {
    version: 1,
    ...identity,
    issuedAt: now,
    expiresAt: now + ttlMs,
  };
  if (!validClaims(claims) || !Number.isSafeInteger(ttlMs) || ttlMs <= 0) {
    throw new ActivitySessionError("Invalid activity session claims.");
  }

  const unsigned = `${encodeJson(SESSION_HEADER)}.${encodeJson(claims)}`;
  const signature = await crypto.subtle.sign(
    "HMAC",
    await signingKey(secret),
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${encodeBytes(new Uint8Array(signature))}`;
}

export async function verifyActivitySession(
  token: unknown,
  secret: string,
  expectedInstanceId?: string,
  now = Date.now(),
): Promise<ActivitySessionClaims> {
  if (typeof token !== "string" || token.length > 4096) {
    throw new ActivitySessionError("A valid activity session is required.");
  }
  const parts = token.split(".");
  if (parts.length !== 3) throw new ActivitySessionError("A valid activity session is required.");
  const [headerPart, claimsPart, signaturePart] = parts;
  const header = decodeJson<Partial<typeof SESSION_HEADER>>(headerPart);
  if (header.alg !== SESSION_HEADER.alg || header.typ !== SESSION_HEADER.typ) {
    throw new ActivitySessionError("Unsupported activity session.");
  }

  const verified = await crypto.subtle.verify(
    "HMAC",
    await signingKey(secret),
    decodeBytes(signaturePart),
    new TextEncoder().encode(`${headerPart}.${claimsPart}`),
  );
  if (!verified) throw new ActivitySessionError("Activity session signature is invalid.");

  const claims = decodeJson<unknown>(claimsPart);
  if (!validClaims(claims)) throw new ActivitySessionError("Invalid activity session claims.");
  if (claims.expiresAt <= now || claims.issuedAt > now + 60_000) {
    throw new ActivitySessionError("The activity session has expired.");
  }
  if (expectedInstanceId && claims.instanceId !== expectedInstanceId) {
    throw new ActivitySessionError("The activity session belongs to another room.");
  }
  return claims;
}
