class_name MonsterDefinition
extends RefCounted

var id: String
var classic_id: int
var classic_name_id: int
var name: String
var description: String
var not_on_menu: bool
var hit_dice: int
var stamina_bonus: int
var agility: int
var movement_max: int
var armor: int
var magic_resistance: int
var required_weapon: int
var magic_to_hit: int
var traitor: bool
var size: int
var attack_count: int
var magic_attack_count: int
var damage_bonus: int
var cast_percent: int
var run_percent: int
var surrender_percent: int
var missile_percent: int
var can_summon: int
var weapon_id: String
var random_weapon_table: int
var icon_id: int
var spell_points: int
var experience: int
var death_macro: int
var _type_flags: Array[int]
var _saves: Array[int]
var _spell_immunities: Array[int]
var _starting_conditions: Array[int]
var _money: Array[int]
var _spells: Array[String]
var _items: Array[String]
var _attacks: Array[MonsterAttackDefinition]


func _init(definition_id: String, native_id: int, display_name: String, hd: int, bonus: int, dexterity: int, armor_rating: int, magic_resist: int, type_flags: Array[int], saves: Array[int], immunities: Array[int], authored_money: Array[int], authored_spells: Array[String], authored_items: Array[String], authored_attacks: Array[MonsterAttackDefinition], authored_conditions: Array[int] = [], native_name_id: int = 0, authored_description: String = "", hidden_from_menu: bool = false) -> void:
	id = definition_id
	classic_id = native_id
	classic_name_id = native_name_id
	name = display_name
	description = authored_description
	not_on_menu = hidden_from_menu
	hit_dice = hd
	stamina_bonus = bonus
	agility = dexterity
	armor = armor_rating
	magic_resistance = magic_resist
	_type_flags = type_flags.duplicate()
	_saves = saves.duplicate()
	_spell_immunities = immunities.duplicate()
	_starting_conditions = authored_conditions.duplicate()
	_money = authored_money.duplicate()
	_spells = authored_spells.duplicate()
	_items = authored_items.duplicate()
	_attacks = authored_attacks.duplicate()
	attack_count = _attacks.size()


func type_flag(index: int) -> bool:
	return index >= 0 and index < _type_flags.size() and _type_flags[index] != 0


func save_value(index: int) -> int:
	return 0 if index < 0 or index >= _saves.size() else _saves[index]


func spell_immune(index: int) -> bool:
	return index >= 0 and index < _spell_immunities.size() and _spell_immunities[index] != 0


func starting_conditions() -> Array[int]:
	return _starting_conditions.duplicate()


func money_values() -> Array[int]:
	return _money.duplicate()


func spell_ids() -> Array[String]:
	return _spells.duplicate()


func spell_id_at(slot: int) -> String:
	return _spells[slot] if slot >= 0 and slot < _spells.size() else ""


func item_ids() -> Array[String]:
	return _items.duplicate()


func item_id_at(slot: int) -> String:
	return _items[slot] if slot >= 0 and slot < _items.size() else ""


func attacks() -> Array[MonsterAttackDefinition]:
	return _attacks.duplicate()
