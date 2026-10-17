---
name: crawl-run-progression
description: Implement Crawl's run lifecycle, temporary equipment, three-choice loot, gold settlement, permanent upgrades, and versioned saves. Use for progression and persistence in this Godot roguelite.
---

# Crawl run progression

Locate the intended Crawl workspace through `project.godot` and `docs/GAME_PLAN.md`. Read confirmed persistence requirements, proposed economy/camp/run defaults and the relevant milestone. Inspect existing inventory, controller and save implementations before adding models.

- Separate immutable item/class/skill/upgrade definitions, persistent profile values and mutable run state. Gear, supplies, temporary levels and statuses end with a run. Banked gold, purchases and chosen persistent presets survive. Do not serialize engine object references.
- Keep party-slot cap, initial slots, costs, class prerequisites and skill ranks in definitions. The plan's three-start/six-cap and gold banking policy are proposed defaults. Enforce purchases and caps in the model, not only disabled buttons.
- Use a run controller with explicit hub, exploration, combat, results, pending offer, room action, camp and terminal transitions. Pending choices block conflicting progression. Cleared encounters and consumed searches/chests/switches do not repeat.
- Generate chest/boss offers as three distinct eligible items when supported by the pool; provide enough content for the slice and an explicit fallback if later pools are too small. Store the rolled offer and its ID before presenting it. Choose exactly one, assign/equip it deliberately, and handle full inventory visibly.
- Award combat gold and drops once using stable encounter/reward IDs. Settle the run once using a run settlement ID and an atomic profile update; repeated result/load/abandon paths cannot duplicate banking. Define earned gold consistently with the plan's policy.
- Save profile and run separately with schema/content versions, ID-based data, validated loads and a last valid backup. Write safely through a temporary file and replacement when supported. Boundary saves should restore pending offers and consumed interactions without rerolls. Do not imply resumable mid-combat saving until implemented.
- Treat camp supplies and between-run upgrades as different economies. Camp cannot reset the floor, respawn enemies or restore unlimited resources through repeated entry.

Verify one-of-three claim idempotency, full inventory handling, insufficient-gold purchases, duplicate unlocks, party cap, victory/wipe/abandon settlement, and clean run reset with persistent unlocks retained. Exercise reload before/after a reward and settlement and a malformed save fallback. Report any unsupported schema migration or crash-recovery window explicitly.
