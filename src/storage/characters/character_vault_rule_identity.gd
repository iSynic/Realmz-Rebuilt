## Carries the character's source rule identity independently of installed adventures.
class_name CharacterVaultRuleIdentity
extends RefCounted

var race_id: String
var caste_id: String
var race_fingerprint: String
var caste_fingerprint: String
var race_custom: bool
var caste_custom: bool


static func capture(source: ContentTransferCatalog, character: CharacterState) -> CharacterVaultRuleIdentity:
	if source == null or character == null:
		return null
	var result := CharacterVaultRuleIdentity.new()
	result.race_id = character.race_id
	result.caste_id = character.caste_id
	result.race_fingerprint = source.fingerprint(&"races", result.race_id)
	result.caste_fingerprint = source.fingerprint(&"castes", result.caste_id)
	result.race_custom = source.is_scenario_specific(&"races", result.race_id)
	result.caste_custom = source.is_scenario_specific(&"castes", result.caste_id)
	return result if _digest(result.race_fingerprint) and _digest(result.caste_fingerprint) else null


func matches_character(character: CharacterState) -> bool:
	return character != null and race_id == character.race_id and caste_id == character.caste_id


func catalog() -> ContentTransferCatalog:
	var result := ContentTransferCatalog.new()
	result.record(&"races", race_id, race_fingerprint, race_custom)
	result.record(&"castes", caste_id, caste_fingerprint, caste_custom)
	return result


func to_data() -> Dictionary:
	return {"version": 1, "raceId": race_id, "casteId": caste_id, "raceFingerprint": race_fingerprint, "casteFingerprint": caste_fingerprint, "raceCustom": race_custom, "casteCustom": caste_custom}


static func from_data(value: Variant) -> CharacterVaultRuleIdentity:
	if not value is Dictionary or value.size() != 7:
		return null
	for key: String in ["version", "raceId", "casteId", "raceFingerprint", "casteFingerprint", "raceCustom", "casteCustom"]:
		if not value.has(key):
			return null
	if not (value.version is int or value.version is float) or value.version != 1 or not value.raceId is String or value.raceId.is_empty() or not value.casteId is String or value.casteId.is_empty():
		return null
	if not _digest(value.raceFingerprint) or not _digest(value.casteFingerprint) or not value.raceCustom is bool or not value.casteCustom is bool:
		return null
	var result := CharacterVaultRuleIdentity.new()
	result.race_id = value.raceId
	result.caste_id = value.casteId
	result.race_fingerprint = value.raceFingerprint
	result.caste_fingerprint = value.casteFingerprint
	result.race_custom = value.raceCustom
	result.caste_custom = value.casteCustom
	return result


static func _digest(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true
