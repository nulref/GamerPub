# Gamer Pub

Gamer Pub is a Godot-powered game collection presented through a shared tavern-themed launcher. The launcher and every game run as scenes in one Godot project, so switching games does not require separate executables.

## Current status

The launcher currently includes:

- A responsive, data-driven carousel with at most six visible cards
- Mouse, keyboard-focus, and previous/next navigation
- Joker, TenK, Sesquip, and Cribbage as playable games in the collection
- Six placeholder entries ready to be replaced by future games
- Direct scene routing into each game and return routes back to Gamer Pub

Joker supports local play against bots and retains its Discord multiplayer bridge. Multiplayer is available when the exported game is hosted by the Gamer Pub or standalone Joker Discord Activity shell.

TenK supports 2–8 local hot-seat players, interactive dice selection, the 1,000-point opening requirement, hot dice, and the Gamer Pub "go for it" house rule. The hosted Web build adds a shared 2–8 player room with host-controlled start, server-authoritative turns and dice, reconnect state, and optional eight-person voice chat.

Sesquip is an early local hot-seat word game for 2–4 players. Players have five seconds to extend a shared sequence using one of the legal letters illuminated on screen. The player who reaches a terminal word scores one point per letter. Its bundled local lexicon is intentionally a prototype rather than a licensed tournament word list.

Cribbage supports Standard 2–4 player games, Partnership tables for 2 or 4 players, and the five- and six-player house-rule Variants. Single player fills every other seat with bots, including partners. Browser and Discord multiplayer use the shared ready-up flow and server-authoritative private hands. Its landscape-first table scales down for mobile browsers and asks portrait users to rotate.

## Technology

- Godot 4.7.1
- GDScript
- GL Compatibility renderer
- Reference resolution: 1600 × 900

## Project structure

```text
Gamer Pub/
├── project.godot
├── export_presets.cfg              # Single-threaded browser export
├── netlify.toml                    # Serves the committed Web build
├── dist/                           # Versioned Netlify play-test bundle
├── activity/                       # Discord SDK and browser shell
├── multiplayer/                    # Gamer Pub Cloudflare Worker backend
├── launcher/
│   ├── main_menu.tscn
│   ├── scripts/
│   └── assets/art/
├── games/
│   ├── joker/
│   │   ├── assets/                 # Joker-specific art and audio
│   │   ├── resources/              # Card definitions used by Joker
│   │   ├── scenes/
│   │   ├── scripts/
│   │   └── tests/
│   ├── tenk/                       # TenK dice game
│   │   ├── scenes/
│   │   ├── scripts/
│   │   └── tests/
│   ├── sesquip/                    # Sesquip word game
│   │   ├── data/                   # Prototype local lexicon
│   │   ├── scenes/
│   │   ├── scripts/
│   │   └── tests/
│   └── cribbage/                   # Cribbage, bots, and responsive table
│       ├── scenes/
│       ├── scripts/
│       └── tests/
├── shared/
│   └── assets/
│       ├── Cards/                  # Shared playing-card artwork
│       ├── Chips/                  # Shared chip artwork
│       └── Dice/                   # Shared die artwork
└── tests/                           # Collection-level integration checks
```

Game-specific files stay under `games/<game_name>/`. Assets and systems intentionally reused by multiple games belong under `shared/`. Global services must use game-specific names unless they are genuinely shared across the whole collection.

## Running the project

1. Install Godot 4.7.1 or a compatible Godot 4 release.
2. Import the root `project.godot` into the Godot Project Manager.
3. Press **F5** to open the Gamer Pub launcher.
4. Select **Joker**, **TenK**, **Sesquip**, or **Cribbage** from the carousel.

From Joker's menu, **Back to Gamer Pub** returns to the launcher.

## Netlify play-test build

The repository includes a single-threaded Godot Web preset and a prebuilt `dist/` bundle. Netlify serves that directory directly; it does not need Godot installed during deployment. The export script adds TenK's browser room and voice bridge, then wraps the content-addressed Godot export in the Gamer Pub Discord Activity shell. On the hosted site, every connected browser joins the same TenK lobby; the first player is host, all players ready up, and the host starts the game. Voice remains optional and supports up to eight people through Gamer Pub's own Worker.

