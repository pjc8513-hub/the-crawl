# Crawl: design and implementation plan

Status: planning baseline, 2026-10-16, with floor generation, automatic combat, tactics and the single-floor UI loop implemented. See [UI_PROTOTYPE.md](UI_PROTOTYPE.md) for the current screens, camp, gear choices and verification. [FLOOR_PROTOTYPE.md](FLOOR_PROTOTYPE.md) and [COMBAT_PROTOTYPE.md](COMBAT_PROTOTYPE.md) describe the earlier subsystem milestones. M4 now has results, room actions, one-of-three gear, limited camp and run completion. M5 persistent progression and saves remain unimplemented. The audit below records the original baseline.

## Product goal

A Godot dungeon roguelite about preparing a party, choosing a route, and configuring combat priorities. The player makes strategic decisions before and between battles; combat resolves automatically. Runs provide temporary builds and persistent gold upgrades.

The supplied map image is a visual reference: connected square rooms with colored borders. Its contents are reference material, not additional instructions.

## Confirmed requirements

- Procedurally generated floors; click an available room to move there.
- Green: current party room. Yellow: available destination. Red: locked or otherwise unavailable. Blue: explored.
- On entering an encounter, automatically fight; show results and loot afterward. Then offer camp, search, room interactions, or travel as applicable.
- Configurable conditions and priorities: healing potions below an HP threshold, healing spells below an HP threshold, low/high HP enemy targeting, and spell casting above an MP threshold.
- Multiple enemy groups, including encounters with three or four groups of roughly three to eight creatures; support larger authored hordes too.
- Enemy panel entries show icon, name, count, and Front/Middle/Back formation. Party panel shows individual HP, MP, and statuses. A fast log explains combat.
- Front groups protect deeper groups from direct physical attacks. Skills can bypass reach and target backline or highest-count groups.
- Ordinary single-target attacks damage one creature at a time. Group AoE damages every individual in its target group.
- Chests and bosses offer three gear choices; choose one to suit the current build.
- Run gold funds between-run upgrades: party slots up to a cap, new classes, new skills, and skill upgrades.
- Gear and run inventories are cleared when a run ends.

## Proposed defaults to make the first version buildable

These are reversible design choices, not claims that the user already selected them.

| Topic | Initial proposal |
| --- | --- |
| Party | Start with three members; six-slot eventual cap. Warrior, Cleric, Mage initially; Rogue as the first class unlock. |
| First playable slice | One seeded floor, 10-14 rooms, entry, ordinary fights, one chest, one boss and exit, one locked optional branch with its key reachable first. |
| Floor traversal | Cardinal grid connections only; adjacent tiles connect only when an explicit door exists. Backtracking through cleared rooms is free and does not respawn enemies. |
| Discovery | Show visited rooms and their immediate connected neighbors. Conceal undiscovered distant rooms. |
| Map precedence | Current green; reachable unblocked neighbor yellow (even if visited); blocked visible destination red; other visited room blue. Keep a separate visited marker so availability does not erase exploration history. |
| Camp | Open a camp screen from a cleared room; limited run supplies heal or restore MP. Returning preserves the floor and room. Camp is not the permanent upgrade hub. |
| Combat timing | Discrete rounds, initiative order with stable ID tie breaks. Pause and 1x/2x/4x playback. Speed changes presentation timing only. |
| Tactic edits | Configure outside encounters for the first slice; pause is for inspection, with no direct action commands. |
| Formation | Melee reaches the nearest occupied enemy row; ranged and flagged bypass abilities can reach deeper rows. Re-evaluate reach for every action. |
| Target HP rules | Compare living individuals' current HP; tie-break by stable unit ID. Label absolute HP versus HP percentage explicitly in the rule editor. |
| AoE | Damage all living members of one group; whole-battlefield AoE is a separate, explicit ability type. |
| Defeat | A member at zero HP is down for the encounter; a supply-based camp revive is possible after victory. Full party wipe ends the run. |
| Gold | At victory, defeat, or an explicit abandon, bank all earned run gold exactly once. No mid-run upgrade purchases. Unclaimed combat rewards are not earned gold. |
| Run end | Clear gear, consumables, temporary levels, room state, and active statuses; retain purchased unlocks and strategy presets. |
| Run completion | First slice ends after boss victory; later add a proposed three-floor run with persistent HP/MP between floors. |

