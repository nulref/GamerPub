export const TENK_ROOM_NAME = "gamer-pub-tenk-room";
export const TENK_ROOM_PATH = "/tenk";
export const TENK_VOICE_PATH = "/voice/tenk";
export const MAX_TENK_VOICE_PARTICIPANTS = 8;

export function validPublicVoiceUserId(value: string | null): value is string {
  return Boolean(value && /^[A-Za-z0-9_-]{1,64}$/.test(value));
}

export function publicVoiceName(value: string | null): string | null {
  if (value === null) return null;
  const cleaned = value.trim().replace(/\s+/g, " ").slice(0, 32);
  return cleaned || null;
}