To refresh the browser bundle after changing the game, install the Godot 4.7.1 export templates and run:

```powershell
.\scripts\export_web.ps1
```

If Godot is not on `PATH`, pass its executable explicitly:

```powershell
.\scripts\export_web.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64.exe"
```

Commit the regenerated files in `dist/` before pushing. Joker multiplayer is disabled on the standalone Netlify build and becomes available when Gamer Pub is launched as a Discord Activity. Tenk uses the shared browser lobby on Netlify, a room isolated to each Discord Activity instance inside Discord, and local hot-seat play in native/headless builds.

Deploy Gamer Pub's `multiplayer/` Cloudflare Worker before the Netlify bundle so its room Durable Objects and `/tenk` endpoint are available first. The production Worker allows the Gamer Pub Netlify and Discord proxy origins. Netlify's response headers allow microphone capture from the Gamer Pub origin only.

See [`docs/DISCORD_ACTIVITY.md`](docs/DISCORD_ACTIVITY.md) for the Activity
build, local tunnel, isolated Worker deployment, and Discord Developer Portal
setup.

## TenK controls

- Select scoring dice or a qualifying partial combination, then choose **Reroll** to lock them and reroll every unselected die in place.
- Matching sets score within one roll; a locked pair may be completed by one matching die on the immediately following roll.
- Choose **Keep It** to bank an eligible turn; Tenk automatically advances to the next player after a score or bust.
- Press <kbd>Space</kbd> or <kbd>Enter</kbd> to roll or reroll.

## Joker controls

- Click a card or press <kbd>1</kbd>-<kbd>5</kbd> to pass it.
- Press <kbd>Space</kbd> or select **Slap the Table** to slap.
- Use the settings menu to adjust sound and bot pacing.

## Sesquip controls

- Select an illuminated key or press its matching physical letter key before the five-second timer expires.
- Keep extending through complete words while legal continuations remain; the terminal word scores.
- A timeout passes the turn. Consecutive timeouts by every player abandon the round without points.

## Cribbage controls

- Choose Single Player or Multiplayer, then select Standard, Partnership, or Variant and a valid table size.
- During the discard, select the highlighted number of cards and send them to the crib.
- During pegging, select any enabled card; cards that would take the count over 31 are disabled.
- In multiplayer, everyone readies up and the host starts and advances the shared table.

## Checks

Run the collection integration checks from the repository root:

```powershell
godot --headless --path . --script tests/test_joker_launcher.gd
godot --headless --path . --script tests/test_tenk_launcher.gd
```

Run Joker's checks from the same location:

```powershell
godot --headless --path . --script games/joker/tests/test_rules.gd
godot --headless --path . --script games/joker/tests/test_deal.gd
godot --headless --path . --script games/joker/tests/test_presentation.gd
godot --headless --path . --script games/joker/tests/test_multiplayer_lobby.gd
```

Run 10,000's checks from the same location:

```powershell
godot --headless --path . --script games/tenk/tests/test_rules.gd
godot --headless --path . --script games/tenk/tests/test_game_flow.gd
```

Run Sesquip's checks from the same location:

```powershell
godot --headless --path . --script games/sesquip/tests/test_lexicon.gd
godot --headless --path . --script games/sesquip/tests/test_game_flow.gd
godot --headless --path . --script tests/test_sesquip_launcher.gd
```

## Adding a game

1. Create `games/<game_name>/` with its own scenes, scripts, resources, assets, and tests.
2. Prefix globally registered `class_name` declarations, autoloads, input actions, and save files with the game's name.
3. Put reusable tabletop artwork or systems under `shared/`.
4. Add the game's name, logo, ID, and entry scene to `GAMES` in `launcher/scripts/main_menu.gd`.
5. Add an integration check that launches the game and returns to Gamer Pub.
