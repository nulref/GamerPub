# Gamer Pub

Gamer Pub is a Godot-powered game collection presented through a shared tavern-themed launcher. The project is organized as a single Godot application so the launcher, individual games, and shared systems can move between scenes without managing separate executables.

## Current status

The first launcher menu is in place. It includes:

- A responsive main menu built over the tavern background
- A data-driven game-card carousel with a maximum of six visible cards
- Previous and next controls that move through the games one card at a time
- Mouse hover and keyboard focus effects with 10% card enlargement
- Selectable cards and a `game_chosen` signal for future scene routing
- Responsive card sizing for smaller window dimensions

The ten current game entries are placeholders and reuse the Gamer Pub logo until individual games and their artwork are added.

## Technology

- Godot 4.7.1
- GDScript
- GL Compatibility renderer
- Reference resolution: 1600 × 900

## Project structure

```text
Gamer Pub/
├── project.godot                 # Root Godot project configuration
├── launcher/
│   ├── main_menu.tscn            # Launcher main scene
│   ├── scripts/
│   │   ├── main_menu.gd          # Carousel data, navigation, and selection
│   │   └── game_card.gd          # Reusable interactive game card
│   └── assets/art/               # Launcher background and logo artwork
├── games/                         # Individual game modules (planned)
├── shared/                        # Shared scenes, scripts, themes, and assets (planned)
└── autoload/                      # Global services and scene routing (planned)
```

Each game should eventually live in its own folder under `games/`, alongside the launcher rather than inside it.

## Running the project

1. Install Godot 4.7.1 or a compatible Godot 4 release.
2. Import `project.godot` into the Godot Project Manager.
3. Open the project and press **F5** to run it.

The launcher is configured as the project's main scene.

## Launcher controls

- Hover over or focus a card to enlarge and highlight it.
- Click a card to select it.
- Use the on-screen arrows or the keyboard's **Left** and **Right** arrow keys to navigate.

## Adding a game

1. Create `games/<game_name>/` with its own `scenes/`, `scripts/`, and `assets/` folders.
2. Add the game's launcher logo to its assets folder.
3. Replace or extend the placeholder entries in `GAMES` inside `launcher/scripts/main_menu.gd`.
4. Route the launcher's `game_chosen` signal to the game's entry scene.

Shared settings, audio, save data, and navigation services should be placed in `shared/` or `autoload/` as they are introduced.
