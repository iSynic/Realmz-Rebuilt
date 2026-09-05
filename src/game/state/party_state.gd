## Stores mutable party state inside a deterministic playthrough.

class_name PartyState
extends RefCounted

var map_id: String
var coordinate: Vector2i
var _characters: Array[CharacterState]
var pooled_wealth: WealthState
var banked_wealth: WealthState
var fatigue: int = 4
var conditions: ConditionSet
var _allies: Array[MonsterState] = []
var _storage: Array[ItemInstance] = []
var _equipment_storage: Dictionary = {}
var _equipment_wealth: WealthState
var equipment_storage_active: bool = false


func _init(location_map_id: String, location: Vector2i, party_characters: Array[CharacterState]) -> void:
	map_id = location_map_id
	coordinate = location
	_characters = party_characters.duplicate()
	pooled_wealth = WealthState.new()
	banked_wealth = WealthState.new()
	_equipment_wealth = WealthState.new()
	conditions = ConditionSet.new(ConditionSet.PARTY_COUNT)


func characters() -> Array[CharacterState]:
	return _characters.duplicate()


func character_by_id(character_id: String) -> CharacterState:
	for character: CharacterState in _characters:
		if character.id == character_id:
			return character
	return null


func add_character(character: CharacterState) -> bool:
	if character == null or character.id.is_empty() or character_by_id(character.id) != null or not _items_are_unique_with(character.inventory()):
		return false
	_characters.append(character)
	return true


func owns_item_instance(item_instance_id: String) -> bool:
	if item_instance_id.is_empty():
		return false
	return item_instance_ids().has(item_instance_id)


func item_instance_ids() -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in _characters:
		for item: ItemInstance in character.inventory():
			result.append(item.id)
	for item: ItemInstance in _storage:
		result.append(item.id)
	for character_id: Variant in _equipment_storage:
		for item: ItemInstance in _equipment_storage[character_id]:
			result.append(item.id)
	return result


func has_unique_item_ownership() -> bool:
	return _items_are_unique_with([])


func remove_character(character_id: String) -> bool:
	for index: int in _characters.size():
		if _characters[index].id != character_id:
			continue
		_characters.remove_at(index)
		return true
	return false


func reorder_characters(character_ids: Array[String]) -> bool:
	if character_ids.size() != _characters.size():
		return false
	var by_id: Dictionary = {}
	for character: CharacterState in _characters:
		by_id[character.id] = character
	var seen: Dictionary = {}
	var reordered: Array[CharacterState] = []
	for character_id: String in character_ids:
		if character_id.is_empty() or seen.has(character_id) or not by_id.has(character_id):
			return false
		seen[character_id] = true
		reordered.append(by_id[character_id])
	_characters = reordered
	return true


func allies() -> Array[MonsterState]:
	return _allies.duplicate()


func set_allies(party_allies: Array[MonsterState]) -> void:
	_allies = party_allies.duplicate()


func add_ally(ally: MonsterState) -> bool:
	if ally == null:
		return false
	for current: MonsterState in _allies:
		if current.id == ally.id:
			return false
	_allies.append(ally)
	return true


func remove_allies_by_definition(definition_id: String, maximum: int = 0) -> int:
	var removed := 0
	for index: int in range(_allies.size() - 1, -1, -1):
		if _allies[index].definition_id != definition_id:
			continue
		_allies.remove_at(index)
		removed += 1
		if maximum > 0 and removed >= maximum:
			break
	return removed


func storage() -> Array[ItemInstance]:
	return _storage.duplicate()


func set_storage(items: Array[ItemInstance]) -> void:
	_storage = items.duplicate()


func add_storage_item(item: ItemInstance) -> bool:
	if item == null:
		return false
	_storage.append(item)
	return true


func capture_equipment() -> bool:
	if equipment_storage_active:
		return false
	_equipment_storage.clear()
	for character: CharacterState in _characters:
		_equipment_storage[character.id] = character.inventory()
		character.set_inventory([])
	_equipment_wealth = WealthState.new(pooled_wealth.gold, pooled_wealth.gems, pooled_wealth.jewelry)
	pooled_wealth = WealthState.new()
	equipment_storage_active = true
	return true


func restore_equipment() -> bool:
	if not equipment_storage_active:
		return false
	for character: CharacterState in _characters:
		var current_items := character.inventory()
		_storage.append_array(current_items)
		var stored: Array[ItemInstance] = []
		for value: Variant in _equipment_storage.get(character.id, []):
			if value is ItemInstance:
				stored.append(value)
		character.set_inventory(stored)
	pooled_wealth.gold += _equipment_wealth.gold
	pooled_wealth.gems += _equipment_wealth.gems
	pooled_wealth.jewelry += _equipment_wealth.jewelry
	_equipment_storage.clear()
	_equipment_wealth = WealthState.new()
	equipment_storage_active = false
	return true


