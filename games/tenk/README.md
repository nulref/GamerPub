# 10,000

This folder contains Gamer Pub's local hot-seat version of the six-die game 10,000.

## Implemented rules

- 2–8 players; first to 10,000 wins immediately.
- A player must bank at least 1,000 points in one turn to get on the board.
- All six dice remain visible during a hand. Selected dice lock in place while every unselected die rerolls in its original position.
- Single 1s score 100 and single 5s score 50.
- Three 1s score 1,000; other triples score face value × 100.
- Each matching die after the third doubles the set's score.
- Matching sets must be rolled together. The exception is a locked pair: one matching die on the immediately following roll completes its triple. If that next roll misses, later matching dice retain their single-die value, if any.
- A straight scores 1,500.
- Three pairs, four-of-a-kind plus a pair, and two triplets score 1,000.
- When all six dice score, all six become available again ("and rolling" or hot dice).
- Reroll is enabled when the selection contains scoring dice, five faces toward a straight, three to five matching dice, two pairs, or one triple toward two triplets.
- Scoring selections may repeat until all six dice score ("and rolling") or a reroll cannot score or advance a qualifying combination (bust).
- The once-per-turn rescue rule applies only when the opening six-die roll has no score.

## Checks

From the project root:

```powershell
godot --headless --path . --script games/tenk/tests/test_rules.gd
godot --headless --path . --script games/tenk/tests/test_game_flow.gd
godot --headless --path . --script tests/test_tenk_launcher.gd
```
