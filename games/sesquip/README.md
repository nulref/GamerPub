# Sesquip

Sesquip is Gamer Pub's local hot-seat word game. Two to four players extend one shared letter sequence using only the legal keys shown on screen. A complete word stays in play while the prototype lexicon contains a longer word with that prefix; the player who reaches a terminal word scores one point per letter.

## First playable scope

- Two to four local players with persistent round scores
- Five-second turns and automatic timeout passes
- An illuminated QWERTY keyboard containing only legal continuations
- Local trie-based prefix, word, and continuation checks
- Rotating opening player and a safeguard against endless consecutive timeouts
- Mouse, touch, and physical-keyboard input
- Responsive landscape and portrait layouts

## Lexicon

`data/starter_words.gd` is a hand-curated prototype vocabulary with a three-letter minimum. It exists to test the mechanic without a network dependency. It is not an Official Scrabble Players Dictionary, NASPA Word List, or Collins Scrabble Words list and should be replaced or substantially expanded before production.

## Checks

Run from the Gamer Pub repository root:

```powershell
godot --headless --path . --script games/sesquip/tests/test_lexicon.gd
godot --headless --path . --script games/sesquip/tests/test_game_flow.gd
godot --headless --path . --script tests/test_sesquip_launcher.gd
```