Confirm or revise these values while implementing their milestone; keep them in data rather than hard-coded UI logic.

## Existing project audit

| Existing artifact | Useful foundation | Work required |
| --- | --- | --- |
| `project.godot` | Declares Godot 4.7 features and canvas item stretch | No `run/main_scene` entry; establish a working baseline viewport and minimum window size. Use the locally installed compatible engine rather than changing versions speculatively. |
| `scenes/main.tscn` | Main, Systems, exploration/combat viewport branches, HUD/pause/transition/debug layers | No attached scripts; controls are mostly 40 by 40. ScreenFilter may cover content if expanded. Decide whether the unused SubViewports are necessary before wiring UI. |
| `DungeonRoomData.gd`, `FloorDefinition.gd` | Rooms, doors, pools, events, floor variants | Both reference missing `EnemyGroupResource`. Add an encounter definition Resource, separate from mutable combat groups. |
| `DoorData.gd` | Direction, destination, key and switch conditions | Add stable door identity or an unambiguous shared edge ID: interactables currently name a target door but doors have no ID. Synchronize both directions on unlock. |
| `EnemyResource.gd` | Enemy stats, roles, rewards, resistance flags, icon hook | Distinguish authored definitions from runtime HP, statuses and cooldowns; formalize skill references and formation defaults. |
| `EnemyGroup.gd` | Runtime group count and row | Tracks only one injured member; `take_damage` spills into subsequent members. Replace with per-unit state for independent AoE, healing, statuses and strictly single-target damage. Derive count from living members. |
| Seven enemy `.tres` files | Kobold Fighter/Knight/Skeleton/Wizard; Goblin Cleric/Ninja/Zombie | Preserve concepts; validate ranges and formulas before balancing. Fighter spawn `3d5` implies 3-15 but count bounds say 3-5. Skeleton HP `2d6` implies 2-12, stored max is 6 and average is 7. Several counts exceed 8, which should remain possible as authored exceptions. |
| Other folders | `autoload`, `scripts`, `systems`, `assets`, `shaders` | No gameplay code found there. Build on the structure without introducing a second project. |

No `AGENTS.md` was found in the project or checked parent directories. This folder is not currently a Git repository. Godot is not available on the inspected command PATH; this is not proof that the editor is absent. No engine import or execution has been performed for this plan.

## Architecture and state ownership

Use typed GDScript and Godot Resources for editable definitions. Keep simulation independent of scene nodes so seeded tests can run without rendering. Proposed names below are implementation targets, not existing APIs.

| Layer | Proposed artifacts | Responsibility |
| --- | --- | --- |
| Definitions | Existing Resources plus `EnemyGroupResource`, `ClassDefinition`, `SkillDefinition`, `ItemDefinition`, `TacticRule`, `UpgradeDefinition` | Authoring inputs; loaded assets are treated as immutable. |
| Runtime | `RunState`, `FloorState`, `RoomState`, `PartyMemberState`, `EnemyUnitState`, `EnemyGroupState`, `CombatState` | Mutable instances with stable IDs. Never mutate a shared `.tres` during play. |
| Simulation | `systems/dungeon/`, `systems/combat/`, `systems/loot/`, `systems/progression/` | Seeded generation, action resolution, rewards and purchases. |
| Coordination | `scripts/run_controller.gd`, small save service in `autoload/` if needed | Own state transitions and save checkpoints; avoid a global singleton for each model. |
| Presentation | `scenes/ui/`, `scripts/ui/` | Render snapshots/events; send validated intents. Widgets never award loot or resolve damage. |
| Verification | `tests/` and fixed seeds | Small headless GDScript runner for model behavior; UI smoke checks in the editor. No testing framework required initially. |

State flow:

```text
Hub -> Party preparation -> Generate floor -> Exploring
Exploring -> Combat -> Results -> Reward choice (when applicable) -> Room actions
Exploring -> Room actions (cleared/safe room)
Room actions -> Camp -> Room actions
Room actions -> Exploring / Next floor
Boss completion or party wipe or Abandon -> Settle run -> Hub
```

Only the controller may commit transitions. Block movement during combat, unresolved results, or a pending mandatory choice. A cleared room revisit does not repeat its encounter. Search, chest, switch, and reward IDs make repeated clicks harmless.

### Seed and generation contract

