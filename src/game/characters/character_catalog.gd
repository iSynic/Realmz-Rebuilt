## Indexes immutable Race, Caste, and character-appearance definitions.

class_name CharacterCatalog
extends RefCounted

var _races: Dictionary = {}
var _castes: Dictionary = {}
var _appearance_options: Dictionary = {}
var _appearance_by_resource: Dictionary = {}
var _application_appearance_options: Dictionary = {}
var _application_appearance_by_resource: Dictionary = {}


func _init(
		races: Array[RaceDefinition] = [],
		castes: Array[CasteDefinition] = [],
		appearance_options: Array[CharacterAppearanceDefinition] = []) -> void:
	_index_by_id(_races, races)
	_index_by_id(_castes, castes)
	for option: CharacterAppearanceDefinition in appearance_options:
		_appearance_options[option.id] = option
		_appearance_by_resource[_appearance_resource_key(option.kind, option.classic_resource_id)] = option


func race_by_id(definition_id: String) -> RaceDefinition:
	return _races.get(definition_id) as RaceDefinition


func caste_by_id(definition_id: String) -> CasteDefinition:
	return _castes.get(definition_id) as CasteDefinition


func race_definitions() -> Array[RaceDefinition]:
	var result: Array[RaceDefinition] = []
	for id: Variant in _sorted_ids(_races):
		result.append(_races[id] as RaceDefinition)
	return result


func caste_definitions() -> Array[CasteDefinition]:
	var result: Array[CasteDefinition] = []
	for id: Variant in _sorted_ids(_castes):
		result.append(_castes[id] as CasteDefinition)
	return result


func appearance_by_id(definition_id: String) -> CharacterAppearanceDefinition:
	var local := _appearance_options.get(definition_id) as CharacterAppearanceDefinition
	return local if local != null else _application_appearance_options.get(definition_id) as CharacterAppearanceDefinition


func appearance_by_resource(kind: StringName, classic_resource_id: int) -> CharacterAppearanceDefinition:
	var key := _appearance_resource_key(kind, classic_resource_id)
	var local := _appearance_by_resource.get(key) as CharacterAppearanceDefinition
	return local if local != null else _application_appearance_by_resource.get(key) as CharacterAppearanceDefinition


func appearance_definitions(kind: StringName) -> Array[CharacterAppearanceDefinition]:
	var result: Array[CharacterAppearanceDefinition] = []
	var occupied_resources: Dictionary = {}
	_append_appearance_kind(result, occupied_resources, _appearance_options, kind, false)
	_append_appearance_kind(result, occupied_resources, _application_appearance_options, kind, true)
	result.sort_custom(func(left: CharacterAppearanceDefinition, right: CharacterAppearanceDefinition) -> bool: return left.classic_resource_id < right.classic_resource_id)
	return result


func install_application_catalog(application: CharacterCatalog) -> void:
	_application_appearance_options.clear()
	_application_appearance_by_resource.clear()
	if application == null or application == self:
		return
	for kind: StringName in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
		for option: CharacterAppearanceDefinition in application.appearance_definitions(kind):
			_application_appearance_options[option.id] = option
			_application_appearance_by_resource[_appearance_resource_key(option.kind, option.classic_resource_id)] = option


func has_complete_appearance_catalog() -> bool:
	return not appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).is_empty() and not appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON).is_empty()


static func _append_appearance_kind(result: Array[CharacterAppearanceDefinition], occupied: Dictionary, source: Dictionary, kind: StringName, skip_occupied: bool) -> void:
	for value: Variant in source.values():
		var option := value as CharacterAppearanceDefinition
		if option.kind != kind or (skip_occupied and occupied.has(option.classic_resource_id)):
			continue
		result.append(option)
		occupied[option.classic_resource_id] = true


static func _index_by_id(target: Dictionary, records: Array) -> void:
	for record: Variant in records:
		target[record.id] = record


static func _sorted_ids(source: Dictionary) -> Array:
	var result: Array = source.keys()
	result.sort()
	return result


static func _appearance_resource_key(kind: StringName, classic_resource_id: int) -> String:
	return "%s:%d" % [kind, classic_resource_id]
