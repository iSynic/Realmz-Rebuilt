## One pinned save copy held for characters whose Character File is still waiting.

class_name SaveHold
extends RefCounted

var campaign_id: String
## The slot the edited save was written to, such as "B".
var slot_id: String
## The pinned copy's own identity in the hold store.
var hold_id: String
var package_hash: String
## Waiting characters, by party character ID, with the name the player knows them by.
var character_ids: Array[String] = []
var character_names: Array[String] = []
## Each waiting character as kept (with any edits made before the drop), encoded by CharacterStateCodec.
var characters: Array[Dictionary] = []
## The Character File identity reserved for each waiting character, or "" until its first publish attempt.
## A retry after a publish whose release failed finds that file instead of making a second one.
var file_ids: Array[String] = []


func _init(campaign: String, slot: String, hold: String, package_identity: String) -> void:
	campaign_id = campaign
	slot_id = slot
	hold_id = hold
	package_hash = package_identity


func name_of(character_id: String) -> String:
	var index := character_ids.find(character_id)
	return character_names[index] if index >= 0 else ""


func character(character_id: String) -> CharacterState:
	var index := character_ids.find(character_id)
	return CharacterStateCodec.decode(characters[index]) if index >= 0 else null


func file_id(character_id: String) -> String:
	var index := character_ids.find(character_id)
	return file_ids[index] if index >= 0 else ""


func to_data() -> Dictionary:
	return {"slot": slot_id, "packageHash": package_hash, "characterIds": character_ids, "characterNames": character_names, "characters": characters, "fileIds": file_ids}


static func from_data(campaign: String, hold: String, data: Variant) -> SaveHold:
	if not data is Dictionary:
		return null
	var fields: Dictionary = data
	for key: String in ["characterIds", "characterNames", "characters"]:
		if not fields.get(key) is Array:
			return null
	if not fields.get("slot") is String or not fields.get("packageHash") is String:
		return null
	var ids: Array = fields["characterIds"]
	var names: Array = fields["characterNames"]
	var states: Array = fields["characters"]
	# Reservations are optional: a record without them simply reserves afresh on Retry.
	var files: Array = fields.get("fileIds", []) if fields.get("fileIds") is Array else []
	if files.is_empty():
		files.resize(ids.size())
		files.fill("")
	if ids.is_empty() or names.size() != ids.size() or states.size() != ids.size() or files.size() != ids.size():
		return null
	var result := SaveHold.new(campaign, String(fields["slot"]), hold, String(fields["packageHash"]))
	for index: int in ids.size():
		if not ids[index] is String or not names[index] is String or not states[index] is Dictionary or not files[index] is String:
			return null
		if CharacterStateCodec.decode(states[index]) == null:
			return null
		result.character_ids.append(String(ids[index]))
		result.character_names.append(String(names[index]))
		result.characters.append(states[index] as Dictionary)
		result.file_ids.append(String(files[index]))
	return result
