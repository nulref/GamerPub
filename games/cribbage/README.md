# Cribbage

Cribbage is the fourth Gamer Pub title. It supports local single-player tables with bots and server-authoritative browser/Discord multiplayer.

## Game types

- **Standard:** 2–4 individual players
- **Partnership:** 2 players, or 4 players with opposite-seat partners
- **Variant:** the requested 5-player individual deal or 6-player three-team deal

All games use four-card hands for pegging and showing, a four-card crib, a normal starter, full pegging points, full hand/crib scoring, heels, and an immediate win at 121.

For five players, the dealer receives four cards and every other player receives five and discards one. For six players, seats are A1–B1–C1–A2–B2–C2; the dealer and partner receive four while the other four players receive five and discard one.

The layout is landscape-first. Narrow landscape screens use smaller cards and a compact score board. Portrait screens show a rotate prompt.

## Checks

```powershell
godot --headless --path . --script games/cribbage/tests/test_rules.gd
godot --headless --path . --script games/cribbage/tests/test_match.gd
godot --headless --path . --script tests/test_cribbage_launcher.gd
```

Cloudflare rules/room checks are part of `npm test` in `multiplayer/`. The browser room client is covered by `tests/cribbage_room_client.test.mjs`.
