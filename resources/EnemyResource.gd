class_name EnemyResource
extends Resource

@export_category("Identification")
@export var id: String                    # e.g., "M-01"
@export var display_name: String          # e.g., "Kobold Wizard"
@export var species: String               # e.g., "Kobold"
@export var subtype_class: String         # e.g., "Wizard"

@export_category("Combat Stats")
@export var threat_tier: String           # e.g., "Tier 1 - Minion"
@export var hit_dice_formula: String      # e.g., HP "2d6 + 2"
@export var min_hp: int
@export var max_hp: int
@export var avg_hp: float
@export var base_strength: int = 3
@export var base_endurance: int = 3
@export var base_wisdom: int = 3
@export var base_dexterity: int = 3
@export var base_piety: int = 0
@export var base_willpower: int = 0

@export_group("bonuses and penalties")
@export var ac_bonus: int = 0          # Flat class AC modifier (negative = better in old-school convention)
@export var accuracy_bonus: int = 0
@export var initiative_bonus: int = 0
@export var bonus_damage_base: int = 0
@export var magic_amp_base: int = 0

@export_group("rewards")
@export var xp: int = 20
@export var gold: int = 10


@export_category("Spawn Rules")
@export var spawn_dice_formula: String    # e.g., "2d4 + 2"
@export var min_group_count: int
@export var max_group_count: int

@export_group("Resistances")
@export var resist_fire: bool = false
@export var resist_water: bool = false
@export var resist_earth: bool = false
@export var resist_air: bool = false
@export var resist_physical: bool = false
@export var resist_light: bool = false
@export var resist_dark: bool = false
@export var resist_spirit: bool = false


@export_category("AI & Tactics")
@export_multiline var tactical_role: String # e.g., "Backline glass-cannon; casts fire darts..."
@export var skill_id: Dictionary [StringName, float] # Skill_ID, chance to use
@export var can_flee: bool = true
@export var flee_chance: float = 0.02
@export var sprite_icon: Texture2D         # Optional icon for Warlords II style UI panel
