# Dungeon UI and room loop

Update 2026-10-17: the lodge, permanent purchases, gold banking and checkpoint saves are now implemented. See [PROGRESSION.md](PROGRESSION.md) for the current startup flow, save behavior and content version 4. The notes below record the earlier UI milestone.

The main scene now provides a complete single-floor screen sequence: exploration -> automatic combat -> results -> room actions -> camp or chest -> exploration, with a mandatory gear choice after the floor boss and a final run summary. The original `Main` scene structure remains in place; the unused SubViewports and ScreenFilter stay hidden.

## Controls and screens

- **Exploration:** click a yellow room. Green marks the party, yellow an available destination, red a blocked room, and blue a visited room. A blue visited dot preserves history when another state takes precedence. Symbols (`@`, `+`, `!`, `·`) supplement color. The map fits discovered rooms; it does not expose hidden rooms through its layout bounds. Hover for a movement reason. Tab to focus the map, then use arrow keys to select a discovered adjacent tile and Enter to submit movement. Selection does not bypass the movement model.
- **Persistent header:** run gold, remaining camp supplies, gear slots and standing party members stay visible. The seed field and New run control restart the prototype with fresh run state. Party tactics is available between encounters.
- **Combat:** grouped enemy rows remain on the left, individual party HP/MP/status on the right, and a bounded scrolling log below. Pause and playback speed remain the only combat controls. A terminal battle automatically opens the aftermath screen; Review combat log returns to the final combat display.
- **Aftermath:** outcome, rounds, gold to collect, downed members and loot source are shown before acknowledgement. Collect & continue awards combat gold once and releases room actions. Defeat, draw, invalid setup and stalemate finish the run without victory rewards.
- **Room actions:** search a cleared room once for a key, open an unclaimed chest, activate authored switches, or enter camp. Disabled actions show their reason on hover. Search, chest, switch and encounter state survives revisits.
- **Spoils:** chest and boss offers contain three distinct pieces from a six-item pool. Choose one item and either a party recipient or the backpack. The screen shows slot, bonuses, comparison with the current equipped slot and what happens to old equipment. At 960x600 descriptions move to hover tooltips so all three claim buttons stay visible. A full inventory requires an explicit discard; no gear is silently replaced or granted twice. Choosing a boss reward completes this prototype's one-floor run.
- **Camp:** heal, restore MP, revive a downed survivor or assign equipment. Costs and disabled reasons are visible. Returning releases the camp travel lock and leaves the party in the same room. There is no free resource refill on reopening camp.
- **Tactics:** add/remove/reorder rules, select a learned action, enable/disable a rule, and edit conditions, comparators, thresholds, selectors, reserves and minimum group size. Absolute HP values and HP percentages are separate choices. Each rule explains its current availability against a clearly labeled preview of front fighters and backline mages. The preview uses actual current party resources and does not perform actions.
- **Completion:** show the outcome, earned run gold and final gear names. Temporary gear bonuses, inventory and camp supplies are cleared. New run creates fresh party and room state.

## Provisional data and state rules

`CrawlRoomFlow` owns the room/camp/reward/end transitions and validates their mutations. `CrawlEncounterSession` continues to own combat results and once-only gold awards. Widgets send intents; they do not directly add loot, spend supplies or alter combat HP.

The initial values are intentionally small and configurable in the model: **six gear slots** total across equipped items and backpack, **six camp supplies**, **40 HP** per heal, **15 MP** per restoration, and **two supplies** for a revive at 25% max HP. Healing/restoration cost one supply. Full HP/MP, a missing MP pool, a standing revive target, exhausted supplies and unresolved combat/rewards reject the action without cost. These values are implementation defaults, not final balance decisions.

Each member can equip one weapon, one armor piece and one charm. Equipping or transferring changes actual attack, magic, armor, initiative and maximum HP/MP as appropriate. Replaced gear stays in the backpack unless explicitly discarded as part of a reward claim. Maximum resource increases do not heal or restore mana; decreases safely clamp current resources. Reassigning an already equipped item to the same member is a no-op. No equipment change revives a member.

The six initial items are Iron Edge, Ember Staff, Ward Mail, Bloodstone Charm, Focus Charm and Swift Blade. `ItemDefinition` Resources are immutable definitions; inventory entries have separate instance IDs and ownership. Offers have deterministic IDs/seeds, are cached for the run, and claim exactly one item. Gameplay mutations are synchronous, and claim controls disable during submission. Model checks reject stale offer IDs and repeated claims.

Content version is now **3**; layout generator version remains **1**. The generated chest room now has an actual `RoomInteractable` record in addition to its room type. Existing floor and combat simulation contracts are preserved, with two additional absolute-HP tactic metrics and a shared side-effect-free rule inspection method for execution and explanations.

Persistent profiles, gold banking between runs, upgrade purchases, saving/loading, additional floors, authored boss abilities, NPC dialogue and final balance remain outside this UI milestone. New run currently resets earned gold; the completion screen is a run summary rather than a persistent hub. The floor boss still uses ordinary encounter generation. These are the next progression/content integrations, not hidden functionality in the screens.

## Files

| File | Purpose |
| --- | --- |
| `scripts/floor_preview.gd` | Main screen coordinator and validated intent routing |
| `scripts/ui/game_theme.gd` | Shared dark panels, gold headings, button/focus styles and compact bars |
| `scripts/ui/results_panel.gd` | Aftermath summary and acknowledgement |
| `scripts/ui/reward_panel.gd` | Three comparable item cards, recipient selection and inventory-full handling |
| `scripts/ui/camp_panel.gd` | Supply actions and equipment assignment |
| `scripts/ui/tactics_panel.gd` | Editable ordered rules and availability explanations |
| `scripts/ui/dungeon_map.gd` | Map drawing, state symbols, selection and keyboard navigation |
| `resources/ItemDefinition.gd` | Gear definition and stat display |
| `systems/loot/room_flow.gd` | Room actions, camp costs, loot offers, equipment ownership and run-end cleanup |

## Verification

```powershell
godot --headless --path . --script tests/test_room_flow.gd
godot --headless --path . --script tests/test_combat.gd
godot --headless --path . --script tests/test_floors.gd
godot --path . --rendering-method gl_compatibility --script tests/test_floor_preview.gd
godot --path . --rendering-method gl_compatibility --script tests/test_ui_flow.gd
```

The room model suite covers **54 checks** for supply costs, no-MP/full-resource cases, revives, three distinct choices, deterministic/stale offers, duplicate claims, explicit discard, equipment transfer/replacement, no free healing, boss reward gating and cleanup. Existing combat and floor suites cover **457** and **3,358** checks respectively.

The complete UI suite covers **145 checks**, including actual control signals for tactic edits and priorities, map keyboard input, encounter -> results -> claim -> camp -> return -> chest revisit -> boss -> completion. It runs at **960x600**, **1280x720** and **1920x1080** and captures each screen. Stress coverage includes a long party/enemy name, multiple statuses, a no-MP member, a 64-creature group and a 300-event stream bounded to 120 visible log entries. The previous rendered suite also checks a 32-enemy/four-group fixture, pause and identical 1x/4x event output.

Screenshots under `tests/preview_*.png` were visually inspected. The complete-loop fixtures strengthen the party and simplify later encounters to isolate transitions; they do not establish that a normal generated run is balanced. Camp, tactics and long-content regions scroll at compact sizes rather than pushing actions beyond the window.
