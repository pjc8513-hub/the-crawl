---
name: crawl-game-ui
description: Build Crawl's Godot square-room map, grouped combat panels, tactic editor, results, and camp or room-action screens. Use for this game's interface and its simulation integration.
---

# Crawl game UI

Find `project.godot` and `docs/GAME_PLAN.md` in the intended Crawl workspace. Read the confirmed UI requirements, proposed display defaults and current UI milestone. Inspect `scenes/main.tscn` before replacing its structure: the initial nodes are largely unsized placeholders and the SubViewports have no established behavior.

- Prefer Godot Control containers, anchors and minimum sizes for panel layout. Keep SubViewports only when the current rendering needs them; preserve useful existing scene nodes. Check ScreenFilter visibility and mouse filtering when expanding it.
- Draw connected square rooms with green/current, yellow/available, red/blocked and blue/explored borders. Implement the plan's overlap precedence, a visited marker, legend and non-color cues. Never make color the movement authority: submit a destination intent to the controller and display its rejection reason.
- Combat has enemy entries on the left with icon/name/count/row, party members on the right with HP/MP/status, and a bounded fast log below. Use one enemy entry per distinct runtime group; groups of the same type in different rows remain separate. Support 4 groups of 8 and larger authored hordes without 32 sprites.
- Show pause and speed controls without direct player combat actions. Render structured simulation events and state snapshots; speed must not change costs, rolls or outcome.
- A tactic editor exposes ordered rules, enabled state, condition subject/metric/comparator, threshold, action and selector. Distinguish percent from absolute HP and show why a rule cannot execute. Do not expose raw engine IDs as player-facing labels.
- Results summarize outcome, gold, casualties and loot. A chest/boss offer presents three comparable options, one selection, equipment assignment and a clear inventory-full resolution. Disable duplicate submissions while the controller commits.
- Room actions reflect actual clearance, supplies and consumed flags. Camp returns to the current room. Keep permanent upgrades in the between-run hub. Block travel behind unresolved combat/rewards through controller state.

Verify at the plan's baseline and smaller supported size, checking long names, many statuses, large counts, no-MP classes and log overflow. Exercise the complete room -> combat -> results -> choice -> camp/travel flow, including double clicks and cleared revisits. If engine/UI execution is unavailable, state that limit and distinguish scene inspection from a successful launch.
