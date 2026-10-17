# Floor generation prototype

Update: automatic encounters have replaced debug clearing. See [COMBAT_PROTOTYPE.md](COMBAT_PROTOTYPE.md) for current controls, corrected enemy data, content version 2 and combat verification. The floor-only implementation notes below describe the earlier traversal prototype.

Run the project in Godot 4.7 (F6 for `scenes/main.tscn`, or F5 for the configured main scene). The existing main scene now hosts a floor exploration harness; unused viewport branches are preserved and hidden.

Enter an integer seed and choose **Generate floor** to reproduce a layout. Click yellow rooms to travel. Green is the party location, red is blocked, and blue is explored. A blue dot retains visited history when a room is also yellow or green. Hover a room for its movement requirement.

Ordinary and boss rooms block travel until resolved. **Debug: clear encounter** is a development control and grants no rewards. Search cleared rooms for the reusable standard key. It opens the locked optional chest room. Searches, cleared rooms and discovery persist while exploring the generated floor. Generating another floor resets this preview state. Combat, gear choices, saving and floor-to-floor runs are not implemented here.

## Code and configuration

- `resources/FloorDefinition.gd`: room counts, spine length, loop chance, retry limit, group cap and encounter budget. Defaults are the plan's proposed values: 10-14 rooms and up to four groups.
- `resources/EnemyGroupResource.gd`: immutable spawn options, including explicit count bounds, formation and per-unit budget cost. Spawn bounds are independent of dice formulas for this prototype; existing enemy data has not been silently rebalanced.
- `systems/dungeon/floor_generator.gd`: graph generation, validation, budgeted encounter rolls and independent seed streams. The optional locked leaf is added after loops so no alternate edge bypasses its gate.
- `systems/dungeon/floor_state.gd`: mutable room instances, door pairs, visibility, movement, reusable keyring, one-shot searches and switches. The future run controller can set `travel_block_reason` while combat results or rewards are pending.
- `scripts/floor_preview.gd` and `scripts/ui/dungeon_map.gd`: preview coordinator and drawn map. Authored enemy definitions are referenced but not mutated. Current preview pools are built by the coordinator.

Reproducibility is scoped to generator/content version 1 and the Godot RNG/hash implementation used here. Preserve those versions and serialized state when adding saves; do not assume future engine versions reproduce historical seeds. Layout, encounters and loot have separate seeds. Loot is reserved and is not rolled yet.

Generation attempts are bounded; failed candidates record the seed/version and reason. The fallback builds a connected cardinal spine and branches with a gated leaf. Invalid generation settings are clamped to supported limits (6-64 rooms, at least three spine rooms, 1-32 attempts). Topology validation assumes reachable encounters can be won and keys are reusable. It checks all rooms can eventually be accessed, including optional locks and switch chains; it does not assess combat difficulty.

The current boss room is a graph destination with a regular encounter preview. Authored boss selection, floor variants, side dungeons, events, and actual chest contents remain future integrations. The UI labels these limits explicitly.

## Verification

With a compatible Godot executable:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_floors.gd
godot --path . --rendering-method gl_compatibility --script tests/test_floor_preview.gd
```

The model suite verifies a 100-seed batch, exact repeated layouts, reciprocal cardinal edges, movement rules, current/available/visited precedence, key-before-lock and switch chains, consumed searches, cleared revisits, pending-action locks, larger authored hordes, budget bounds, immutable definitions and fallback validity. The render smoke script exercises map clicks and captures the preview at 960x600, 1280x720 and 1920x1080 to `tests/preview_*.png` for visual inspection. These images are generated verification artifacts.

Verified with the installed Godot 4.7 stable engine: **3,358 model assertions passed**, headless main-scene startup completed without errors, and the rendered smoke check passed at all three sizes. The screenshots were visually inspected; the compact sidebar scrolls to keep room actions and messages visible. Engine import completed without script/resource errors. This does not complete M0's separate enemy dice/stat content audit, nor validate the future combat system.
