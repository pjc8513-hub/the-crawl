class_name CrawlUpgradeDefinition
extends Resource
## A purchase composes existing definitions; IDs remain the save-game boundary.

@export_enum("class", "skill", "rank") var kind: String = "skill"
@export var class_definition: CrawlClassDefinition
@export var skill: CrawlCombatSkill
@export var cost: int = 0
@export var power_per_rank: int = 0
@export var status_chance_per_rank: int = 0
@export var default_tactic: CrawlTacticRule


func purchase_id() -> String:
	return class_definition.id if kind == "class" else skill.id


func rank_summary() -> String:
	match skill.id if skill != null else "":
		"divine_intervention": return "+%d round per rank" % power_per_rank
		"resurrect": return "+%d%% HP restored per rank" % power_per_rank
		"group_heal": return "+%d HP healed per rank" % power_per_rank
	if status_chance_per_rank == 0:
		return "+%d power per rank" % power_per_rank
	var result := "+%d%% effect chance per rank" % status_chance_per_rank
	if power_per_rank != 0:
		result += ", +%d power" % power_per_rank
	return result
