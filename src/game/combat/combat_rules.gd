## Coordinates deterministic physical-attack and initiative rule collaborators.

class_name CombatRules
extends RefCounted

var _character_attacks: CombatCharacterAttackResolver
var _monster_attacks: CombatMonsterAttackResolver
var _initiative: CombatInitiativeRules


func _init(_condition_rules: ConditionRules, character_rules: CharacterRules) -> void:
	_character_attacks = CombatCharacterAttackResolver.new()
	_monster_attacks = CombatMonsterAttackResolver.new(character_rules)
	_initiative = CombatInitiativeRules.new()


func resolve_character_attack(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, realmz_day: int = 0, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	return _character_attacks.resolve_character_attack(attacker, equipment, defender, defender_definition, rng, realmz_day, behind, allow_fumbles, can_queue_fumble)


func resolve_character_attack_character(attacker: CharacterState, attacker_equipment: CharacterCombatEquipment, defender: CharacterState, defender_equipment: CharacterCombatEquipment, rng: RealmzRng, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	return _character_attacks.resolve_character_attack_character(attacker, attacker_equipment, defender, defender_equipment, rng, behind, allow_fumbles, can_queue_fumble)


func resolve_monster_attack(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, charm_save_bonus: int = 0, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	return _monster_attacks.resolve_monster_attack(attacker, attacker_definition, attack_index, defender, race, caste, rng, charm_save_bonus, context, allow_fumbles)


func resolve_monster_attack_monster(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	return _monster_attacks.resolve_monster_attack_monster(attacker, attacker_definition, attack_index, defender, defender_definition, rng, context, allow_fumbles)


func initiative_order(characters: Array[CharacterState], monsters: Array[MonsterState], surprise: int, rng: RealmzRng) -> Array[String]:
	return _initiative.initiative_order(characters, monsters, surprise, rng)
