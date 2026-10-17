# Mage control and elemental skills

Sleep is learned by new Mages. Freezing Wind, Charming Potion, Earthquake, Combust and Chain Lightning are purchased as Mage skill unlocks at the lodge. Mage tactics can be reordered to choose when each spell is used. The values in `systems/combat/combat_content.gd` and `resources/ProgressionDefinition.gd` are provisional balance defaults.

| Skill | MP | Power | Effect |
| --- | ---: | ---: | --- |
| Sleep | 5 | 0 | Air, one group, 45% sleep chance per unresistant enemy |
| Freezing Wind | 7 | 4 | Air, one group, 35% freeze chance |
| Charming Potion | 9 | 0 | Water, one group, 35% base flee chance plus the enemy's authored flee chance; only enemies allowed to flee |
| Earthquake | 10 | 9 | Earth, one group, 30% stun chance |
| Combust | 12 | 24 | Fire, single target, applies a three-turn burn when not resisted |
| Chain Lightning | 18 | 18 | Air, one group, no status |
| Magic Missile | 0 | 3 | Water, single target, low damage |

Meditation, Mind Expansion and Focus are unlockable passive Mage skills. Their provisional values are 20% of maximum MP restored after each battle for a living Mage, +20 maximum MP, and 20% lower MP costs for spells, respectively. Focus rounds the reduced cost up. Passives apply automatically and do not appear as combat actions.

Damage uses spell power plus the Mage's magic stat. Matching elemental resistance halves damage, rounded down, and blocks the spell's status or flee effect. Sleep ends when damage lands; that hit deals 50% more damage. Frozen enemies lose their turn and have a 50% thaw chance at each opportunity. Winter Staff and Glacial Charm reduce this chance by 20 and 30 percentage points, respectively, reaching zero together. Burn deals four damage at the start of each turn and increases other incoming damage by 20%. Fled enemies leave combat and award no gold. EXP is authored on enemies but is not currently awarded by the run model.

Sleep, Freezing Wind, Charming Potion and Earthquake ranks add 10 percentage points to effect chance; Freezing Wind and Earthquake also gain power. Winter Staff adds 15 percentage points to effect chance. Elemental and status rolls use the seeded combat RNG.
