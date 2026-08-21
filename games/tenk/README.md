# 10,000

This folder contains Gamer Pub's local hot-seat version of the six-die game 10,000.

## Implemented rules

- 2–8 players; first to 10,000 wins immediately.
- A player must bank at least 1,000 points in one turn to get on the board.
- Scoring dice are selected from one roll and set aside; combinations cannot normally be assembled across rolls.
- Single 1s score 100 and single 5s score 50.
- Three 1s score 1,000; other triples score face value × 100.
- Each matching die after the third doubles the set's score.
- A straight scores 1,500.
- Three pairs, four-of-a-kind plus a pair, and two triplets score 1,000.
- When all six dice score, all six become available again ("and rolling" or hot dice).
- After every scoring roll, a player may set aside the selected scoring dice and reroll every unselected die. This may repeat as long as every new roll scores.
- The once-per-turn rescue reroll is offered only when the opening six-die roll has no scoring dice. The player may lock any 1–5 dice and reroll the rest once.
- Rescue-reroll dice form a six-die hand that is scored normally, supporting player-chosen attempts at straights, matching sets, and three-pair structures.

The supplied example where `4, 4` is followed by `4, 5, 5, 1` says both that the turn ends and that all-scoring dice are "and rolling." This implementation applies the general all-six-dice rule consistently, so that result scores 600 and is "and rolling."

## Checks

From the project root:

```powershell
godot --headless --path . --script games/tenk/tests/test_rules.gd
godot --headless --path . --script games/tenk/tests/test_game_flow.gd
godot --headless --path . --script tests/test_tenk_launcher.gd
```
