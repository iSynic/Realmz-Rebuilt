## Indexes immutable spell definitions by stable and packed Classic identity.

class_name SpellCatalog
extends RefCounted

var _by_id: Dictionary = {}
var _by_classic_id: Dictionary = {}


func _init(definitions: Array[SpellDefinition] = []) -> void:
	for definition: SpellDefinition in definitions:
		_by_id[definition.id] = definition
	for value: Variant in _by_id.values():
		var definition := value as SpellDefinition
		if not _by_classic_id.has(definition.classic_id):
			_by_classic_id[definition.classic_id] = definition


func spell_by_id(definition_id: String) -> SpellDefinition:
	return _by_id.get(definition_id) as SpellDefinition


func spell_by_classic_id(classic_id: int) -> SpellDefinition:
	return _by_classic_id.get(classic_id) as SpellDefinition


func definitions() -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	var ids: Array = _by_id.keys()
	ids.sort()
	for id: Variant in ids:
		result.append(_by_id[id] as SpellDefinition)
	return result
