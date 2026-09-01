export type DiscordRoomAccessDecision = "join" | "activate" | "wait_for_host";

export function discordRoomAccessDecision(
  roomLicenseActive: boolean,
  userCanHost: boolean,
): DiscordRoomAccessDecision {
  if (roomLicenseActive) return "join";
  return userCanHost ? "activate" : "wait_for_host";
}
