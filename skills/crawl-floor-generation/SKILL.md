---
name: crawl-floor-generation
description: Build or revise seeded procedural floors, door constraints, and room traversal for the Crawl Godot roguelite. Use for this project rather than unrelated dungeon generators.
---

# Crawl floor generation

Locate the Crawl project root using `project.godot` and `docs/GAME_PLAN.md`; if the project is not in the current workspace, obtain its location before editing. Read the plan's requirements, proposed map defaults, seed contract and relevant milestone. Treat proposed values as configurable defaults, not settled user decisions. Inspect the current definitions before inventing replacement types.

- Reuse `resources/FloorDefinition.gd`, `DungeonRoomData.gd`, `DoorData.gd` and `DungeonEnums.gd`. Resolve the missing `EnemyGroupResource` if it still blocks imports; it is an authored spawn definition, not a live combat group.
- Generate explicit cardinal graph edges on unique integer coordinates. Touching rooms are not automatically connected. Generate a connected start-to-boss route before optional branches/loops and room contents.
- Store RNG seed/version and use separate streams for layout, encounters and loot. Bound retries and retain a valid fallback with a diagnostic reason.
- Validate keys/switches against actual reachability with unlock state, including multi-lock paths. Never place a mandatory unlock behind itself. Both directions of a door share identity and state.
- Distinguish discovered, visited, cleared, current and currently reachable. Movement legality depends on the present room and door state, not the button color. Revisit must preserve consumed interactions and avoid replaying cleared encounters.
- Preserve the green/current, yellow/available, red/blocked and blue/explored map language. Apply the documented precedence and a separate visited marker when states overlap. Return a blocking reason for UI tooltips.
- Scale encounter composition with budgets and preserve authored count exceptions; the desired 3-4 groups of 3-8 is a common presentation target, not a universal clamp.

Keep generation and validation usable without scene rendering. Verify a fixed seed batch for connectivity, reciprocal edges, bounds, reachable progression and reproducibility; include seed/version in failures. Check movement rejects non-neighbors and locked doors, and that a key or switch unlock updates both directions. Report implemented behavior, checks and remaining generator constraints.
