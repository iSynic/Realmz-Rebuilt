## Indexes immutable monster, monster-set, and battle definitions.

class_name CombatCatalog
extends RefCounted

var _monsters: Dictionary = {}
var _base_monsters: Dictionary = {}
var _monster_by_classic_id: Dictionary = {}
var _monster_sets: Dictionary = {}
var _battles: Dictionary = {}
var _battle_by_classic_id: Dictionary = {}


func _init(
		monsters: Array[MonsterDefinition] = [],
		battles: Array[BattleDefinition] = [],
		monster_sets: Dictionary = {}) -> void:
	for monster: MonsterDefinition in monsters:
		_monsters[monster.id] = monster
		_base_monsters[monster.id] = monster
	for set_id: Variant in monster_sets:
		var records: Dictionary = {}
		for monster: MonsterDefinition in monster_sets[set_id]:
			records["classic.monster.%d" % monster.classic_id] = monster
			_monsters[monster.id] = monster
		_monster_sets[int(set_id)] = records
	for value: Variant in _monsters.values():
		var monster := value as MonsterDefinition
		if not _monster_by_classic_id.has(monster.classic_id):
			_monster_by_classic_id[monster.classic_id] = monster
	for battle: BattleDefinition in battles:
		_battles[battle.id] = battle
	for value: Variant in _battles.values():
		var battle := value as BattleDefinition
		if not _battle_by_classic_id.has(battle.classic_id):
			_battle_by_classic_id[battle.classic_id] = battle


func monster_by_id(definition_id: String) -> MonsterDefinition:
	return _monsters.get(definition_id) as MonsterDefinition


func monster_by_id_for_set(definition_id: String, set_id: int) -> MonsterDefinition:
	var records: Variant = _monster_sets.get(set_id)
	if records is Dictionary and records.has(definition_id):
		return records[definition_id] as MonsterDefinition
	return monster_by_id(definition_id)


func monster_by_classic_id(classic_id: int) -> MonsterDefinition:
	return _monster_by_classic_id.get(classic_id) as MonsterDefinition


func monster_by_classic_id_for_set(classic_id: int, set_id: int) -> MonsterDefinition:
	return monster_by_id_for_set("classic.monster.%d" % classic_id, set_id)


func available_monster_sets() -> Array[int]:
	var result: Array[int] = [0]
	for classic_set_id: int in [-1, 1]:
		if _monster_sets.has(classic_set_id):
			result.append(classic_set_id)
	var extension_sets: Array[int] = []
	for value: Variant in _monster_sets.keys():
		var set_id := int(value)
		if set_id not in [0, -1, 1]:
			extension_sets.append(set_id)
	extension_sets.sort()
	result.append_array(extension_sets)
	return result


func bestiary_definitions_for_set(set_id: int) -> Array[MonsterDefinition]:
	var result: Array[MonsterDefinition] = []
	for value: Variant in _base_monsters.values():
		var base := value as MonsterDefinition
		var definition := monster_by_id_for_set(base.id, set_id)
		if definition != null and definition.hit_dice > 0 and definition.hit_dice != 255 and not definition.not_on_menu:
			result.append(definition)
	result.sort_custom(func(left: MonsterDefinition, right: MonsterDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func battle_by_id(definition_id: String) -> BattleDefinition:
	return _battles.get(definition_id) as BattleDefinition


func battle_by_classic_id(classic_id: int) -> BattleDefinition:
	return _battle_by_classic_id.get(classic_id) as BattleDefinition
