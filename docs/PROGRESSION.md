# Run progression, the lodge and saves

Implemented 2026-10-17. Press **F5** in Godot 4.7 to start at the Wayfarers' Lodge. The existing dungeon/combat loop now connects to permanent gold, purchases, party preparation and resumable checkpoints.

## Playing between runs

At the lodge, select a class for every available party slot and enter an integer seed, then choose **Begin expedition**. Warrior, Cleric and Mage are available initially with three party slots. Duplicate classes are allowed and receive distinct actor IDs and member numbers.

Gold earned by acknowledged combat victories remains run gold until the expedition ends. Victory, party defeat, draw/stalemate and **Bank & abandon** settle all earned run gold once. Results that have not been acknowledged are not earned gold; abandoning while those results are pending does not collect their reward. Simply closing the game preserves the saved expedition rather than abandoning or banking it.

Temporary gear, equipment bonuses, consumables, statuses and camp supplies are cleared at run end. The completion screen keeps final gear names for the summary. Banked gold, purchases, class unlocks, skill ranks, selected party composition and class strategy presets survive.

The lodge offers these provisional economy values from `resources/ProgressionDefinition.gd`:

| Purchase | Cost / limit | Effect |
| --- | --- | --- |
| Party slots 4, 5, 6 | 150, 350, 700 gold | Adds one selectable member slot; maximum six |
| Rogue class | 120 gold | Unlocks an 85 HP / 18 MP, fast melee class |
| Cleave | 120 gold; Warrior | Adds the learned skill to new Warrior members |
| Poison strike | 100 gold; Rogue | Adds the learned skill to new Rogue members |
| Stunning strike | 160 gold; Rogue | Adds the learned skill to new Rogue members |
| Attack rank | 60 × next rank | +2 power per rank |
| Heal rank | 80 × next rank | +4 power per rank |
| Fireball rank | 100 × next rank | +3 power per rank |
| Cleave rank | 100 × next rank; unlock first | +3 power per rank |
| Poison/Stunning strike rank | 80/100 × next rank; unlock first | +2 power per rank |

Skill ranks cap at three. The model rejects insufficient funds, duplicate unlocks, unmet class/skill prerequisites, unknown purchases and cap overflow. Purchases require that no saved expedition is active. Party upgrades modify newly built party skill definitions; enemy skill power remains unchanged.

Unlocked actions appear in the tactics editor. New class defaults can use their unlocked skills; an existing saved preset is preserved rather than overwritten to insert a new action. Add/reorder a rule if that preset should use the new skill. The first member of each class supplies that class's saved preset when leaving the tactics editor or settling the run. Other members of the same class may use different per-run rules, and their individual rules remain in the run checkpoint.

## Checkpoint behavior

Startup shows the lodge. If an expedition exists, choose **Resume saved run** or explicitly **Bank & abandon** it. A pending reward/result returns to that required screen; camp returns to camp; ordinary room state returns to exploration.

Automatic checkpoints preserve:

- Seed, generator/content versions and the generation definition, including the enemy spawn pool.
- Current room, visited/discovered rooms, cleared encounters, both directions of doors, held keys, consumed searches and chest flags.
- Individual party HP/MP, statuses, potions, class, learned skills, tactics and the run's skill ranks.
- Inventory instance IDs, gear definition IDs and equipment ownership. Loaded stats already include equipment bonuses, so restoration never applies them twice.
- Cached three-choice offers, the pending offer, consumed offer IDs, camp supplies, earned gold and stable encounter reward IDs.
- Terminal combat results and the last 120 structured events for result review before acknowledgement.

Checkpoints occur when starting a run, before entering an encounter, after cleared-room travel, after combat finishes, after result acknowledgement, after opening/claiming loot, after camp actions/equipment changes and when leaving the tactics editor. Closing the normal game window also attempts a supported checkpoint. Failed writes leave the previous valid document intact and show an error with a retry control during play.

**Mid-combat turn queues are not saved.** Closing or stopping during a battle resumes at the pre-entry checkpoint with the earlier room and party resources. The same encounter is reproduced from its seed. A forced process stop or failed close-time write uses the last successfully committed checkpoint; an uncommitted UI edit can therefore be lost. Terminal results are a supported boundary and do not need to replay the battle.

## Files and transaction rules

The normal save directory is `user://progression`, inside Godot's per-user data directory for the Crawl project. It contains:

| Document | Persistent contents |
| --- | --- |
| `profile.json` | Wallet, slots, unlocks, ranks, class presets, preferred composition, next run counter and settlement ledger |
| `run.json` | Active expedition checkpoint, or a completed-run settlement receipt |
| `*.json.bak` | Last validated previous document; the initial commit also creates a backup |

