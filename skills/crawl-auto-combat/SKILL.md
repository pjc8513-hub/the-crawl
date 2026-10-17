---
name: crawl-auto-combat
description: Implement or tune Crawl's deterministic party auto-combat, grouped enemies, formation reach, and ordered tactic rules in Godot. Use for combat simulation and tactics rather than generic combat UI.
---

# Crawl auto-combat

Locate the Crawl project through `project.godot` and `docs/GAME_PLAN.md`. Read the combat requirements, proposed defaults, combat contract and relevant milestone; inspect current resources and simulation code. Keep new balance assumptions configurable and documented.

- Treat `EnemyResource` and skill/class/item definitions as immutable inputs. Create runtime state with stable actor IDs. The existing `EnemyGroup.gd` may still track one injured creature and spill damage: inspect and replace that representation when implementing individual effects.
- Keep every enemy's HP and status independent even though presentation collapses it into a type/formation entry. Derive living group count. An ordinary attack damages one individual and discards overkill; cleave is an explicit exception. Group AoE affects each living individual in one selected group, not a shared HP pool or every group.
- Resolve melee against the nearest occupied row and recompute reach per action. Backline selection cannot bypass reach without an ability flag. Tie-break selections and initiative with stable IDs.
- Resolve ordered tactic rules using the first true condition with a legal target and payable action. Failed conditions or unaffordable/unavailable actions fall through without costs. Commit action costs and effects together; revalidate at execution. Use basic attack, then defend if no attack is legal.
- Make threshold metrics, subjects and strict/inclusive comparisons explicit. Preserve absolute HP versus percentage distinctions. MP percentage predicates are false for actors with no MP pool. Clamp HP and reject negative costs/damage.
- Keep rounds, status ticks, stun, death, targeting and terminal outcomes in the simulation; pause and playback speed only affect presentation. End on a defeated side and bound stalemates without granting victory rewards.
- Emit structured events with IDs, actor/target, action, values and outcome. UI converts these to readable logs. Do not make scene timers, log text or visual effects authoritative.

Use seeded fixtures that verify single-target overkill, per-unit AoE, reach changes after a front group dies, rule threshold boundaries, depleted MP/items, dead-target handling, deterministic event output and bounded termination. Validate existing enemy formulas/ranges before consuming them; do not silently pick contradictory values. Summarize observable behavior and unresolved balance choices.
