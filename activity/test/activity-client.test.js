import assert from "node:assert/strict";
import test from "node:test";
import {
  activitySocketUrl,
  discordDisplayName,
  isDiscordActivity,
  validatedGameEntry,
} from "../src/activity-client.js";

test("detects Discord's embedded frame query", () => {
  assert.equal(isDiscordActivity("?frame_id=abc&instance_id=room"), true);
  assert.equal(isDiscordActivity("?tenk_player=one"), false);
});

test("builds a proxied Activity WebSocket URL", () => {
  const url = new URL(activitySocketUrl(
    "/api/tenk",
    "activity-instance-123",
    { href: "https://123.discordsays.com/" },
  ));
  assert.equal(url.protocol, "wss:");
  assert.equal(url.pathname, "/api/tenk");
  assert.equal(url.searchParams.get("instance_id"), "activity-instance-123");
});

test("uses Discord display names and validates versioned game entries", () => {
  assert.equal(discordDisplayName({ username: "steve", global_name: "Steve" }), "Steve");
  assert.equal(
    validatedGameEntry({ entry: "/game/0123456789abcdef/index.html" }),
    "/game/0123456789abcdef/index.html",
  );
  assert.throws(() => validatedGameEntry({ entry: "https://example.com/game.html" }));
});
