## Stores mutable character state inside a deterministic playthrough.

class_name CharacterState
extends RefCounted


var id: String
var name: String
var current_health: int
var maximum_health: int
var race_id: String = "realmz.race.human"
var caste_id: String = "realmz.caste.adventurer"
var gender: int = 1
var portrait_id: String = ""
var combat_icon_id: String = ""
var level: int = 1
var experience: int = 0
var age_days: int = 0
var age_group: int = 0
var brawn: int = 10
var knowledge: int = 10
var judgment: int = 10
var agility: int = 10
var vitality: int = 10
var luck: int = 10
var to_hit: int = 0
var dodge: int = 20
var missile: int = 0
var two_hand: int = 0
var hand_to_hand: int = 1
var damage_bonus: int = 0
var armor: int = 0
var magic_resistance: int = 0
var movement: int = 0
var maximum_movement: int = 10
var normal_attacks: int = 1
var attack_bonus: int = 0
var attacks_remaining: int = 1
var maximum_spell_attacks: int = 0
var spellcaster_type: int = 0
var spell_points: int = 0
var maximum_spell_points: int = 0
var carried_load: int = 0
var maximum_load: int = 0
var prestige_penalty: int = 0
var lifetime_record: CharacterLifetimeRecord
var traitor: bool = false
var conditions: ConditionSet
var money: WealthState
var _saves: Array[int] = []
var _specials: Array[int] = []
var _abilities: Array[int] = []
var _inventory: Array[ItemInstance] = []
var _known_spells: Array[String] = []
var _scroll_case: Array[SpellScrollState] = []
var _fast_spells: Array[FastSpellBindingState] = []
var save_values: Array[int]:
	get:
		return _saves.duplicate()
var special_values: Array[int]:
	get:
		return _specials.duplicate()
var ability_values: Array[int]:
	get:
		return _abilities.duplicate()


func _init(character_id: String, character_name: String, health: int, max_health: int) -> void:
	id = character_id
	name = character_name
	current_health = health
	maximum_health = max_health
	conditions = ConditionSet.new()
	money = WealthState.new()
	lifetime_record = CharacterLifetimeRecord.new()
	_saves.resize(8)
	_saves.fill(50)
	_specials.resize(12)
	_specials.fill(0)
	_abilities.resize(15)
	_abilities.fill(0)
	for index: int in 5:
		_scroll_case.append(SpellScrollState.new())
	for index: int in 10:
		_fast_spells.append(FastSpellBindingState.new())


func save_value(index: int) -> int:
	return 0 if index < 0 or index >= _saves.size() else _saves[index]


func set_save_value(index: int, value: int, enforce_creation_range: bool = true) -> bool:
	if index < 0 or index >= _saves.size():
		return false
	_saves[index] = clampi(value, -99, 120) if enforce_creation_range else value
	return true


func special_value(index: int) -> int:
	return 0 if index < 0 or index >= _specials.size() else _specials[index]


func set_special_value(index: int, value: int, enforce_classic_range: bool = true) -> bool:
	if index < 0 or index >= _specials.size():
		return false
	_specials[index] = clampi(value, -32_768, 32_767) if enforce_classic_range else value
	return true


func ability_value(index: int) -> int:
	return 0 if index < 0 or index >= _abilities.size() else _abilities[index]


func set_ability_value(index: int, value: int, enforce_classic_range: bool = true) -> bool:
	if index < 0 or index >= _abilities.size():
		return false
	_abilities[index] = clampi(value, -32_768, 32_767) if enforce_classic_range else value
	return true


func inventory() -> Array[ItemInstance]:
	return _inventory.duplicate()


func set_inventory(items: Array[ItemInstance]) -> void:
	_inventory = items.duplicate()


func known_spells() -> Array[String]:
	return _known_spells.duplicate()


func set_known_spells(spell_ids: Array[String]) -> void:
	_known_spells = spell_ids.duplicate()


func scroll_case() -> Array[SpellScrollState]:
	return _scroll_case.duplicate()


func scroll_at(index: int) -> SpellScrollState:
	return null if index < 0 or index >= _scroll_case.size() else _scroll_case[index]


func set_scroll_case(scrolls: Array[SpellScrollState]) -> bool:
	if scrolls.size() != 5:
		return false
	for scroll: SpellScrollState in scrolls:
		if scroll == null:
			return false
	_scroll_case = scrolls.duplicate()
	return true


func write_scroll(index: int, spell_id: String, power: int) -> bool:
	if index < 0 or index >= _scroll_case.size() or spell_id.is_empty() or power < 1 or power > 7:
		return false
	_scroll_case[index] = SpellScrollState.new(spell_id, power)
	return true


func clear_scroll(index: int) -> bool:
	if index < 0 or index >= _scroll_case.size():
		return false
	_scroll_case[index] = SpellScrollState.new()
	return true


func fast_spells() -> Array[FastSpellBindingState]:
	return _fast_spells.duplicate()


func fast_spell_at(index: int) -> FastSpellBindingState:
	return null if index < 0 or index >= _fast_spells.size() else _fast_spells[index]


func set_fast_spells(bindings: Array[FastSpellBindingState]) -> bool:
	if bindings.size() != 10 or bindings.any(func(binding: FastSpellBindingState) -> bool: return binding == null):
		return false
	_fast_spells = bindings.duplicate()
	return true


func bind_fast_spell(index: int, spell_id: String, power: int) -> bool:
	if index < 0 or index >= _fast_spells.size() or spell_id.is_empty() or power < 1 or power > 7:
		return false
	_fast_spells[index] = FastSpellBindingState.new(spell_id, power)
	return true


func clear_fast_spell(index: int) -> bool:
	if index < 0 or index >= _fast_spells.size():
		return false
	_fast_spells[index] = FastSpellBindingState.new()
	return true
