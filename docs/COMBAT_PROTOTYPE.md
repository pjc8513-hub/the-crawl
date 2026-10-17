# Auto-combat and tactics prototype

Update: the room UI now includes an aftermath screen, camp, temporary gear and boss/chest reward choices. See [UI_PROTOTYPE.md](UI_PROTOTYPE.md) for current controls, content version 3 and the complete screen flow. The subsystem notes below record the earlier combat-only milestone.

Press **F5** in Godot 4.7. The project now starts a three-member Warrior/Cleric/Mage party. Choose **Party tactics** before entering a room to edit thresholds, target selectors, MP reserves, minimum target group size and rule order. The first enabled rule with a matching condition, an affordable learned skill and a legal target wins. Disabled or unusable rules fall through; basic attack and then defend are the fallbacks.

Click a yellow room. An uncleared room starts combat automatically; the debug-clear button is gone. Enemy entries show an icon (a placeholder diamond when no art exists), name, living/original count, row, aggregate HP and statuses. Party entries show HP, MP, remaining healing potions and statuses. Pause stops simulation advancement. Speed changes how quickly actor opportunities are displayed, without changing the sequence of model events.

After combat, **Continue** acknowledges results. Victory grants gold once and clears the room; other outcomes end this prototype run and keep movement blocked. Cleared rooms do not repeat battles. Party HP, MP and remaining potions persist between fights. **New run** resets the party, gold, tactics and floor, including when used to abandon an ongoing battle. There is no save or permanent banking yet. Gear selection, camp supplies/revives, boss-specific abilities and permanent upgrades remain future milestones. The designated boss room currently uses the ordinary encounter system.

## Implemented model

- Each creature has independent HP, MP and status state. UI stacking never combines their health into a shared damage pool. Ordinary attacks discard overkill. Cleave explicitly carries remaining damage through the selected group after mitigation. Group spells affect a snapshot of the living members of one selected group.
- Melee can hit the closest occupied opposing row. Ranged spells bypass row protection. A backline selector still respects its action's reach. Both sides use the same reach rule; party melee users may attack from their own row in this initial model.
- Initiative is descending initiative stat, then ascending stable actor ID. Each living creature gets one opportunity per round; dead queued actors are skipped. Targets are chosen at execution time, avoiding retained dead targets.
- Conditions include self HP %, lowest living ally HP %, self MP %, largest opposing group count and always. Comparators support below, above, at most and at least. Below/above are strict; no-MP actors never satisfy an MP-percent condition. Target selectors distinguish absolute HP and HP %, plus highest HP, highest count, self and backline.
- A chosen action is validated again immediately before costs are committed. Dead, unreachable or invalid targets, invalid skills, insufficient MP, reserves and missing potions consume nothing. Healing never revives and does not waste resources on a full-health target.
- Poison ticks and loses one duration at the start of its owner's opportunity. Stun consumes an owner opportunity and then expires according to its duration. A poison death prevents that actor's action. Defend halves incoming damage until the owner's next opportunity. Status reapplication replaces duration/potency rather than stacking. Statuses are encounter-scoped in this prototype and reset when another battle begins.
- End conditions are victory, defeat, draw, invalid setup and a configurable round-limit stalemate (default 100). Only victory grants gold. Terminal steps and result acknowledgement are idempotent. The event log is presentation of structured events and does not resolve actions.

## Initial configurable balance

`resources/ClassDefinition.gd`, `CombatSkill.gd` and `TacticRule.gd` define editable fields. `systems/combat/combat_content.gd` builds the initial presets; these are tuning defaults, not final balance. Starting party HP is 120/95/75, MP is 12/40/42, and each member has two 35-HP potions. Cleric healing defaults to below 40% ally HP. Mage Fireball defaults to above 35% MP and a target group of at least four. Potions default to below 25% self HP.

Enemy HP is rolled from validated dice with a separate HP stream. Enemy physical power is `1 + strength + bonus_damage_base`; magic is `wisdom + magic_amp_base`; physical armor is `floor(endurance / 2)`; initiative is `dexterity + initiative_bonus`. Damage is skill power plus the applicable attack/magic stat, minus physical armor, then defend/resistance reductions. Fire, physical and spirit resistance flags halve matching damage, rounded down. Other resistance types await corresponding skills. Skill damage variance is supported and seed-controlled; supplied skills currently use zero variance.

Enemy Wizards have Fire Dart and a 12-MP pool. Enemy Clerics have healing and a 12-MP pool; other enemies use basic attacks. Accuracy, old-school AC, flee chance and the existing weighted `skill_id` dictionary are not yet interpreted. Their final rules need a separate balancing decision. Enemy counts still use the floor's explicit uniform spawn bounds and budget, while HP uses dice; spawn dice are checked for consistency but are not the floor's count distribution.

Two authored inconsistencies were corrected according to the plan's formula-first policy: Kobold Fighter `max_group_count` is now **15** for `3d5`; Kobold Skeleton `max_hp` is now **12** for `2d6`. The seven existing enemy assets now validate. Invalid definitions produce actionable messages before instantiation. Content version is now **2**; generator version remains **1**. Combat seed derivation includes content version, run seed, floor depth and coordinates. Reproduction is scoped to this code/content and the Godot RNG/hash implementation.

## Main files

| File | Responsibility |
| --- | --- |
| `systems/combat/combat_engine.gd` | Pure turn resolution, rules, reach, costs, damage, status ticks, events and outcomes |
| `systems/combat/combatant.gd` | Mutable individual state |
| `resources/EnemyGroup.gd` | Runtime grouping with derived living counts and independent members |
| `systems/combat/enemy_validation.gd` | Dice parsing, range/average checks and seeded HP rolls |
| `systems/combat/encounter_session.gd` | Room encounter setup, persistent party references, pending results and once-only gold |
| `scripts/ui/combat_panel.gd` | Group display, party bars, pause/speed and bounded log |
| `scripts/ui/tactics_panel.gd` | Per-run tactic editing and priority reordering |
| `scripts/floor_preview.gd` | Existing main-scene coordination and playback timing |

## Verification

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/test_combat.gd
godot --headless --path . --script tests/test_floors.gd
godot --path . --rendering-method gl_compatibility --script tests/test_floor_preview.gd
```

The combat suite covers dice validation for all seven assets, overkill, cleave mitigation, individual AoE/resistance, formation reach, rule thresholds, fallthrough/reserves, no-MP handling, real heal/potion costs, dead-target retargeting, poison/stun/defend, terminal outcomes and reward acknowledgement. Thirty repeated seeded Fighter/Wizard fixtures compare complete event streams. The existing 100-seed floor suite remains a regression check.

Rendered checks exercise map input -> combat -> results -> acknowledgement, pause and identical event output at 1x/4x, plus map, tactics and combat layout at 960x600, 1280x720 and 1920x1080. Screenshots are generated under `tests/preview_*.png`. The UI uses scrolling where needed for large groups, status text and tactics.

Final verification: **457 combat assertions and 3,358 floor assertions passed**, with no failures. Rendered checks passed at all three sizes, including a 32-enemy/four-group fixture. Screenshots were visually inspected; compact styling keeps all three party members and four group summaries visible at 960x600. These checks establish model correctness for the covered cases and screen integration; overall run balance remains provisional.