Record the run seed, generator version and content version. Derive separate floor, encounter, loot and combat seeds so UI playback and unrelated RNG draws cannot change dungeon layout. Stable traversal order and IDs are part of reproducibility.

Generate a connected graph on `Vector2i` coordinates: create a start-to-boss spine, add bounded branches and a few loops, then assign room types. Use a floor budget to choose encounter groups and counts; do not multiply enemy counts without regard to party action economy. The graph defines doors, not geometric proximity alone.

Validate the mandatory route with actual key/switch state transitions. Place optional branch keys on an accessible side of the lock. Prevent a lever or required key from spawning behind its own lock. Limit generation attempts and fall back to a known-valid layout if constraints cannot be satisfied. Debug output includes the seed and rejection reason.

### Auto-combat and tactics contract

Each group contains independently tracked living/dead units, HP and statuses. The UI collapses those units into one entry. One ordinary attack targets one unit and discards overkill; cleave explicitly permits spill. Group AoE resolves damage against each living unit in a snapshot of that group. Rewards are based on actual defeated units and committed once.

For each ready actor, evaluate enabled rules in displayed priority order. A rule has an ID, condition subject, metric, comparator, threshold, action, target selector, and optional resource reserve. Use the first rule with a true condition AND a legal, payable action; otherwise continue, then fall back to basic attack, or defend when no legal attack exists. Failed rules consume no MP, items, or action. Commit costs and effects atomically and re-check target validity at execution.

Example ordered rules:

| Priority | Condition | Action and target |
| --- | --- | --- |
| 1 | Self HP below 25% and potion available | Drink potion |
| 2 | Lowest living ally HP below 40%, sufficient MP | Heal that ally |
| 3 | Self MP above 35%, sufficient spell cost, enemy group count at least 4 | Cast group AoE at highest-count legal group |
| 4 | Always | Basic attack at lowest current HP reachable enemy |

Threshold comparisons must be visible (`below` means strictly less than). Handle zero maximum MP without division; the MP percentage condition is false for actors with no MP pool. Define status duration in turns with one documented tick boundary. Dead or stunned actors cannot act. End combat immediately when one side has no living units; use a round limit/stalemate outcome for unresolvable fights, with no victory rewards. Emit structured action, damage, heal, status, defeat and completion events; generate readable log text in presentation.

### Rewards, inventory and saving contract

Loot offers have stable IDs, three distinct eligible items when the pool supports it, and one committed selection. Expand the slice loot pool enough to guarantee three distinct choices; define a visible fallback for later constrained pools. Preview stats and equipment slot, permit party assignment, and explicitly resolve full inventory. Never silently replace an item or grant all three. Ordinary encounters can grant gold and ordinary drops separately.

Keep `ProfileSave` (banked gold, unlocks, upgrade ranks, strategy presets) separate from `RunSave` (seed/version, party, map, supplies, temporary gear, pending offers). Serialize IDs and values rather than engine object references. Use a save schema version, temporary write plus atomic replacement where supported, and a last valid backup. Validate loaded values. Do not reroll a pending offer on reload. Give each run settlement an ID so reopening results cannot bank gold twice. The initial slice can save at room boundaries; resumable mid-combat saves are later work.

## Implementation milestones

Each milestone ends with a runnable outcome and focused acceptance checks. Do not build broad content before the loop works.

### M0 - Make the skeleton load reliably

- Resolve `EnemyGroupResource`; retain the distinction between spawn definition and runtime group.
- Configure startup scene and viewport. Replace or properly size placeholder controls; keep the existing scene where useful.
- Review stat/formula discrepancies. Proposed policy: dice formula is canonical for rolled HP/count, derived bounds/averages are validated; do not silently reinterpret existing content.
- Add a minimal scene/controller and content validation entry point.
- Acceptance: project imports without script/resource errors; main launches into a usable placeholder; all seven enemy definitions either validate or produce actionable errors before encounter generation.

### M1 - Establish a deterministic combat model

- Implement party/class/skill runtime state, enemy units grouped for presentation, rounds, initiative, reach, damage, MP, healing, statuses, victory/defeat and event records.
- Provide a fixed party versus Fighter/Wizard fixture; avoid requiring dungeon UI to test combat.
- Acceptance: 40 damage against a 10 HP creature kills exactly one with an ordinary hit; explicit cleave can cross units. Group AoE of 6 against HP `[5, 10, 10]` yields dead/4/4 and count 2. Backline melee is blocked until closer rows die; ranged bypass works. Identical seeds and inputs produce identical event streams. Resource costs never go negative; stalemates terminate.

