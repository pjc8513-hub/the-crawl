class_name CrawlEncounterSession
extends RefCounted
## Room-to-combat coordinator; reward acknowledgement is idempotent.

var floor_state: CrawlFloorState
var party: Array[CrawlCombatant] = []
var combat: CrawlCombatEngine
var result_pending: bool = false
var run_gold: int = 0
var banked_gold: int = 0
var error_message: String = ""
var skill_definitions: Dictionary = {} # Party upgrades; enemy skill definitions stay unmodified.
var claimed_rewards: Dictionary = {} # Stable encounter IDs, persisted with room state.


func encounter_id() -> String:
	return "combat:%d:%s" % [floor_state.floor_depth, floor_state.current]


func begin() -> bool:
	if floor_state == null or result_pending or (combat != null and combat.outcome == "ongoing") or floor_state.rooms[floor_state.current].is_cleared or floor_state.travel_block_reason != "":
		return false
	var seed_value := ("combat:v1:content%d:%d:%d:%s" % [floor_state.content_version, floor_state.run_seed, floor_state.floor_depth, floor_state.current]).hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("hp:%d" % seed_value).hash()
	var enemy_groups: Array[EnemyGroup] = []
	var specs: Array = floor_state.encounters.get(floor_state.current, [])
	if specs.is_empty():
		error_message = "No encounter definition for this uncleared room."
		floor_state.travel_block_reason = error_message
		return false
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var errors := CrawlEnemyValidation.errors(spec.enemy)
		var enemy_group := EnemyGroup.new()
		if not errors.is_empty() or not enemy_group.initialize_group(spec.enemy, spec.count, rng, "enemy:%03d" % index):
			error_message = "Invalid encounter content: " + str(errors)
			floor_state.travel_block_reason = error_message
			return false
		enemy_group.position_row = spec.formation
		for unit in enemy_group.units:
			unit.row = spec.formation
		enemy_groups.append(enemy_group)
	for actor in party:
		actor.statuses.clear() # Initial statuses are encounter-scoped.
		actor.defending = false
		actor.battle_armor = 0
		actor.bloodlust_bonus = 0
		actor.battle_kills = 0
	combat = CrawlCombatEngine.new()
	combat.configure(party, enemy_groups, seed_value, skill_definitions, true, banked_gold + run_gold)
	floor_state.travel_block_reason = "Combat is in progress."
	_sync_result()
	return true


func advance() -> void:
	if combat == null or result_pending:
		return
	combat.step()
	_sync_result()


func _sync_result() -> void:
	if combat.outcome != "ongoing":
		result_pending = true
		floor_state.travel_block_reason = "Review combat results before travelling."


func acknowledge() -> Dictionary:
	if not result_pending:
		return {"ok": false, "gold": 0}
	result_pending = false
	for actor in party:
		if actor.alive() and actor.meditation_percent > 0:
			actor.mp = mini(actor.max_mp, actor.mp + ceili(actor.max_mp * actor.meditation_percent / 100.0))
	var gold := 0
	if combat.outcome == "victory":
		var reward_id := encounter_id()
		if not claimed_rewards.has(reward_id):
			gold = combat.reward_gold()
			run_gold += gold
			claimed_rewards[reward_id] = true
		floor_state.resolve_current_encounter()
		floor_state.travel_block_reason = ""
	else:
		floor_state.travel_block_reason = "Run ended: %s. Start a new run to continue." % combat.outcome
	return {"ok": true, "gold": gold, "outcome": combat.outcome}
