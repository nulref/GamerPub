export const PUBLIC_ROOM_NAME = "public-web-lobby";
export const PUBLIC_ROOM_PATH = "/public";

export function configuredPublicOrigins(value: string): string[] {
  return value
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

export function publicOriginAllowed(origin: string | null, configuredOrigins: string): boolean {
  if (!origin) return false;
  try {
    const parsedOrigin = new URL(origin);
    if (configuredPublicOrigins(configuredOrigins).some((configuredOrigin) => {
      try {
        return parsedOrigin.origin === new URL(configuredOrigin).origin;
      } catch {
        return false;
      }
    })) return true;
    return (
      parsedOrigin.protocol === "http:" &&
      (parsedOrigin.hostname === "localhost" || parsedOrigin.hostname === "127.0.0.1")
    );
  } catch {
    return false;
  }
}
