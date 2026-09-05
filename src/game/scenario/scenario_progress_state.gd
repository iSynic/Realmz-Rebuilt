## Stores scenario-authored progress that travels with one playthrough.

class_name ScenarioProgressState
extends RefCounted

const JOURNAL_MESSAGE_CAPACITY: int = 3000

var _party: PartyState
var encounters := ScenarioEncounterState.new()
var _searched_cells: Dictionary = {}
var _quest_values: Dictionary = {}
var _selected_character_ids: Array[String] = []
var _journal_message_ids: Dictionary = {}


func _init(party: PartyState) -> void:
	_party = party


func mark_searched(map_id: String, coordinate: Vector2i) -> void:
	_searched_cells[_cell_key(map_id, coordinate)] = true


func was_searched(map_id: String, coordinate: Vector2i) -> bool:
	return _searched_cells.has(_cell_key(map_id, coordinate))


func quest_value(quest_id: int) -> int:
	return int(_quest_values.get(quest_id, 0))


func quest_is_set(quest_id: int) -> bool:
	return quest_value(quest_id) != 0


func set_quest_value(quest_id: int, value: int) -> bool:
	if quest_id < 0 or quest_id >= 100:
		return false
	_quest_values[quest_id] = clampi(value, -32_768, 32_767)
	return true


func adjust_quest_value(quest_id: int, amount: int) -> int:
	if not set_quest_value(quest_id, quest_value(quest_id) + amount):
		return 0
	return quest_value(quest_id)


func record_journal_message(message_id: int) -> bool:
	if not journal_message_id_is_valid(message_id):
		return false
	_journal_message_ids[message_id] = true
	return true


func journal_message_is_recorded(message_id: int) -> bool:
	return _journal_message_ids.has(message_id)


func journal_message_ids() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in _journal_message_ids.keys():
		result.append(int(value))
	result.sort()
	return result


static func journal_message_id_is_valid(message_id: int) -> bool:
	return message_id >= 0 and message_id < JOURNAL_MESSAGE_CAPACITY


func selected_character_ids() -> Array[String]:
	return _selected_character_ids.duplicate()


func set_selected_character_ids(ids: Array[String]) -> bool:
	var known: Dictionary = {}
	for character: CharacterState in _party.characters():
		known[character.id] = true
	var unique: Array[String] = []
	for id: String in ids:
		if not known.has(id) or unique.has(id):
			return false
		unique.append(id)
	_selected_character_ids = unique
	return true


func selected_characters(living_only: bool = false) -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for id: String in _selected_character_ids:
		var character := _party.character_by_id(id)
		if character != null and (not living_only or character.current_health > 0):
			result.append(character)
	return result


func write_to(data: Dictionary) -> void:
	data["searchedCells"] = _sorted_string_keys(_searched_cells)
	data["questValues"] = _quest_values_for_save()
	data["selectedCharacterIds"] = _selected_character_ids.duplicate()
	data["journalMessageIds"] = journal_message_ids()
	encounters.write_to(data)


func restore_searched_cells(value: Variant) -> bool:
	if not value is Array:
		return false
	for key: Variant in value:
		if not key is String or key.is_empty():
			return false
		_searched_cells[key] = true
	return true


func restore_collections(data: Dictionary) -> bool:
	for field: String in ["questValues", "selectedCharacterIds"]:
		if not data.has(field):
			return false
	return _restore_quests(data["questValues"]) \
		and _restore_selection(data["selectedCharacterIds"]) \
		and encounters.restore_collections(data) \
		and _restore_journal(data.get("journalMessageIds", []))


func _restore_quests(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not key is String or not key.is_valid_int():
			return false
		var quest_id: int = String(key).to_int()
		var quest_value := _signed_integer(value[key])
		if quest_id < 0 or quest_id >= 100 or quest_value < -32_768 or quest_value > 32_767:
			return false
		_quest_values[quest_id] = quest_value
	return true


func _restore_selection(value: Variant) -> bool:
	if not value is Array:
		return false
	var selected: Array[String] = []
	for id: Variant in value:
		if not id is String:
			return false
		selected.append(id)
	return set_selected_character_ids(selected)


func _restore_journal(value: Variant) -> bool:
	if not value is Array:
		return false
	for raw_id: Variant in value:
		var message_id := _integer(raw_id)
		if not journal_message_id_is_valid(message_id) or journal_message_is_recorded(message_id):
			return false
		_journal_message_ids[message_id] = true
	return true


func _quest_values_for_save() -> Dictionary:
	var result: Dictionary = {}
	var quest_ids: Array = _quest_values.keys()
	quest_ids.sort()
	for quest_id: Variant in quest_ids:
		result[str(quest_id)] = _quest_values[quest_id]
	return result


static func _cell_key(map_id: String, coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [map_id, coordinate.x, coordinate.y]


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source:
		result.append(String(key))
	result.sort()
	return result
