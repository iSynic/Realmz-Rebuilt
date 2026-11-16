## Pinned save copies held after a save edit until each kept character's Character File exists.
## Held copies live outside the slot folders, so Quick Save, automatic updates and later saves never rotate them away.

class_name SaveHoldStore
extends RefCounted

var last_error := ""
var _root_path: String
var _copies: SaveRepository


func _init(root_path: String = "user://saves-held") -> void:
	_root_path = root_path
	_copies = SaveRepository.new(root_path)


## Pins `envelope` for the waiting `characters` of `slot_id`; returns the hold, or null (see last_error).
func hold(slot_id: String, envelope: SaveEnvelope, characters: Array[CharacterState]) -> SaveHold:
	last_error = ""
	if envelope == null or characters.is_empty():
		last_error = "Nothing is waiting to be held."
		return null
	var hold_id := "%s-held-%s" % [slot_id.left(100), JSON.stringify(envelope.to_data(), "", true).sha256_text().left(8)]
	var result := SaveHold.new(envelope.campaign_id, slot_id, hold_id, envelope.package_hash)
	for character: CharacterState in characters:
		result.character_ids.append(character.id)
		result.character_names.append(character.name)
		result.characters.append(CharacterStateCodec.encode(character))
		result.file_ids.append("")
	# A live hold for this same original is never overwritten; its reservations and waiting characters stay.
	if FileAccess.file_exists(_record_path(result)):
		last_error = "Slot %s's original save is already held for characters still waiting." % slot_id
		return null
	# A copy left by an earlier hold whose record failed holds this same envelope, so it is reused.
	if not FileAccess.file_exists(_copy_path(result)) and not _copies.save_new_copy(envelope.campaign_id, hold_id, envelope):
		last_error = "The save couldn't be held: %s" % _copies.last_error
		return null
	if not _write_record(result):
		return null
	return result


## Records the Character File identity reserved for one waiting character before it is published.
func reserve_file(held: SaveHold, character_id: String, file_id: String) -> bool:
	last_error = ""
	var index := held.character_ids.find(character_id)
	if index < 0:
		return false
	held.file_ids[index] = file_id
	return _write_record(held)


## Every hold for a campaign, ordered by slot and then pinned copy.
func holds(campaign_id: String) -> Array[SaveHold]:
	var result: Array[SaveHold] = []
	var folder := _root_path.path_join(campaign_id)
	if campaign_id.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)):
		return result
	for file_name: String in DirAccess.get_files_at(folder):
		if not file_name.ends_with(".hold.json"):
			continue
		var hold_id := file_name.trim_suffix(".hold.json")
		var parsed := SaveHold.from_data(campaign_id, hold_id, JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file_name))))
		if parsed != null and FileAccess.file_exists(_copy_path(parsed)):
			result.append(parsed)
	result.sort_custom(func(left: SaveHold, right: SaveHold) -> bool: return left.hold_id.naturalnocasecmp_to(right.hold_id) < 0)
	return result


## The pinned save, or null (see last_error).
func load(held: SaveHold) -> SaveEnvelope:
	var envelope := _copies.load(held.campaign_id, held.hold_id, held.package_hash)
	last_error = "" if envelope != null else "The held save can't be read: %s" % _copies.last_error
	return envelope


## Stops holding one character. The pinned copy is deleted once no character waits on it.
func release(held: SaveHold, character_id: String) -> bool:
	last_error = ""
	var index := held.character_ids.find(character_id)
	if index < 0:
		return true
	held.character_ids.remove_at(index)
	held.character_names.remove_at(index)
	held.characters.remove_at(index)
	held.file_ids.remove_at(index)
	if not held.character_ids.is_empty():
		return _write_record(held)
	for path: String in [_copy_path(held), _copy_path(held) + ".bak", _record_path(held)]:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			last_error = "The held save couldn't be removed."
			return false
	return true


func _write_record(held: SaveHold) -> bool:
	var path := _record_path(held)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_error = "The waiting Character File couldn't be recorded."
		return false
	file.store_string(JSON.stringify(held.to_data(), "", true, true))
	file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path)) != OK:
		last_error = "The waiting Character File couldn't be recorded."
		return false
	return true


func _copy_path(held: SaveHold) -> String:
	return "%s/%s/%s.r2save" % [_root_path, held.campaign_id, held.hold_id]


func _record_path(held: SaveHold) -> String:
	return "%s/%s/%s.hold.json" % [_root_path, held.campaign_id, held.hold_id]
