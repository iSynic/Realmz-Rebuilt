class_name ViewChangeSet
extends RefCounted

const PARTY_ROSTER: StringName = &"party_roster"
const PARTY_STATUS: StringName = &"party_status"
const INVENTORY: StringName = &"inventory"
const MAGIC: StringName = &"magic"
const EXPLORATION: StringName = &"exploration"
const SERVICES: StringName = &"services"
const COMBAT: StringName = &"combat"
const SYSTEM: StringName = &"system"

var complete_refresh: bool = false
var _domains: Dictionary = {}
var _character_ids: Dictionary = {}


func _init(refresh_all: bool = false) -> void:
	complete_refresh = refresh_all


func mark_domain(domain: StringName) -> void:
	_domains[domain] = true


func mark_character(character_id: String) -> void:
	if not character_id.is_empty():
		_character_ids[character_id] = true


func has_domain(domain: StringName) -> bool:
	return complete_refresh or _domains.has(domain)


func domains() -> Array[StringName]:
	var result: Array[StringName] = []
	for domain: StringName in _domains:
		result.append(domain)
	result.sort()
	return result


func affected_character_ids() -> Array[String]:
	var result: Array[String] = []
	for character_id: String in _character_ids:
		result.append(character_id)
	result.sort()
	return result