Each document has envelope schema **1**, a kind, a revision, a JSON body and a SHA-256 checksum of that body. Profile/run payload version is **1**, content version is **4**, and layout generator version is **1**. Seeds are stored as strings to preserve 64-bit integer precision. Definitions are restored only by catalog IDs; a save never chooses a script or resource path to load.

Before replacement, the writer validates the candidate, flushes a temporary file in the same directory and validates it again. It preserves a validated previous primary as backup, then replaces the primary by rename. A failed profile write does not spend currency or grant the purchase in memory. A failed banking attempt retains the active run so it can retry.

Gold settlement commits the wallet change and the run's settlement ID in the **same profile replacement**. Only then is the run replaced by a receipt containing the run ID, outcome and banked amount. If interruption leaves a stale active run file, the profile ledger prevents it from banking again. If profile backup recovery predates the deposit but the run receipt is valid, that receipt restores the deposit and ledger entry together once. This also advances the run counter past the recovered ID.

Malformed/checksum-invalid primary files fall back to a semantically validated backup with a visible notice. Backup recovery may roll back the most recent checkpoint or purchase; the latest valid settlement receipt reconciles its bank deposit. If neither copy is valid, gameplay mutations are blocked and the files are retained. A missing profile with an existing run also blocks starting a fresh wallet. Recognized but unsupported schema/content versions are retained and not overwritten or silently downgraded. No migrations from other released formats exist yet.

This format supports the currently generated floor/chest content. Added authored NPC/event/switch content currently rejects checkpoint creation rather than silently dropping it; that content needs a codec/schema extension before use. Reproduction is scoped to the recorded code/content versions and compatible Godot RNG/hash behavior. Save replacement is intended for one game process writing this profile; cross-process coordination is not implemented. File flush/rename and backups provide process-crash recovery rather than a guarantee against hardware-level cache loss.

## Main implementation files

| File | Responsibility |
| --- | --- |
| `resources/ProgressionDefinition.gd` | Costs, prerequisites, party/rank caps and rank bonuses |
| `systems/progression/progression_catalog.gd` | Validated profile data, class/skill construction and primitive tactic records |
| `systems/progression/progression_controller.gd` | Purchases, unique run allocation, checkpoints, settlement and receipt reconciliation |
| `systems/progression/save_store.gd` | Checksummed envelopes, validation, temporary writes, backups and replacement |
| `systems/progression/run_codec.gd` | Primitive run snapshots and validated restoration at supported boundaries |
| `scripts/ui/hub_panel.gd` | Preparation, resume/abandon and permanent upgrade interface |
| `scripts/floor_preview.gd` | Screen routing, autosave boundaries, error notices and normal window-close handling |

Existing combat/room models continue to validate gameplay mutations. Encounter reward IDs now persist separately from room clearance as an additional idempotency guard. Gear choice and camp inventories remain per-run; the hub does not refill or modify an active expedition.

## Verification

```powershell
godot --headless --path . --script tests/test_progression.gd
godot --headless --path . --script tests/test_combat.gd
godot --headless --path . --script tests/test_floors.gd
godot --headless --path . --script tests/test_room_flow.gd
godot --path . --rendering-method gl_compatibility --script tests/test_progression_ui.gd
godot --path . --rendering-method gl_compatibility --script tests/test_ui_flow.gd
```

The progression suite has **91 passing checks** for costs, duplicate purchases, prerequisites, caps, upgraded party skills versus unchanged enemy skills, pending/chosen reward reloads, camp resources, pending/acknowledged results, stable reward IDs, victory/defeat/abandon banking, stale-run crash recovery, corrupt backup fallback, unsupported versions, failed writes/retries and receipt reconciliation without duplicate deposits.

The persistent UI suite has **150 passing checks** at **960x600**, **1280x720** and **1920x1080**, including party preparation, purchases, tactic persistence, camp autosaves, process restarts, pre-encounter resume, pending-result resume, abandon banking, boss completion, six-member parties and visible backup recovery. Screenshots under `tests/preview_hub_*.png`, `preview_upgrades_*.png`, `preview_banked_*.png` and `preview_recovery_*.png` were visually inspected. Tests use isolated `.godot` subdirectories and do not modify the normal player profile.

The existing model suites contribute **3,869 passing checks**, and the previous complete UI suite contributes **145**. Persistence tests isolate some encounters from balance; success here establishes state/transaction behavior, not final difficulty balance. Multiple floors, distinct authored boss abilities, additional content and balance remain M6 work.
