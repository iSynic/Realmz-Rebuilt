## Indexes immutable item definitions by stable and Classic identity.

class_name ItemCatalog
extends RefCounted

var _by_id: Dictionary = {}
var _by_classic_id: Dictionary = {}


func _init(definitions: Array[ItemDefinition] = []) -> void:
	for definition: ItemDefinition in definitions:
		_by_id[definition.id] = definition
	for value: Variant in _by_id.values():
		var definition := value as ItemDefinition
		if not _by_classic_id.has(definition.classic_id):
			_by_classic_id[definition.classic_id] = definition


func item_by_id(definition_id: String) -> ItemDefinition:
	return _by_id.get(definition_id) as ItemDefinition


func item_by_classic_id(classic_id: int) -> ItemDefinition:
	return _by_classic_id.get(classic_id) as ItemDefinition


func definitions() -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	var ids: Array = _by_id.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_by_id[id] as ItemDefinition)
	return result
