# 10,000

This folder contains Gamer Pub's version of the six-die game 10,000. Native
builds use local hot-seat play; the Netlify Web build uses a shared 2–8 player
lobby whose host starts the game and whose dice, scores, and turns are enforced
by the Joker Cloudflare Worker.

## Implemented rules

- 2–8 players; a player must finish on exactly 10,000 to win. Exceeding 10,000 busts the turn and leaves the player's previously banked score unchanged.
- A player must bank at least 1,000 points in one turn to get on the board.
- All six dice remain visible during a hand and begin unselected. Unselected dice have no border; selected and locked dice use a white outline. Selected dice lock in place while every unselected die rerolls in its original position, and multiplayer selection changes are visible to everyone at the table.
- Single 1s score 100 and single 5s score 50.
- Three 1s score 1,000; other triples score face value × 100.
- Each matching die after the third doubles the set's score.
- Matching sets must be rolled together. The exception is a locked pair: one matching die on the immediately following roll completes its triple. If that next roll misses, later matching dice retain their single-die value, if any.
- At a banked score of 9,000 or less, locking two 1s is a committed attempt at three 1s for 1,000 points; the immediately following roll must contain the third 1 or the turn busts. Above 9,000, two 1s remain ordinary 100-point singles instead. An opening roll worth exactly 1,000 also busts immediately above 9,000 because it would overshoot the winning score.
- A straight scores 1,500.
- Three pairs, four-of-a-kind plus a pair, and two triplets score 1,000.
- When all six dice score, all six become available again ("and rolling" or hot dice).
- Reroll is enabled when the selection contains scoring dice, a pair toward three of a kind, five faces toward a straight, three to five matching dice, two pairs, or one triple toward two triplets. A non-scoring partial-combination attempt may be started once per turn; its next roll must score or advance that same attempt.
- Scoring selections may repeat until all six dice score ("and rolling") or a reroll cannot score or advance a qualifying combination (bust).
- A matching die rolled after an already-scored triple does not extend that set and is not a qualifying continuation by itself. This applies to every die face; only a locked pair may be completed by one matching die on the immediately following roll.
- Above 9,000 points, a carried pair of 1s and a later matching 1 remain three 100-point singles; only three 1s rolled together retain the 1,000-point combination.
- A newly rolled combination worth at least 1,000 points immediately busts when adding it to the banked and current-turn score would exceed exactly 10,000.
- The once-per-turn rescue rule applies only when the opening six-die roll has no score.
- Banking, failing to meet the opening requirement, and busting automatically advance control to the next player. No separate pass action is required.

## Diagnostic game log

The in-game **Game Log** records every roll and the action that follows it. Entries include the player, a game-wide roll number, raw dice, raw roll points, available hand points, selected dice, action points, running turn points, and the final bank/bust outcome. Zero-point rolls, qualifying partial combinations, failed opening banks, and busts are recorded explicitly.

Native games also append the structured entries to `user://tenk_debug.log` (the Godot user-data directory) and print them to the process log. Hosted games retain the entries in the server-authoritative room activity and emit the same text to the Cloudflare Worker log.

Every local or server-synchronized roll plays the licensed dice-roll effect stored at `assets/audio/dice-roll.wav`.

## Checks

From the project root:

```powershell
godot --headless --path . --script games/tenk/tests/test_rules.gd
godot --headless --path . --script games/tenk/tests/test_game_flow.gd
godot --headless --path . --script tests/test_tenk_launcher.gd
```