### M2 - Add executable tactic priorities

- Implement ordered rules, thresholds, selectors, reserves, legality and fallback behavior; add presets for Warrior, Cleric and Mage.
- Acceptance: exactly 40% HP does not trigger a `below 40%` heal. An unavailable potion or unaffordable heal falls through. A no-MP actor cannot divide by zero. A target killed earlier in the round is safely reselected. A highest-count/backline selector still respects ability reach.

### M3 - Build one navigable procedural floor

- Implement seeded graph generation, doors, key/switch availability, visibility and persistent room flags.
- Render clickable square rooms using the supplied color semantics, with an explicit legend and visited marker.
- Acceptance: a fixed batch of at least 100 seeds satisfies room bounds, unique coordinates, reciprocal doors, connected topology and a solvable mandatory route. Same seed/version yields the same layout. Locked optional branches are solvable. Nonadjacent and blocked clicks do nothing; cleared revisits do not respawn encounters. Current/explored/available overlap follows the stated precedence.

### M4 - Connect the complete room loop and combat screen

- Present enemies left, party right and a bounded scrolling log below; counts and statuses update from model events.
- Add pause/speed controls, results, ordinary rewards, one-of-three chest/boss choices, search and limited-supply camp.
- Suggested layout: persistent party/resources header, central map or combat view, room actions/results below. At 1280x720 keep panels readable; verify at 1920x1080 and the chosen minimum supported size. Reflow or scroll at smaller sizes instead of clipping.
- Acceptance: enter room -> automatic combat -> results -> claim reward -> camp/search/interact/travel works. Double clicks cannot enter two battles or duplicate rewards. Camp cannot be used during combat. Playback speed leaves outcomes unchanged. A four-group/eight-creature fixture stays readable without rendering 32 individual sprites. Cleared-room actions remain consumed after revisit.

### M5 - Add the hub and permanent progression

- Implement versioned profile/run saves, idempotent gold settlement, class/skill purchases and capped party-slot purchases.
- Create the proposed three-member start and six-member cap as data values. Upgrade costs and unlock dependencies live in definitions.
- Acceptance: victory, wipe and abandon each bank exactly once according to the chosen policy. Insufficient funds, repeat unlocks and cap overflow are rejected. Starting another run retains upgrades and removes all previous run gear/consumables/statuses. Reloading a pending offer does not reroll it. A damaged save falls back visibly to a valid backup rather than silently losing progress.

### M6 - Expand into a replayable roguelite

- Add multiple floors, themed encounter budgets, elites, bosses, gear synergies, class builds and clearer tactic explanations.
- Integrate existing variant/event/NPC/side-dungeon hooks after the core loop is stable. Add party formation rules only with explicit reach and targeting semantics.
- Acceptance: several seeded complete runs can win or lose without stuck progression; optional branches offer meaningful risk/reward; starting builds and gold purchases leave more than one viable strategy. Record run length, damage/healing by ability, deaths, unused supplies and upgrade costs to guide balance.

## Scope and next action

The first playable slice is M0-M4: one complete floor with automatic combat, tactics, loot and camp. M5 completes the requested persistent progression loop. M6 adds breadth. Multiplayer, real-time action controls, crafting, procedural art, complex economy simulation and extensive NPC dialogue are outside this baseline.

Start with M0, then the M1 combat fixture. This resolves the existing definition gaps and group-damage representation before UI or content depends on them.

## Reusable skills

Authoring copies are in `skills/`; install copies in the Codex skills directory for automatic discovery. Skills locate this project through `project.godot` and this plan rather than assuming every Godot project follows these rules.

| Skill | Use it for |
| --- | --- |
| `crawl-floor-generation` | Seeded room graphs, door/key constraints, movement and room availability |
| `crawl-auto-combat` | Individual enemy simulation inside groups, formation reach, tactics and combat events |
| `crawl-game-ui` | Square map, stacked combat display, tactic editor, results and room actions |
| `crawl-run-progression` | Run lifecycle, temporary gear, reward choices, persistent upgrades and saves |

Example follow-up: `Use $crawl-auto-combat to implement M1 from docs/GAME_PLAN.md, including a deterministic combat fixture and its acceptance checks.`
