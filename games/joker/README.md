# Joker

Joker is Gamer Pub's first playable game. Four players pass cards clockwise while trying to complete a matching hand; once someone qualifies, everyone races to slap the table. Penalty letters spell `JOKER`, and the first player to complete the word loses.

## Module boundaries

- `scenes/main_menu.tscn` is Joker's entry scene.
- `scenes/game.tscn` contains the play surface and overlays.
- `scripts/` contains rules, state, presentation, settings, and the Discord bridge.
- `resources/ranks/` contains Joker's rank definitions.
- `assets/` contains artwork and audio unique to Joker.
- `res://shared/assets/Cards/` supplies the reusable card artwork.

Joker's global GDScript classes, `JokerDiscordBridge` autoload, `joker_slap` input action, and `user://joker_settings.cfg` save file are namespaced so they can coexist with future games.

## Navigation

The Gamer Pub launcher opens `scenes/main_menu.tscn`. Joker's **Back to Gamer Pub** button returns to `res://launcher/main_menu.tscn`; the in-game **Main Menu** button returns to Joker's own menu.

## Multiplayer

The `JokerDiscordBridge` keeps the browser/Discord messaging boundary used by Joker multiplayer. Desktop play remains local; the multiplayer workflow requires the separately deployed Discord Activity shell and server-authoritative room service.

## Checks

Run these commands from the Gamer Pub repository root:

```powershell
godot --headless --path . --script games/joker/tests/test_rules.gd
godot --headless --path . --script games/joker/tests/test_deal.gd
godot --headless --path . --script games/joker/tests/test_presentation.gd
godot --headless --path . --script games/joker/tests/test_multiplayer_lobby.gd
```