func to_data() -> Dictionary:
	var character_data: Array[Dictionary] = []
	for character: CharacterState in _characters:
		character_data.append(CharacterStateCodec.encode(character))
	var ally_data: Array[Dictionary] = []
	for ally: MonsterState in _allies:
		ally_data.append(ally.to_data())
	var storage_data: Array[Dictionary] = []
	for item: ItemInstance in _storage:
		storage_data.append(item.to_data())
	var equipment_data: Dictionary = {}
	var equipment_character_ids: Array = _equipment_storage.keys()
	equipment_character_ids.sort()
	for character_id: Variant in equipment_character_ids:
		var item_data: Array[Dictionary] = []
		for item: ItemInstance in _equipment_storage[character_id]:
			item_data.append(item.to_data())
		equipment_data[character_id] = item_data
	return {
		"mapId": map_id,
		"x": coordinate.x,
		"y": coordinate.y,
		"characters": character_data,
		"pooledWealth": pooled_wealth.to_data(),
		"bankedWealth": banked_wealth.to_data(),
		"fatigue": fatigue,
		"conditions": conditions.to_data(),
		"allies": ally_data,
		"storage": storage_data,
		"equipmentStorageActive": equipment_storage_active,
		"equipmentStorage": equipment_data,
		"equipmentWealth": _equipment_wealth.to_data(),
	}


static func from_data(data: Variant) -> PartyState:
	if not data is Dictionary:
		return null
	if not _base_fields_are_valid(data):
		return null
	var x := _integer(data["x"])
	var y := _integer(data["y"])
	if x < 0 or y < 0:
		return null
	var loaded_characters_value: Variant = _characters_from_data(data["characters"])
	if loaded_characters_value == null:
		return null
	var loaded_characters: Array[CharacterState] = loaded_characters_value
	var result := PartyState.new(data["mapId"], Vector2i(x, y), loaded_characters)
	if not data.has("pooledWealth"):
		return result if result.has_unique_item_ownership() else null
	if not _restore_extended_state(result, data):
		return null
	if data.has("equipmentStorageActive") and not _restore_equipment_storage(result, data):
		return null
	return result if result.has_unique_item_ownership() else null


static func _base_fields_are_valid(data: Dictionary) -> bool:
	for field: String in ["mapId", "x", "y", "characters"]:
		if not data.has(field):
			return false
	return data["mapId"] is String and not data["mapId"].is_empty() and data["characters"] is Array


static func _characters_from_data(values: Array) -> Variant:
	var result: Array[CharacterState] = []
	for value: Variant in values:
		var character := CharacterStateCodec.decode(value)
		if character == null:
			return null
		result.append(character)
	return result


static func _restore_extended_state(result: PartyState, data: Dictionary) -> bool:
	for field: String in ["pooledWealth", "fatigue", "conditions", "allies", "storage"]:
		if not data.has(field):
			return false
	var wealth := WealthState.from_data(data["pooledWealth"])
	var banked := WealthState.from_data(data.get("bankedWealth", {"gold": 0, "gems": 0, "jewelry": 0}))
	var party_conditions := ConditionSet.from_data(data["conditions"], ConditionSet.PARTY_COUNT)
	var loaded_fatigue := _integer(data["fatigue"])
	if wealth == null or banked == null or party_conditions == null:
		return false
	if loaded_fatigue < 4 or loaded_fatigue > 135:
		return false
	if not data["allies"] is Array or not data["storage"] is Array:
		return false
	var loaded_allies_value: Variant = _allies_from_data(data["allies"])
	var stored_items_value: Variant = _items_from_data(data["storage"])
	if loaded_allies_value == null or stored_items_value == null:
		return false
	result.pooled_wealth = wealth
	result.banked_wealth = banked
	result.fatigue = loaded_fatigue
	result.conditions = party_conditions
	result._allies = loaded_allies_value
	result._storage = stored_items_value
	return true


static func _allies_from_data(values: Array) -> Variant:
	var result: Array[MonsterState] = []
	for value: Variant in values:
		var ally := MonsterState.from_data(value)
		if ally == null:
			return null
		result.append(ally)
	return result


static func _items_from_data(values: Array) -> Variant:
	var result: Array[ItemInstance] = []
	for value: Variant in values:
		var item := ItemInstance.from_data(value)
		if item == null:
			return null
		result.append(item)
	return result


static func _restore_equipment_storage(result: PartyState, data: Dictionary) -> bool:
	if not data["equipmentStorageActive"] is bool or not data.get("equipmentStorage") is Dictionary:
		return false
	var equipment_wealth := WealthState.from_data(data.get("equipmentWealth"))
	if equipment_wealth == null:
		return false
	var equipment_storage: Dictionary = {}
	for character_id: Variant in data["equipmentStorage"]:
		if not character_id is String or result.character_by_id(character_id) == null or not data["equipmentStorage"][character_id] is Array:
			return false
		var items_value: Variant = _items_from_data(data["equipmentStorage"][character_id])
		if items_value == null:
			return false
		equipment_storage[character_id] = items_value
	result.equipment_storage_active = data["equipmentStorageActive"]
	result._equipment_storage = equipment_storage
	result._equipment_wealth = equipment_wealth
	return true


func _items_are_unique_with(additional_items: Array[ItemInstance]) -> bool:
	var seen: Dictionary = {}
	for item_id: String in item_instance_ids():
		if item_id.is_empty() or seen.has(item_id):
			return false
		seen[item_id] = true
	for item: ItemInstance in additional_items:
		if item == null or item.id.is_empty() or seen.has(item.id):
			return false
		seen[item.id] = true
	return true


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
