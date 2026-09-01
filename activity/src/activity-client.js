export const DISCORD_CLIENT_ID_PLACEHOLDER = "YOUR_DISCORD_APPLICATION_ID";

export function isDiscordActivity(search = globalThis.location?.search ?? "") {
  return new URLSearchParams(search).has("frame_id");
}

export function discordDisplayName(user) {
  return user?.global_name?.trim() || user?.username?.trim() || "Player";
}

export function activitySocketUrl(
  path,
  instanceId,
  locationLike = globalThis.location,
) {
  if (!locationLike?.href) throw new Error("An Activity location is required.");
  if (!instanceId) throw new Error("A Discord Activity instance is required.");
  const url = new URL(path, locationLike.href);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("instance_id", instanceId);
  return url.toString();
}

export function validatedGameEntry(manifest) {
  if (!manifest || typeof manifest.entry !== "string" ||
      !/^\/game\/[a-f0-9]{16}\/index\.html$/.test(manifest.entry)) {
    throw new Error("The Gamer Pub build manifest is invalid.");
  }
  return manifest.entry;
}
