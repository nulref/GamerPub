# Gamer Pub

Gamer Pub is a Godot-powered game collection presented through a shared tavern-themed launcher. The launcher and every game run as scenes in one Godot project, so switching games does not require separate executables.

## Current status

The launcher currently includes:

- A responsive, data-driven carousel with at most six visible cards
- Mouse, keyboard-focus, and previous/next navigation
- Joker and 10,000 as playable games in the collection
- Eight placeholder entries ready to be replaced by future games
- Direct scene routing into each game and return routes back to Gamer Pub

Joker supports local play against bots and retains its Discord multiplayer bridge. Multiplayer is available only when the exported game is hosted by Joker's Discord Activity shell.

Tenk supports 2–8 local hot-seat players, interactive dice selection, the 1,000-point opening requirement, hot dice, the Gamer Pub "go for it" house rule, and optional eight-person browser voice chat on the hosted Web build.

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
│   └── tenk/                       # 10,000 dice game
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
4. Select **Joker** or **10,000** from the carousel.

From Joker's menu, **Back to Gamer Pub** returns to the launcher.

## Netlify play-test build

The repository includes a single-threaded Godot Web preset and a prebuilt `dist/` bundle. Netlify serves that directory directly; it does not need Godot installed during deployment. The export script adds Tenk's browser voice toolbar and copies its WebRTC client into the bundle. Voice is optional, appears only while Tenk is open, and supports up to eight people through Joker's existing signaling worker.

To refresh the browser bundle after changing the game, install the Godot 4.7.1 export templates and run:

```powershell
.\scripts\export_web.ps1
```

If Godot is not on `PATH`, pass its executable explicitly:

```powershell
.\scripts\export_web.ps1 -GodotPath "C:\path\to\Godot_v4.7.1-stable_win64.exe"
```

Commit the regenerated files in `dist/` before pushing. Joker multiplayer is disabled on the standalone Netlify build and becomes available only inside its Discord Activity wrapper; Joker single-player and 10,000 local hot-seat play remain available.

The production voice worker must allow `https://gamerpub.netlify.app` as an exact WebSocket origin and expose `/voice/tenk`. Netlify's response headers allow microphone capture from the Gamer Pub origin only.

## 10,000 controls

- Select scoring dice or a qualifying partial combination, then choose **Reroll** to lock them and reroll every unselected die in place.
- Matching sets score within one roll; a locked pair may be completed by one matching die on the immediately following roll.
- Choose **Keep It** to bank an eligible turn and pass the dice.
- Press <kbd>Space</kbd> or <kbd>Enter</kbd> to roll or reroll.

## Joker controls

- Click a card or press <kbd>1</kbd>-<kbd>5</kbd> to pass it.
- Press <kbd>Space</kbd> or select **Slap the Table** to slap.
- Use the settings menu to adjust sound and bot pacing.

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

## Adding a game

1. Create `games/<game_name>/` with its own scenes, scripts, resources, assets, and tests.
2. Prefix globally registered `class_name` declarations, autoloads, input actions, and save files with the game's name.
3. Put reusable tabletop artwork or systems under `shared/`.
4. Add the game's name, logo, ID, and entry scene to `GAMES` in `launcher/scripts/main_menu.gd`.
5. Add an integration check that launches the game and returns to Gamer Pub.
