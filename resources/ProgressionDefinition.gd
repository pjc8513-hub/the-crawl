class_name CrawlProgressionDefinition
extends Resource
## Initial economy values; purchases are validated against this definition.

@export var starting_slots: int = 3
@export var maximum_slots: int = 6
@export var slot_costs: Array[int] = [150, 350, 700]
@export var class_costs: Dictionary = {"rogue": 120}
@export var skill_unlocks: Dictionary = {
	"cleave": {"class": "warrior", "cost": 120},
	"poison_strike": {"class": "rogue", "cost": 100},
	"stun_strike": {"class": "rogue", "cost": 160}
	,"freezing_wind": {"class": "mage", "cost": 120}
	,"charming_potion": {"class": "mage", "cost": 140}
	,"earthquake": {"class": "mage", "cost": 160}
	,"combust": {"class": "mage", "cost": 200}
	,"chain_lightning": {"class": "mage", "cost": 240}
	,"magic_missile": {"class": "mage", "cost": 80}
	,"meditation": {"class": "mage", "cost": 180}
	,"mind_expansion": {"class": "mage", "cost": 180}
	,"focus": {"class": "mage", "cost": 200}
	,"intimidate": {"class": "warrior", "cost": 120}
	,"battle_harden": {"class": "warrior", "cost": 120}
	,"blood_lust": {"class": "warrior", "cost": 160}
	,"giant_slayer": {"class": "warrior", "cost": 180}
	,"berserk": {"class": "warrior", "cost": 180}
	,"aegis": {"class": "warrior", "cost": 220}
}
@export var rank_costs: Dictionary = {"attack": 60, "heal": 80, "fireball": 100, "cleave": 100, "poison_strike": 80, "stun_strike": 100, "sleep": 100, "freezing_wind": 120, "charming_potion": 140, "earthquake": 160, "combust": 200, "chain_lightning": 240}
@export var maximum_skill_rank: int = 3
@export var power_per_rank: Dictionary = {"attack": 2, "heal": 4, "fireball": 3, "cleave": 3, "poison_strike": 2, "stun_strike": 2, "sleep": 0, "freezing_wind": 2, "charming_potion": 0, "earthquake": 3, "combust": 5, "chain_lightning": 4}
