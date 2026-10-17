# Warrior passives

The six skills are lodge unlocks for Warriors and apply automatically when learned. Their costs and powers are provisional values in `resources/ProgressionDefinition.gd` and `systems/combat/combat_content.gd`.

| Passive | Current effect |
| --- | --- |
| Intimidate | At battle start, each living Front row enemy has a 35% chance to gain Fear, unless spirit resistant. Fear persists for the battle and has a 30% chance to skip each turn. |
| Battle Harden | At battle start, gain 1 physical armor per living Front row enemy. This battle bonus uses the starting count. |
| Blood Lust | Gain +1 physical attack power per enemy downed by a party member, including a party-sourced damage-over-time kill, up to +12 for the battle. Fleeing does not count. |
| Giant Slayer | Against a target with more current HP than the Warrior, gain `floor(100 × HP difference / Warrior max HP)%` physical power, capped at 50%. |
| Berserk | Gain +1 physical power per 10 missing HP, capped at +10. The bonus updates with damage and healing. |
| Aegis | Each living Warrior with Aegis has a 20% chance to block an incoming damaging enemy action against any party member. Warriors roll in stable ID order; one successful block cancels damage and attached status for that hit. It does not block poison or burn ticks. |

Multiple Warriors apply their own Battle Harden and Blood Lust bonuses. Intimidate rolls independently per Warrior and enemy, while Fear itself does not stack. Battle armor and Blood Lust reset when a new encounter begins. The combat event log records fear, passive bonuses and blocks.
